import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/models.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

const group = 'MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk';

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;
  late Map<String, dynamic> state;
  final m = messagesFixture();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    client.answer = (cmd) => switch (cmd['command']) {
      'thread' => m['thread'] as Map<String, dynamic>,
      'message' || 'create_group' => m['conversation'] as Map<String, dynamic>,
      _ => {'response': 'ok'},
    };
    controller = Controller(client, SettingsStore(dir));
    state = fixture()['state'] as Map<String, dynamic>;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The app started, its state the fixture's, on the Messages screen.
  Future<void> open(WidgetTester tester, [Map<String, dynamic>? s]) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(s ?? state);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
  }

  test('a message and a thread are read whole', () {
    final t = [for (final x in (m['thread'] as Map)['messages'] as List) MessageView.fromJson(x as Map<String, dynamic>)];
    expect(t.map((x) => x.mine), [true, false, false, false]);
    expect((t[3].kind, t[3].name, t[3].contentType, t[3].size, t[3].attachment), ('file', 'plan.pdf', 'application/pdf', 48213, true));
    expect((t[1].audio, t[1].voicemail, t[1].durationMs, t[1].purpose), (true, false, 4200, 'voice-message'));
    expect(
      (t[2].audio, t[2].voicemail, t[2].durationMs, t[2].session),
      (true, true, 12640, '01M6EKRTVG3C55DFMQ401G3MC0'),
    );
    expect(t[0].attachment, isFalse);
    expect(t[1].text, isNull);
    expect(t[1].kind, 'audio');
    expect(shortDid('did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK'), 'did:key:z6MkhaXg…2doK');
    expect(shortDid('did:key:z6MkBob'), 'did:key:z6MkBob');
  });

  testWidgets('a request not named by the user says the name it offers', (tester) async {
    state.remove('names');
    await open(tester);
    expect(find.text('Carol (says they are)'), findsOneWidget);
  });

  testWidgets('a request is answered from the list', (tester) async {
    await open(tester);
    expect(find.text('Asking to message you'), findsOneWidget);
    // the fixture's names: Carol named by the user, so not as she says she is
    expect(find.text('Carol Jones'), findsOneWidget);
    expect(find.text('Carol (says they are)'), findsNothing);
    await tester.tap(find.byTooltip('Accept'));
    await tester.tap(find.byTooltip('Decline'));
    expect(client.commands, [
      {'command': 'accept_request', 'id': '01M6EKRTVG3C55DFMQ401G3MB0'},
      {'command': 'decline_request', 'id': '01M6EKRTVG3C55DFMQ401G3MB0'},
    ]);
  });

  testWidgets('an introduction accepted opens the conversation with it on top, made by the first message', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    final intro = find.byKey(const Key('introduction-did:key:z6MkCarol'));
    expect(find.descendant(of: intro, matching: find.text('Carol Jones introduced themselves')), findsOneWidget);
    expect(find.descendant(of: intro, matching: find.text('We met at the conference')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('compose')), 'great to meet you');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(client.commands.sublist(0, 2), [
      {'command': 'accept_request', 'id': '01M6EKRTVG3C55DFMQ401G3MB0'},
      {'command': 'message', 'to': 'did:key:z6MkCarol', 'text': 'great to meet you'},
    ]);
    // the conversation made is the one open
    expect(client.commands.last, {'command': 'thread', 'conversation': group});
  });

  testWidgets('an introduction of yours, accepted, opens the conversation with it on top', (tester) async {
    final introduced = ((state['messaging'] as Map)['introduced'] as List).cast<Map<String, dynamic>>();
    introduced.first['accepted'] = true;
    await open(tester);
    await tester.tap(find.byKey(const Key('introduced-did:key:z6MkDave')));
    await tester.pumpAndSettle();
    final intro = find.byKey(const Key('introduction-did:key:z6MkDave'));
    expect(find.descendant(of: intro, matching: find.text('You introduced yourself')), findsOneWidget);
    expect(find.descendant(of: intro, matching: find.text('Lunch on Friday?')), findsOneWidget);
    expect(find.byKey(const Key('compose')), findsOneWidget);
  });

  testWidgets('a conversation opens on its thread, takes what arrives, and sends', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('conversation-$group')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'thread', 'conversation': group});
    expect(find.text('hello Bob'), findsOneWidget);
    expect(find.text('Voice message · 0:04'), findsOneWidget);
    expect(find.text('Voicemail · 0:12 · Downloading…'), findsOneWidget, reason: 'not fetched yet');
    expect(find.text('1 message not yet at the hub'), findsOneWidget);

    client.push(state, m['message'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    expect(find.text('hi Alice'), findsOneWidget);
    client.push(state, m['message'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    expect(find.text('hi Alice'), findsOneWidget, reason: 'the same message once');

    await tester.enterText(find.byKey(const Key('compose')), 'see you at four');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'message', 'to': group, 'text': 'see you at four'});
    expect(tester.widget<TextField>(find.byKey(const Key('compose'))).controller!.text, isEmpty);
  });

  testWidgets('first contact: introduce yourself, then message, or make a group', (tester) async {
    await open(tester);
    await tester.tap(find.text('Introduce yourself').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-0')), 'did:key:z6MkDave');
    await tester.enterText(find.byKey(const Key('field-1')), 'we met at the conference');
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'introduce', 'to': 'did:key:z6MkDave', 'purpose': 'we met at the conference'});
    expect(find.text('Asked. You can message them once they accept.'), findsOneWidget);

    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-0')), 'did:key:z6MkBob\ndid:key:z6MkDave  ');
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(client.commands.reversed.skip(1).first, {'command': 'create_group', 'members': ['did:key:z6MkBob', 'did:key:z6MkDave']});
    expect(client.commands.last, {'command': 'thread', 'conversation': group}, reason: 'the group made is opened');
  });

  testWidgets('a grant that arrives is told', (tester) async {
    await open(tester);
    client.push(state, m['granted'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    expect(find.textContaining('accepted: you can message them'), findsOneWidget);
  });

  testWidgets('without a mailbox, messaging says it is off', (tester) async {
    final noMailbox = Map<String, dynamic>.from(state)..['messaging'] = {'connected': false, 'conversations': [], 'requests': []};
    await open(tester, noMailbox);
    expect(find.textContaining('Messaging is off'), findsOneWidget);
  });
}
