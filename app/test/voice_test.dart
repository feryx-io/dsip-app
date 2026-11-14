// Voice messages and voicemail (found on devices: a declined call left nothing, and the app had no voice messages): a
// voice message plays from its bubble and stops; one is recorded from the conversation and sent; after a call placed
// here goes unanswered, a voicemail is offered when the app's core says the callee takes one, recorded to their limit
// and sent with the call's session; and a voicemail arriving while the app is behind is told as one.

import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alerts_test.dart' show FakeAlerter;
import 'fake_client.dart';

const group = 'MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk';
const voicePath = '/home/alice/.local/share/dsip/media/01M6EKRTVG3C55DFMQ401G3MC2.ogg';

void main() {
  late Directory dir;
  late FakeClient client;
  late FakeAlerter alerter;
  late Controller controller;
  late Map<String, dynamic> state;
  final m = messagesFixture();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    client.answer = (cmd) => switch (cmd['command']) {
      'thread' => m['thread'] as Map<String, dynamic>,
      'stop_recording' => {'response': 'recorded', 'path': '/rec/1.ogg', 'duration_ms': 3400},
      'send_audio' => {'response': 'conversation', 'conversation': group},
      'voicemail_offer' => {'response': 'voicemail', 'offer': true, 'max_duration_s': 120},
      _ => {'response': 'ok'},
    };
    alerter = FakeAlerter();
    controller = Controller(client, SettingsStore(dir), alerter: alerter);
    state = fixture()['state'] as Map<String, dynamic>;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, dynamic> copy(Map<String, dynamic> s) => jsonDecode(jsonEncode(s)) as Map<String, dynamic>;

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(state);
    await tester.pumpAndSettle();
  }

  Future<void> conversation(WidgetTester tester) async {
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-$group')));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> withVoice(Map<String, dynamic> voice) => copy(state)..['voice'] = voice;

  testWidgets('a voice message plays from its bubble, and stops', (tester) async {
    await open(tester);
    await conversation(tester);
    expect(find.text('Voice message · 0:04'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('play-01M6EKRTVG3C55DFMQ401G3MC5'))).onPressed, isNull,
        reason: 'a voicemail not yet fetched does not play');

    await tester.tap(find.byKey(const Key('play-01M6EKRTVG3C55DFMQ401G3MC2')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'play', 'path': voicePath});
    client.push(withVoice({'playing': voicePath}));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Stop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-01M6EKRTVG3C55DFMQ401G3MC2')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'stop_playing'});
  });

  testWidgets('a voice message is recorded in the conversation and sent there, or dropped', (tester) async {
    // not during a call: the call has the microphone
    state['calls'] = [for (final c in state['calls'] as List) if (((c as Map)['state'] as Map)['state'] == 'ended') c];
    await open(tester);
    await conversation(tester);
    await tester.tap(find.byKey(const Key('record')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'record', 'max_s': 300});
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    client.push(withVoice({'recording': {'running': true, 'started_at': now - 2}}));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('recorder')), findsOneWidget);
    expect(find.textContaining('Recording 0:0'), findsOneWidget);
    expect(find.byKey(const Key('compose')), findsNothing, reason: 'the bar takes the composer\'s place');

    await tester.tap(find.byKey(const Key('record-send')));
    await tester.pump();
    expect(client.commands.reversed.take(2).toList().reversed, [
      {'command': 'stop_recording'},
      {'command': 'send_audio', 'to': group, 'path': '/rec/1.ogg', 'purpose': 'voice-message'},
    ]);
    client.push(state);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('recorder')), findsNothing);

    // stopped at its limit, then dropped
    await tester.tap(find.byKey(const Key('record')));
    await tester.pump();
    client.push(withVoice({'recording': {'running': false, 'started_at': now, 'max_ms': 300000, 'duration_ms': 300000}}));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recorded 5:00 / 5:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record-drop')));
    await tester.pump();
    expect(client.commands.last, {'command': 'cancel_recording'});
    client.push(state);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('after a call placed here goes unanswered, a voicemail is offered, recorded and sent', (tester) async {
    await open(tester);
    final declined = copy(state);
    final call = {
      'session': '01M6BTTMQ9QMKY9SYTY8415VZ7', 'peer': 'did:key:z6MkBob', 'direction': 'outgoing', 'answered': false,
      'reason': 'user.declined', 'ended_at': 1794200500,
    };
    declined['history'] = [...declined['history'] as List, call];
    client.push(declined, {'change': 'history', 'history': declined['history']});
    // the core's answer comes after the change, on the real event loop the updates are listened on
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'voicemail_offer', 'to': 'did:key:z6MkBob', 'reason': 'user.declined'});
    expect(find.byKey(const Key('voicemail-offer')), findsOneWidget);
    expect(find.text('did:key:z6MkBob didn\'t answer'), findsOneWidget, reason: 'Bob has no name here');
    expect(find.text('Leave a voicemail? Up to 2:00.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('voicemail-record')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'record', 'max_s': 120});
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    client.push(copy(declined)..['voice'] = {'recording': {'running': true, 'started_at': now, 'max_ms': 120000}});
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('/ 2:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record-send')));
    await tester.pump();
    await tester.pump();
    expect(client.commands.last, {
      'command': 'send_audio',
      'to': 'did:key:z6MkBob',
      'path': '/rec/1.ogg',
      'purpose': 'voicemail',
      'session': '01M6BTTMQ9QMKY9SYTY8415VZ7',
    });
    client.push(declined);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voicemail-offer')), findsNothing);
    expect(find.text('Voicemail sent.'), findsOneWidget);

    // one answered, or taken here, offers nothing
    final more = copy(declined);
    more['history'] = [
      ...more['history'] as List,
      {...call, 'session': '01M6BTTMQ9QMKY9SYTY8415VZ8', 'direction': 'incoming'},
      {...call, 'session': '01M6BTTMQ9QMKY9SYTY8415VZ6', 'answered': true, 'reason': 'user.hangup'},
    ];
    final asked = client.commands.length;
    client.push(more, {'change': 'history', 'history': more['history']});
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(client.commands.skip(asked).where((c) => c['command'] == 'voicemail_offer'), isEmpty);
  });

  testWidgets('no voicemail is offered where the core says not', (tester) async {
    client.answer = (cmd) => switch (cmd['command']) {
      'voicemail_offer' => {'response': 'voicemail', 'offer': false},
      _ => {'response': 'ok'},
    };
    await open(tester);
    final s = copy(state);
    s['history'] = [
      ...s['history'] as List,
      {'session': 'S', 'peer': 'did:key:z6MkBob', 'direction': 'outgoing', 'answered': false, 'reason': 'user.blocked',
       'ended_at': 1794200500},
    ];
    client.push(s, {'change': 'history', 'history': s['history']});
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(client.commands.last['command'], 'voicemail_offer');
    expect(find.byKey(const Key('voicemail-offer')), findsNothing);
  });

  testWidgets('a voicemail arriving while the app is behind is told as one', (tester) async {
    await open(tester);
    controller.foreground = false;
    final thread = (m['thread'] as Map)['messages'] as List;
    final vm = thread.firstWhere((x) => (x as Map)['purpose'] == 'voicemail') as Map<String, dynamic>;
    client.push(state, {'change': 'message', 'message': vm});
    await tester.pumpAndSettle();
    expect((alerter.shown.last.$2.title, alerter.shown.last.$2.body), ('did:key:z6MkBob', 'Voicemail'));
  });
}
