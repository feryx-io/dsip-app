import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

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

  testWidgets('the first run makes an identity, saves the settings and starts the app', (tester) async {
    await open(tester);
    expect(find.text('Welcome to DSIP'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(client.started, isNull);

    await tester.enterText(find.byKey(const Key('name')), 'Alice');
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
    await tester.enterText(find.byKey(const Key('mailbox')), 'wss://mailbox.example.com:9443/dsip');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('A mailbox needs its DID too.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('mailbox-did')), 'did:key:z6MkMailbox');
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
    await tester.enterText(find.byKey(const Key('relay')), 'wss://relay.example.com:8443/dsip');
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
    await tester.tap(find.descendant(of: answered, matching: find.text('Unmute')));
    await tester.tap(find.descendant(of: answered, matching: find.text('Hang up')));
    expect(find.text('Ended: user.hangup'), findsOneWidget);

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
