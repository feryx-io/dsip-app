import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/client.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:dsip_app/src/screens/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';
import 'package:dsip_app/src/screens/scan.dart';
import 'package:dsip_app/src/screens/backup_file.dart';

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

  testWidgets('a backup asks for the passphrase twice, then shows the recovery code (A6b)', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.byKey(const Key('backup')));
    await tester.tap(find.byKey(const Key('backup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passphrase')), 'short');
    await tester.tap(find.text('Make the code'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 10 characters.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('passphrase')), 'a long passphrase');
    await tester.enterText(find.byKey(const Key('again')), 'a long passphrase!');
    await tester.tap(find.text('Make the code'));
    await tester.pumpAndSettle();
    expect(find.text('The two passphrases differ.'), findsOneWidget);
    expect(client.exported, isEmpty);

    await tester.enterText(find.byKey(const Key('again')), 'a long passphrase');
    await tester.runAsync(() async {
      await tester.tap(find.text('Make the code'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(client.exported, [(saved['identity'] as String, 'a long passphrase')]);
    expect(client.exportedSettings, [saved], reason: 'the file keeps the servers too');
    expect(find.text('Your recovery code'), findsOneWidget);
    expect(find.text('DSIP1-AAAAA-BBBBB'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Your recovery code'), findsNothing);
  });

  /// Make a backup with [passphrase] from the settings, up to the code shown.
  Future<void> backUp(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('backup')));
    await tester.tap(find.byKey(const Key('backup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passphrase')), 'a long passphrase');
    await tester.enterText(find.byKey(const Key('again')), 'a long passphrase');
    await tester.runAsync(() async {
      await tester.tap(find.text('Make the code'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('a backup with names to keep offers its whole text to copy: the code alone does not hold them', (tester) async {
    const file = 'DSIP identity backup\n\nDSIP1-AAAAA-BBBBB\n\nDSIPC1-CCCCC-DDDDD\n';
    client.backup = const IdentityBackup(identity: 'did:key:z6MkAnn', code: 'DSIP1-AAAAA-BBBBB', file: file);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester);
    await backUp(tester);
    expect(find.textContaining('are not in the code'), findsOneWidget);
    await tester.tap(find.byKey(const Key('copy-file')));
    await tester.pumpAndSettle();
    expect(copied, file);
  });

  testWidgets('a backup is saved as a file: its whole text, the names with it, under the day\'s name', (tester) async {
    const file = 'DSIP identity backup\n\nDSIP1-AAAAA-BBBBB\n\nDSIPC1-CCCCC-DDDDD\n';
    client.backup = const IdentityBackup(identity: 'did:key:z6MkAnn', code: 'DSIP1-AAAAA-BBBBB', file: file);
    final saved = <(String, String)>[];
    saveBackupFile = (name, text) async {
      saved.add((name, text));
      return true;
    };
    addTearDown(() => saveBackupFile = (_, _) async => false);
    await open(tester);
    await backUp(tester);
    await tester.tap(find.byKey(const Key('save-file')));
    await tester.pumpAndSettle();
    expect(saved, [(backupFileName(DateTime.now()), file)]);
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('a backup file not saved says why, and the code is still shown', (tester) async {
    saveBackupFile = (_, _) async => throw Exception('no room');
    addTearDown(() => saveBackupFile = (_, _) async => false);
    await open(tester);
    await backUp(tester);
    await tester.tap(find.byKey(const Key('save-file')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The file was not saved'), findsOneWidget);
    expect(find.text('DSIP1-AAAAA-BBBBB'), findsOneWidget);
  });

  test('a backup file is named for its day, and only text of a backup\'s size is read from one', () {
    expect(backupFileName(DateTime(2026, 3, 7)), 'dsip-backup-2026-03-07.txt');
    expect(backupText(utf8.encode('DSIP1-AAAAA\n')), 'DSIP1-AAAAA\n');
    expect(() => backupText(List.filled(backupFileMax + 1, 0x41)), throwsFormatException);
    expect(() => backupText([0xff, 0xfe, 0x00]), throwsFormatException);
  });

  testWidgets('a backup with no names to keep offers the code only', (tester) async {
    await open(tester);
    await backUp(tester);
    expect(find.byKey(const Key('copy-file')), findsNothing);
    expect(find.textContaining('are not in the code'), findsNothing);
  });

  testWidgets('the identity moves to its own domain once the domain serves its document (A6d)', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('web')), 300, scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(find.byKey(const Key('web')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('web')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('web-did')), 'ann.example.com');
    await tester.tap(find.text('Make the document'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a DID that starts with did:web:'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('web-did')), 'did:web:ann.example.com');
    await tester.runAsync(() async {
      await tester.tap(find.text('Make the document'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Serve this at https://ann.example.com/.well-known/did.json, then check.'), findsOneWidget);
    expect(find.text('Move to it'), findsNothing, reason: 'not before the check');

    // the domain does not serve it yet
    client.webDiffers = ['its #key-1 is not this identity\'s key'];
    await tester.runAsync(() async {
      await tester.tap(find.text('Check'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Not yet: its #key-1'), findsOneWidget);
    expect(find.text('Move to it'), findsNothing);

    // it does: moved with the app stopped, then started again
    client.webDiffers = const [];
    await tester.runAsync(() async {
      await tester.tap(find.text('Check'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Your domain serves the document.'), findsOneWidget);
    await tester.tap(find.text('Move to it'));
    await tester.pumpAndSettle();
    expect(find.text('Move your identity?'), findsOneWidget);
    final stops = client.stops;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('web-move-sure')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    // the confirmation's answer goes on in the test's zone: let it, then the move's real work run
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(); // a spinner turns until the restarted app's first update: no settling
    expect(client.moves, [('did:web:ann.example.com', true)], reason: 'moved while the app was stopped');
    expect(client.stops, stops + 1);
    expect(client.started, saved, reason: 'started again');
  });

  testWidgets('a device is added: its join code in, the welcome code and check code out (A6)', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('add-device')), 300, scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make the welcome code'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the join code the new device shows.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('join')), 'DSIPJ1-AAAAA-BBBBB');
    await tester.runAsync(() async {
      await tester.tap(find.text('Make the welcome code'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(client.welcomed, ['DSIPJ1-AAAAA-BBBBB']);
    expect(find.byKey(const Key('welcome-code')), findsOneWidget);
    expect(find.byKey(const Key('welcome-qr')), findsOneWidget, reason: 'the welcome code as a QR code too');
    expect(find.textContaining('QX7K-2DSA'), findsOneWidget);
  });

  testWidgets('on a phone, the join code is scanned from the new device\'s screen (A6)', (tester) async {
    scanAvailable = () => true;
    scanCode = (_, prefix) async => prefix == 'DSIPJ1-' ? 'DSIPJ1-SCANNED' : null;
    addTearDown(() {
      scanAvailable = () => false;
      scanCode = (_, _) async => null;
    });
    await open(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('add-device')), 300, scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-DSIPJ1-')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Make the welcome code'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(client.welcomed, ['DSIPJ1-SCANNED']);
  });

  /// Scan [join] from the add-device dialog, then make the welcome code.
  Future<void> scanAndWelcome(WidgetTester tester, String join) async {
    scanAvailable = () => true;
    scanCode = (_, prefix) async => join;
    addTearDown(() {
      scanAvailable = () => false;
      scanCode = (_, _) async => null;
    });
    await open(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('add-device')), 300, scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-DSIPJ1-')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Make the welcome code'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('a join code scanned with where the new device listens: the welcome code is sent there (A6)', (tester) async {
    client.sendTo = '192.168.1.20:40123';
    await scanAndWelcome(tester, 'DSIPJ1-SCANNED/192.168.1.20:40123');
    expect(find.text('DSIPJ1-SCANNED'), findsNothing, reason: 'the field is gone once the welcome code is made');
    expect(client.welcomed, ['DSIPJ1-SCANNED'], reason: 'the code alone in the field');
    expect(client.sent, [('DSIPJ1-SCANNED/192.168.1.20:40123', 'DSIPW2-q1bKTClKzSvJLM6sUrJSSkzJyy9KTcxRqsoDAA')]);
    expect(find.byKey(const Key('welcome-sent')), findsOneWidget);
    expect(find.textContaining('QX7K-2DSA'), findsOneWidget, reason: 'the check code to compare');
    expect(find.byKey(const Key('welcome-qr')), findsNothing, reason: 'nothing to scan: it was sent');
  });

  testWidgets('a welcome code that could not be sent is shown to scan or type instead (A6)', (tester) async {
    client.sendFails = Exception('no route');
    await scanAndWelcome(tester, 'DSIPJ1-SCANNED/192.168.1.20:40123');
    expect(find.byKey(const Key('welcome-not-sent')), findsOneWidget);
    expect(find.textContaining('no route'), findsOneWidget);
    expect(find.byKey(const Key('welcome-qr')), findsOneWidget);
  });

  testWidgets('a join code typed carries nowhere to send to: nothing is sent (A6)', (tester) async {
    await scanAndWelcome(tester, 'DSIPJ1-SCANNED');
    expect(client.sent, isEmpty);
    expect(find.byKey(const Key('welcome-qr')), findsOneWidget);
  });
}
