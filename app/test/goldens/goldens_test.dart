// Golden screenshots of every screen, light and dark (app plan A3), at a desktop's size and a phone's (A5, `phone-`):
// one set, made on Linux, compared on Linux, Windows and macOS. "The same on every desktop" is this test passing on
// all three; at a phone's size, a screen that does not fit fails it (an overflow is an error in a test).
//
// Drawn with the app's own fonts (Inter, Material Icons), from the fixtures `dsip-app`'s `wire_fixture` test makes, so
// what is shown is what the app sends. Made again after a deliberate change to a screen:
//   flutter test test/goldens --update-goldens

import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/models.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_client.dart';
import 'tolerant_comparator.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// The app's fonts, as the bundle declares them: tests otherwise draw text in a placeholder font.
Future<void> loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// The state every screen is drawn from: the fixtures' calls, conversation, request, presence and sound devices.
Map<String, dynamic> seeded() {
  final state = fixture()['state'] as Map<String, dynamic>;
  (state['presence'] as Map<String, dynamic>)['following'] = _fixture('presence')['following'];
  state['audio'] = (_fixture('settings')['audio'] as Map<String, dynamic>)['audio'];
  return state;
}

void main() {
  setUpAll(() async {
    await loadFonts();
    useTolerantGoldens();
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dsip-app-golden'));
  tearDown(() => dir.deleteSync(recursive: true));

  for (final (prefix, size) in [('', const Size(1100, 760)), ('phone-', const Size(390, 844))]) {
  for (final brightness in Brightness.values) {
    final theme = brightness.name;

    /// The app on [tab] (by its label; null: the first run), after [arrange], against `<name>-<theme>.png`.
    Future<void> shot(
      WidgetTester tester,
      String name, {
      String? tab,
      Future<void> Function(WidgetTester tester)? arrange,
      UpdateInfo? release,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final client = FakeClient()
        ..answer = (cmd) => switch (cmd['command']) {
          'thread' => _fixture('messages')['thread'] as Map<String, dynamic>,
          _ => {'response': 'ok'},
        };
      client.release = release;
      final controller = Controller(client, SettingsStore(dir));
      if (tab != null) await tester.runAsync(() => SettingsStore(dir).save(_fixture('settings')['settings'] as Map<String, dynamic>));
      await tester.pumpWidget(DsipApp(controller: controller));
      await tester.runAsync(controller.load);
      if (tab != null) {
        client.push(seeded());
        await tester.pumpAndSettle();
        if (release != null) await controller.checkForUpdate();
        await tester.tap(find.text(tab).last);
      }
      await tester.pumpAndSettle();
      if (arrange != null) await arrange(tester);
      await tester.pumpAndSettle();
      await expectLater(find.byType(DsipApp), matchesGoldenFile('$prefix$name-$theme.png'));
    }

    testWidgets('first run, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) => shot(tester, 'first_run'));

    testWidgets('calls, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) => shot(tester, 'calls', tab: 'Calls'));

    testWidgets('messages, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) async {
      await shot(
        tester,
        'messages',
        tab: 'Messages',
        arrange: (tester) => tester.tap(find.byKey(const Key('conversation-MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk'))),
      );
    });

    testWidgets('contacts, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) => shot(tester, 'contacts', tab: 'Contacts'));

    testWidgets('presence, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) => shot(tester, 'presence', tab: 'Presence'));

    testWidgets('me, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) => shot(tester, 'me', tab: 'Me'));

    testWidgets('settings, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) => shot(tester, 'settings', tab: 'Settings'));

    testWidgets('an update, $theme${prefix.isEmpty ? '' : ', phone'}', (tester) async {
      await shot(
        tester,
        'update',
        tab: 'Presence',
        release: const UpdateInfo(
          version: '0.2.0',
          notes: 'https://github.com/feryx-io/dsip-app/releases/tag/v0.2.0',
          canInstall: true,
        ),
      );
    });
  }
  }
}
