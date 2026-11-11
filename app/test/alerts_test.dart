// Alerts (found on real devices: nothing told of a new message): from the system while the app is not in front, in the
// app while it is, none for the conversation being read; each kind, and all of them, turned off in the settings; on by
// default, and kept.

import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/alerts.dart';
import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

const group = 'MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk';

/// The system's notifications, as a list.
class FakeAlerter implements Alerter {
  final shown = <(int, Alert)>[];
  final cancelled = <int>[];
  void Function(String)? opened;

  @override
  Future<void> init(void Function(String payload) opened) async => this.opened = opened;

  @override
  Future<void> show(int id, Alert alert) async => shown.add((id, alert));

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

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
      _ => {'response': 'ok'},
    };
    alerter = FakeAlerter();
    controller = Controller(client, SettingsStore(dir), alerter: alerter);
    state = fixture()['state'] as Map<String, dynamic>;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(state);
    await tester.pumpAndSettle();
  }

  Future<void> push(WidgetTester tester, Map<String, dynamic> change, [Map<String, dynamic>? s]) async {
    client.push(s ?? state, change);
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> message = m['message'] as Map<String, dynamic>;

  testWidgets('a message while the app is behind: the system says who and what, and opens the conversation', (tester) async {
    await open(tester);
    controller.foreground = false;
    await push(tester, message);
    final (_, a) = alerter.shown.single;
    expect((a.title, a.body, a.payload), ('did:key:z6MkBob', 'hi Alice', 'conversation:$group'));

    alerter.opened!(a.payload);
    await tester.pumpAndSettle();
    expect(controller.tab, Tabs.messages);
    expect(client.commands.last, {'command': 'thread', 'conversation': group}, reason: 'the conversation is opened');
  });

  testWidgets('a message while the app is in front: told in the app, unless its conversation is open', (tester) async {
    await open(tester);
    await push(tester, message);
    expect(alerter.shown, isEmpty);
    expect(find.text('did:key:z6MkBob: hi Alice'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(controller.tab, Tabs.messages);
    expect(controller.visibleConversation, group);

    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
    await tester.pumpAndSettle();
    await push(tester, message);
    expect(find.byKey(const Key('alert')), findsNothing, reason: 'it is being read');
    expect(alerter.shown, isEmpty);
  });

  testWidgets('a request, a missed call, and a call ringing while a desktop app is behind', (tester) async {
    await open(tester);
    controller.foreground = false;
    final before = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    final messaging = state['messaging'] as Map<String, dynamic>;
    messaging['requests'] = [
      ...messaging['requests'] as List,
      {'id': '01M6EKRTVG3C55DFMQ401G3MB1', 'from': 'did:key:z6MkErin', 'name': 'Erin', 'purpose': 'about the band'},
    ];
    await push(tester, {'change': 'requests', 'requests': messaging['requests']});
    expect(alerter.shown.map((x) => (x.$2.title, x.$2.body)), [('Erin asks to message you', 'about the band')]);

    final history = state['history'] as List;
    state['history'] = [
      ...history,
      {'session': 'S-missed', 'peer': 'did:key:z6MkErin', 'peer_name': 'Erin', 'direction': 'incoming', 'answered': false,
       'reason': 'user.cancelled', 'ended_at': 1794200300},
      {'session': 'S-declined', 'peer': 'did:key:z6MkErin', 'direction': 'incoming', 'answered': false,
       'reason': 'user.declined', 'ended_at': 1794200400},
    ];
    await push(tester, {'change': 'history', 'history': state['history']});
    expect(alerter.shown.last.$2.title, 'Missed call from Erin');
    expect(alerter.shown.length, 2, reason: 'one declined here is not missed');

    final ringing = (before['calls'] as List).firstWhere((c) => (c as Map)['id'] == 3) as Map<String, dynamic>;
    await push(tester, {'change': 'call_added', 'call': ringing});
    expect((alerter.shown.last.$2.title, alerter.shown.last.$2.payload), ('Bob is calling', 'calls'));
  });

  testWidgets("a desktop's ringing call is answered or declined from its alert, which goes when it stops ringing",
      (tester) async {
    await open(tester);
    controller.foreground = false;
    final ringing = (state['calls'] as List).firstWhere((c) => (c as Map)['id'] == 3) as Map<String, dynamic>;
    await push(tester, {'change': 'call_added', 'call': ringing});
    final (id, a) = alerter.shown.last;
    expect(a.call, isTrue);
    expect([for (final b in a.actions) (b.id, b.label)], [('answer:3', 'Answer'), ('decline:3', 'Decline')]);

    alerter.opened!('answer:3');
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'answer', 'call': 3});
    expect(controller.tab, Tabs.calls);
    alerter.opened!('decline:3');
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'decline', 'call': 3});
    alerter.opened!('answer:99');
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'decline', 'call': 3}, reason: 'no call 99 rings here: nothing is done');
    expect(alerter.cancelled, isEmpty, reason: 'still ringing');

    // answered (here, or anywhere): the alert goes, once
    final answered = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    final call = (answered['calls'] as List).firstWhere((c) => (c as Map)['id'] == 3) as Map<String, dynamic>;
    call['state'] = {'state': 'ended', 'reason': 'user.cancelled'};
    await push(tester, {'change': 'call_changed', 'call': call}, answered);
    await push(tester, {'change': 'call_changed', 'call': call}, answered);
    expect(alerter.cancelled, [id]);
  });

  testWidgets('alerts are on by default, turned off by kind or all at once, and kept', (tester) async {
    await open(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('alerts-calls')), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('alerts-enabled'))).value, isTrue);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('alerts-messages'))).value, isTrue);

    await tester.tap(find.byKey(const Key('alerts-messages')));
    await tester.pumpAndSettle();
    controller.foreground = false;
    await push(tester, message);
    expect(alerter.shown, isEmpty, reason: 'messages are off');

    await tester.tap(find.byKey(const Key('alerts-enabled')));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('alerts-calls'))).onChanged, isNull);
    final a = controller.alertSettings;
    expect((a.enabled, a.messages, a.calls), (false, false, true));
  });

  test('the alert settings are kept in alerts.json, and default to on', () async {
    expect((await AlertSettings.load(dir)).enabled, isTrue);
    await const AlertSettings(enabled: false, requests: false).save(dir);
    final kept = await AlertSettings.load(dir);
    expect((kept.enabled, kept.messages, kept.requests, kept.calls), (false, true, false, true));
    File('${dir.path}/alerts.json').writeAsStringSync('not json');
    expect((await AlertSettings.load(dir)).enabled, isTrue, reason: 'a broken file is the defaults');
  });
}
