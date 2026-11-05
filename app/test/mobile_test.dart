import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/mobile/platform.dart';
import 'package:dsip_app/src/screens/settings.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';
import 'fake_mobile.dart';

/// The app on a phone (app plan A5): the microphone asked for and the audio set up before the app starts, a refusal
/// told; no self-update (a store updates the app); the screens laid out for a phone's width; and the system's call
/// screen kept in step with the app's calls, what the user does there reaching the app (A5b).
void main() {
  late Directory dir;
  late FakeClient client;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-mobile');
    client = FakeClient();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Controller> open(WidgetTester tester, FakeMobile mobile) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = Controller(client, SettingsStore(dir), mobile: mobile);
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(fixture()['state'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the microphone is asked for and the audio set up before the app starts', (tester) async {
    final mobile = FakeMobile(client: client);
    await open(tester, mobile);
    expect(mobile.log.take(2), ['requestMicrophone', 'startAudio']);
    expect(client.started, isNotNull);
    expect(find.byKey(const Key('microphone-refused')), findsNothing);
  });

  testWidgets('a refused microphone still starts the app, and says why', (tester) async {
    await open(tester, FakeMobile(allow: false));
    expect(client.started, isNotNull);
    expect(find.byKey(const Key('microphone-refused')), findsOneWidget);
    expect(find.textContaining('may not use the microphone'), findsOneWidget);
  });

  testWidgets('a phone has its tabs along the bottom, and no update check of its own', (tester) async {
    await open(tester, FakeMobile());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('app-version')),
      200,
      scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.byKey(const Key('app-version')), findsOneWidget);
    expect(find.byKey(const Key('check-updates')), findsNothing);
  });

  testWidgets('on a phone a conversation opens over the list, and goes back to it', (tester) async {
    await open(tester, FakeMobile());
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    final conversation = find.byKey(const Key('conversation-MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk'));
    await tester.tap(conversation);
    await tester.pumpAndSettle();
    expect(conversation, findsNothing);
    expect(find.byKey(const Key('compose')), findsOneWidget);
    await tester.tap(find.byKey(const Key('thread-back')));
    await tester.pumpAndSettle();
    expect(conversation, findsOneWidget);
    expect(find.byKey(const Key('compose')), findsNothing);
  });

  /// The fixture's state with each call's JSON changed by [edit] (by id; null drops it).
  Map<String, dynamic> calls(Map<String, dynamic>? Function(Map<String, dynamic> call) edit) {
    final state = jsonDecode(jsonEncode(fixture()['state'])) as Map<String, dynamic>;
    state['calls'] = [
      for (final c in (state['calls'] as List).cast<Map<String, dynamic>>()) ?edit(c),
    ];
    return state;
  }

  testWidgets('the system is told of the calls: ringing in, placed and answered; and when they end', (tester) async {
    final mobile = FakeMobile();
    await open(tester, mobile);
    // the fixture: call 1 over, call 2 placed and answered, call 3 ringing in from Bob
    expect(mobile.log, [
      'requestMicrophone',
      'startAudio',
      'outgoing 2 did:key:z6MkBob did:key:z6MkBob',
      'connected 2',
      'incoming 3 Bob did:key:z6MkBob',
    ]);
    mobile.log.clear();
    client.push(calls((c) => c['id'] == 3 ? {...c, 'state': {'state': 'answered', 'answered_by': 'user'}} : c));
    await tester.pumpAndSettle();
    expect(mobile.log, ['connected 3']);
    mobile.log.clear();
    client.push(calls((c) => c['id'] == 2 ? {...c, 'state': {'state': 'ended', 'reason': 'user.hangup'}} : c));
    await tester.pumpAndSettle();
    expect(mobile.log, ['ended 2']);
  });

  Future<FakeMobile> ringing(WidgetTester tester) async {
    final mobile = FakeMobile();
    await open(tester, mobile);
    client.commands.clear();
    return mobile;
  }

  testWidgets('answered at the system: the app answers', (tester) async {
    final mobile = await ringing(tester);
    mobile.act(const SystemCallEvent(SystemCallAction.answer, 3));
    await tester.pumpAndSettle();
    expect(client.commands, [
      {'command': 'answer', 'call': 3},
    ]);
  });

  testWidgets('ended at the system: a call ringing in is declined, one answered is hung up', (tester) async {
    final mobile = await ringing(tester);
    mobile.act(const SystemCallEvent(SystemCallAction.end, 3));
    mobile.act(const SystemCallEvent(SystemCallAction.end, 2));
    await tester.pumpAndSettle();
    expect(client.commands, [
      {'command': 'decline', 'call': 3},
      {'command': 'hangup', 'call': 2},
    ]);
  });

  testWidgets('muted at the system: the app mutes or unmutes, once', (tester) async {
    final mobile = await ringing(tester);
    // call 2 is muted already
    mobile.act(const SystemCallEvent(SystemCallAction.mute, 2, on: true));
    mobile.act(const SystemCallEvent(SystemCallAction.mute, 2, on: false));
    await tester.pumpAndSettle();
    expect(client.commands, [
      {'command': 'unmute', 'call': 2},
    ]);
  });

  testWidgets('a call the system filters (Do Not Disturb, blocked) is declined; one it cannot show rings in the app', (
    tester,
  ) async {
    final mobile = await ringing(tester);
    mobile.act(const SystemCallEvent(SystemCallAction.failed, 3, reason: 'unavailable'));
    await tester.pumpAndSettle();
    expect(client.commands, isEmpty);
    mobile.act(const SystemCallEvent(SystemCallAction.failed, 3, reason: 'filtered'));
    await tester.pumpAndSettle();
    expect(client.commands, [
      {'command': 'decline', 'call': 3},
    ]);
  });

  testWidgets('what the system says of a call that is over, or not the app\'s, does nothing', (tester) async {
    final mobile = await ringing(tester);
    mobile.act(const SystemCallEvent(SystemCallAction.end, 1));
    mobile.act(const SystemCallEvent(SystemCallAction.answer, 99));
    await tester.pumpAndSettle();
    expect(client.commands, isEmpty);
  });
}
