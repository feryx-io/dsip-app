import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/client.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';
import 'package:dsip_app/src/screens/scan.dart';
import 'package:dsip_app/src/screens/backup_file.dart';

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    controller = Controller(client, SettingsStore(dir));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    // not settled: until the app's first update a spinner turns
    await tester.pump();
  }

  /// The relay and mailbox typed in rather than found at a server.
  Future<void> byHand(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('by-hand')));
    await tester.tap(find.byKey(const Key('by-hand')));
    await tester.pumpAndSettle();
  }

  testWidgets('the first run finds its servers at feryx.io, or at the server the user names', (tester) async {
    client.servers['feryx.io'] = {
      'relay': 'wss://relay1.feryx.io/dsip',
      'mailbox': {'uri': 'wss://mailbox1.feryx.io/dsip', 'did': 'did:web:mailbox1.feryx.io'},
      'hints_nodes': ['https://hints.feryx.io'],
      'stun': ['stun:turn.feryx.io:3478'],
    };
    await open(tester);
    expect(find.byKey(const Key('relay')), findsNothing, reason: 'no addresses to type');
    expect(tester.widget<TextFormField>(find.byKey(const Key('server'))).controller!.text, 'feryx.io');
    await tester.enterText(find.byKey(const Key('name')), 'Alice');

    // a server listing none: said, and nothing started
    await tester.enterText(find.byKey(const Key('server')), 'example.org');
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not get the servers from example.org'), findsOneWidget);
    expect(client.started, isNull);
    expect(client.identities, isEmpty);

    await tester.enterText(find.byKey(const Key('server')), ' feryx.io ');
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final identity = SettingsStore(dir).defaultIdentity;
    expect(client.discovered, ['example.org', 'feryx.io']);
    expect(client.identities, [(identity, 'Alice')]);
    expect(client.started, {
      'identity': identity,
      'relay': 'wss://relay1.feryx.io/dsip',
      'mailbox': {'uri': 'wss://mailbox1.feryx.io/dsip', 'did': 'did:web:mailbox1.feryx.io'},
      'hints_nodes': ['https://hints.feryx.io'],
      'stun': ['stun:turn.feryx.io:3478'],
      'server': 'feryx.io',
    });
  });

  testWidgets('the first run makes an identity, saves the settings and starts the app', (tester) async {
    await open(tester);
    expect(find.text('Welcome to DSIP'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(client.started, isNull);

    await tester.enterText(find.byKey(const Key('name')), 'Alice');
    await byHand(tester);
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
    await tester.enterText(find.byKey(const Key('mailbox')), 'wss://mailbox.example.com:9443/dsip');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('A mailbox needs its DID too.'), findsOneWidget);
    expect(find.textContaining('Messages need a hints node too'), findsOneWidget, reason: 'nobody finds the mailbox');
    await tester.enterText(find.byKey(const Key('mailbox-did')), 'did:key:z6MkMailbox');
    await tester.enterText(find.byKey(const Key('hints')), 'hints.example.com');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.textContaining('starting with https:// or http://'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hints')), 'https://hints.example.com');
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    final identity = SettingsStore(dir).defaultIdentity;
    expect(client.identities, [(identity, 'Alice')]);
    final settings = {
      'identity': identity,
      'relay': 'wss://relay.example.com:8443/dsip',
      'mailbox': {'uri': 'wss://mailbox.example.com:9443/dsip', 'did': 'did:key:z6MkMailbox'},
      'hints_nodes': ['https://hints.example.com'],
    };
    expect(client.started, settings);
    expect(await tester.runAsync(() => SettingsStore(dir).load()), settings, reason: 'kept for the next start');

    client.push(fixture()['state'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    expect(find.text('Calls'), findsOneWidget);
  });

  testWidgets('an existing identity folder makes no new identity', (tester) async {
    await open(tester);
    await tester.tap(find.text('Use an identity folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('folder')), '/home/alice/.dsip/alice');
    await byHand(tester);
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(client.identities, isEmpty);
    expect(client.started?['identity'], '/home/alice/.dsip/alice');
  });

  testWidgets("an identity restored from its recovery code is this install's (A6b)", (tester) async {
    await open(tester);
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    await byHand(tester);
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the recovery code.'), findsOneWidget);
    expect(find.text('Enter the passphrase.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code')), ' DSIP1-AAAAA-BBBBB ');
    await tester.enterText(find.byKey(const Key('passphrase')), 'a long passphrase');
    await tester.enterText(find.byKey(const Key('name')), 'Ann');
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final identity = SettingsStore(dir).defaultIdentity;
    expect(client.restored, [(identity, 'DSIP1-AAAAA-BBBBB', 'a long passphrase', 'Ann')]);
    expect(client.identities, isEmpty, reason: 'restored, not made');
    expect(client.started?['identity'], identity);
  });

  testWidgets('an identity is restored from a backup file: its text, the names with it (A6b)', (tester) async {
    const file = 'DSIP identity backup\n\nDSIP1-AAAAA-BBBBB\n\nDSIPC1-CCCCC-DDDDD\n';
    openBackupFile = () async => file;
    addTearDown(() => openBackupFile = () async => null);
    await open(tester);
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('open-file')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passphrase')), 'a long passphrase');
    await tester.enterText(find.byKey(const Key('name')), 'Ann');
    await byHand(tester);
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
    await tester.ensureVisible(find.text('Start'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final identity = SettingsStore(dir).defaultIdentity;
    expect(client.restored, [(identity, file.trim(), 'a long passphrase', 'Ann')]);
  });

  testWidgets('a backup file that keeps its servers starts with them: none typed, none looked up', (tester) async {
    const file = 'DSIP identity backup\n\nDSIP1-AAAAA-BBBBB\n\nDSIPC1-CCCCC-DDDDD\n';
    final kept = {
      'relay': 'wss://relay.example.com:8443/dsip',
      'mailbox': {'uri': 'wss://mailbox.example.com:9443/dsip', 'did': 'did:key:z6MkMailbox'},
      'hints_nodes': ['http://hints.example.com:8090'],
    };
    client.backupServersKept = kept;
    openBackupFile = () async => file;
    addTearDown(() => openBackupFile = () async => null);
    await open(tester);
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('also brings back the servers'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('open-file')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name')), 'Ann');

    // the wrong passphrase: said, and nothing restored
    await tester.enterText(find.byKey(const Key('passphrase')), 'not the passphrase');
    await tester.ensureVisible(find.text('Start'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('does not open'), findsOneWidget);
    expect(client.restored, isEmpty);

    await tester.enterText(find.byKey(const Key('passphrase')), 'a long passphrase');
    await tester.ensureVisible(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final identity = SettingsStore(dir).defaultIdentity;
    expect(client.restored, [(identity, file.trim(), 'a long passphrase', 'Ann')]);
    expect(client.started, {...kept, 'identity': identity});
    expect(client.discovered, isEmpty, reason: 'the server field (feryx.io) is not asked');
  });

  testWidgets('a file that is not a backup says so, and nothing is restored', (tester) async {
    openBackupFile = () async => throw const FormatException('too large to be a backup');
    addTearDown(() => openBackupFile = () async => null);
    await open(tester);
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('open-file')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be read as a backup'), findsOneWidget);
    expect(client.restored, isEmpty);
  });

  testWidgets('another device joins by the codes, without making an identity (A6)', (tester) async {
    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Join another device'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('DSIP1-AAAAA-BBBBB'), findsNothing);
    expect(find.text('DSIPJ1-AAAAA-BBBBB'), findsOneWidget);
    expect(find.text('Check code: QX7K-2DSA'), findsOneWidget);
    expect(find.byKey(const Key('join-qr')), findsOneWidget, reason: 'the join code as a QR code too');
    expect(find.byKey(const Key('scan-DSIPW')), findsNothing, reason: 'no camera to scan with on a desktop');
    await byHand(tester);
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Enter the welcome code from the other device.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('welcome')), ' DSIPW1-abc ');
    await tester.ensureVisible(find.text('Start'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final identity = SettingsStore(dir).defaultIdentity;
    expect(client.finished, [(identity, 'DSIPW1-abc')]);
    expect(client.identities, isEmpty, reason: 'joined, not made');
    expect(client.started?['identity'], identity);
  });

  testWidgets('the welcome code comes back over the local network: whose it is is said before Start (A6)', (tester) async {
    client.listenQr = 'DSIPJ1-AAAAA-BBBBB/192.168.1.20:40123';
    client.toReceive = const WelcomeReceived(welcome: 'DSIPW2-SENT', identity: 'did:key:z6MkAnn', name: 'Ann');
    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Join another device'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('DSIPJ1-AAAAA-BBBBB'), findsOneWidget, reason: 'the code as text, without the addresses');
    expect(find.textContaining('Received from Ann (did:key:z6MkAnn)'), findsOneWidget);
    expect(client.handoffStopped, isTrue, reason: 'one welcome code, then no more listening');
    expect(client.finished, isEmpty, reason: 'nothing joins until Start');
    await byHand(tester);
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
    await tester.ensureVisible(find.text('Start'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(client.finished, [(SettingsStore(dir).defaultIdentity, 'DSIPW2-SENT')]);
  });

  testWidgets('on a phone, the welcome code is scanned from the other device\'s screen (A6)', (tester) async {
    scanAvailable = () => true;
    final asked = <String>[];
    scanCode = (_, prefix) async {
      asked.add(prefix);
      return 'DSIPW2-SCANNED';
    };
    addTearDown(() {
      scanAvailable = () => false;
      scanCode = (_, _) async => null;
    });
    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Join another device'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('scan-DSIPW')));
    await tester.tap(find.byKey(const Key('scan-DSIPW')));
    await tester.pump();
    expect(asked, ['DSIPW']);
    expect(tester.widget<TextField>(find.descendant(of: find.byKey(const Key('welcome')), matching: find.byType(TextField))).controller!.text,
        'DSIPW2-SCANNED');
  });

  testWidgets('with settings saved, the app starts at once and shows its calls', (tester) async {
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await open(tester);
    expect(client.started, {'identity': '/x', 'relay': 'wss://r/dsip'});
    client.push(fixture()['state'] as Map<String, dynamic>);
    await tester.pumpAndSettle();

    // the call ringing here is answered or declined; the answered one hangs up or mutes
    final ringing = find.byKey(const Key('call-3'));
    expect(find.descendant(of: ringing, matching: find.text('Incoming call')), findsOneWidget);
    await tester.tap(find.descendant(of: ringing, matching: find.text('Answer')));
    final answered = find.byKey(const Key('call-2'));
    expect(find.descendant(of: answered, matching: find.text('In call')), findsOneWidget);
    // its sound counted stage by stage, and where it stopped
    expect(
      find.descendant(of: answered, matching: find.text('Sound: mic 250 · sent 250 · heard 248 · decoded 248 · played 0 · ringback 100')),
      findsOneWidget,
    );
    expect(find.descendant(of: answered, matching: find.text('speaker: stream disconnected')), findsOneWidget);
    await tester.tap(find.descendant(of: answered, matching: find.text('Unmute')));
    await tester.tap(find.descendant(of: answered, matching: find.text('Hang up')));
    // why it ended in words, the code in the tooltip (§15)
    expect(find.textContaining('Ended · '), findsOneWidget);
    expect(find.byTooltip('Reason code: user.hangup'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('call-to')), 'did:key:z6MkCarol');
    await tester.tap(find.text('Call'));
    await tester.pump();
    expect(client.commands, [
      {'command': 'answer', 'call': 3},
      {'command': 'unmute', 'call': 2},
      {'command': 'hangup', 'call': 2},
      {'command': 'call', 'to': 'did:key:z6MkCarol'},
    ]);
  });

  testWidgets('a command that fails says why', (tester) async {
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    client.answer = (_) => {'response': 'error', 'message': 'no such identity'};
    await open(tester);
    client.push(fixture()['state'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('call-to')), 'did:key:nobody');
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(find.text('no such identity'), findsOneWidget);
  });

  testWidgets('Me shows the identity to give others', (tester) async {
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await open(tester);
    client.push(fixture()['state'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    expect(find.text('did:key:z6MkAlice'), findsOneWidget);
    expect(find.text('did:key:z6MkMailbox · Connected'), findsOneWidget);
  });
}
