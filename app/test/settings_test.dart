import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

/// The settings fixture, from `dsip-app`'s `wire_fixture` test: an `audio` change with microphones and speakers (a
/// speaker chosen), and `Settings` with every field the screen edits, which `dsip-app` reads back.
Map<String, dynamic> settingsFixture() =>
    jsonDecode(File('test/fixtures/settings.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;
  late Map<String, dynamic> state;
  late Map<String, dynamic> saved;
  final f = settingsFixture();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    controller = Controller(client, SettingsStore(dir));
    state = fixture()['state'] as Map<String, dynamic>;
    state['audio'] = (f['audio'] as Map<String, dynamic>)['audio'];
    saved = {...f['settings'] as Map<String, dynamic>};
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The app started from the fixture's settings, on the Settings screen.
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.runAsync(() => SettingsStore(dir).save(saved));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(state);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  String shown(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField))).controller!.text;

  testWidgets('the devices chosen show, and a new choice is made and kept', (tester) async {
    await open(tester);
    expect(shown(tester, 'audio-input'), "The system's default");
    expect(shown(tester, 'audio-output'), 'USB headset');

    await tester.tap(find.byKey(const Key('audio-input')));
    await tester.pumpAndSettle();
    expect(find.text("Built-in microphone (the system's default)").last, findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(MenuItemButton, 'USB headset').hitTestable().first);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Look for devices again'));
    await tester.pump();

    expect(client.commands, [
      {'command': 'choose_audio', 'input': 'mic-2', 'output': 'spk-2'},
      {'command': 'audio_devices'},
    ]);
    final kept = await tester.runAsync(() => SettingsStore(dir).load());
    expect((kept!['audio_input'], kept['audio_output']), ('mic-2', 'spk-2'));
  });

  testWidgets('back to the default, and a refused choice is not kept', (tester) async {
    await open(tester);
    client.answer = (_) => {'response': 'error', 'message': 'no output device "spk-2"'};
    await tester.tap(find.byKey(const Key('audio-output')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(MenuItemButton, "The system's default").hitTestable().first);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(client.commands, [
      {'command': 'choose_audio'},
    ]);
    expect(find.textContaining('no output device'), findsOneWidget);
    final kept = await tester.runAsync(() => SettingsStore(dir).load());
    expect(kept!['audio_output'], 'spk-2');
  });

  testWidgets('with the tone host there is nothing to choose', (tester) async {
    (state['audio'] as Map<String, dynamic>)['host'] = 'tone';
    await open(tester);
    expect(find.textContaining('test tone'), findsOneWidget);
    expect(find.byKey(const Key('audio-input')), findsNothing);
  });

  testWidgets('the connection is edited, saved, and the app starts again with it', (tester) async {
    await open(tester);
    expect(shown(tester, 'settings-relay'), 'wss://relay.example.com:8443/dsip');
    expect(shown(tester, 'settings-mailbox-did'), 'did:key:z6MkMailbox');
    expect(shown(tester, 'settings-stun'), 'stun:stun.example.com:3478');
    expect(find.text('/home/alice/.local/share/dsip/identity'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('settings-relay')), 'wss://relay.other.example:8443/dsip');
    await tester.enterText(find.byKey(const Key('settings-hints')), '');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Calls in progress end'), findsOneWidget, reason: 'the fixture has a call up');
    await tester.tap(find.text('Restart'));
    // the dialog closes, then the settings file is written (real IO) and the app started
    for (var i = 0; i < 50 && client.started?['relay'] != 'wss://relay.other.example:8443/dsip'; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }

    final want = {...saved, 'relay': 'wss://relay.other.example:8443/dsip'}..remove('hints_nodes');
    expect(client.stops, 1);
    expect(client.started, want);
    expect(await tester.runAsync(() => SettingsStore(dir).load()), want, reason: 'kept for the next start');
    client.push(state);
    await tester.pumpAndSettle();
    expect(find.text('Sound'), findsOneWidget, reason: 'back on the settings screen');
  });

  testWidgets('a relay that is not wss, or a mailbox without its DID, is not saved', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('settings-relay')), 'relay.example.com');
    await tester.enterText(find.byKey(const Key('settings-mailbox-did')), '');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a relay address starting with wss://.'), findsOneWidget);
    expect(find.text('A mailbox needs its DID too.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(client.stops, 0);
  });

  testWidgets('cancelled, nothing restarts', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.stops, 0);
  });
}
