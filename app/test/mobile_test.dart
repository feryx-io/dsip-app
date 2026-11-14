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
/// screen kept in step with the app's calls, what the user does there reaching the app (A5b); where a call's audio goes
/// and the screen off at the ear (A5c); on Android the system following the core instead (A5d-2).
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
    // the fixture's answered call as an audio one: these are about where its sound goes, the video area aside
    final state = fixture()['state'] as Map<String, dynamic>;
    for (final c in (state['calls'] as List).cast<Map<String, dynamic>>()) {
      c.remove('video');
      c.remove('camera');
    }
    client.push(state);
    await tester.pumpAndSettle();
    // The routes are asked for once the calls are known, on the real event loop (the app started in runAsync).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
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

  testWidgets('where the system follows the core (Android), Dart tells it nothing and acts on nothing; the sensor stays',
      (tester) async {
    final mobile = FakeMobile(systemFollowsCore: true)
      ..routes = const AudioRoutes(current: AudioRoute.earpiece, available: [AudioRoute.earpiece, AudioRoute.speaker]);
    await open(tester, mobile);
    client.commands.clear();
    expect(mobile.log, ['requestMicrophone', 'startAudio']);
    expect(mobile.proximity, [true]);
    mobile.act(const SystemCallEvent(SystemCallAction.answer, 3));
    mobile.act(const SystemCallEvent(SystemCallAction.end, 2));
    await tester.pumpAndSettle();
    client.push(calls((c) => {...c, 'state': {'state': 'ended', 'reason': 'user.hangup'}}));
    await tester.pumpAndSettle();
    expect(mobile.log, ['requestMicrophone', 'startAudio']);
    expect(client.commands, isEmpty);
    expect(mobile.proximity, [true, false]);
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

  const phoneOnly = AudioRoutes(current: AudioRoute.earpiece, available: [AudioRoute.earpiece, AudioRoute.speaker]);
  const withCar = AudioRoutes(
    current: AudioRoute.bluetooth,
    available: [AudioRoute.earpiece, AudioRoute.speaker, AudioRoute.bluetooth],
    bluetoothName: 'Car kit',
  );

  testWidgets('with only the earpiece and the speaker, the call has a speaker switch', (tester) async {
    final mobile = FakeMobile()..routes = phoneOnly;
    await open(tester, mobile);
    final speaker = find.byKey(const Key('speaker-route'));
    // on the call answered (2), not the one ringing in (3)
    expect(speaker, findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('call-2')), matching: speaker), findsOneWidget);
    await tester.tap(speaker);
    await tester.pumpAndSettle();
    expect(mobile.routeSets, [AudioRoute.speaker]);
    mobile.route(const AudioRoutes(current: AudioRoute.speaker, available: [AudioRoute.earpiece, AudioRoute.speaker]));
    await tester.pumpAndSettle();
    await tester.tap(speaker);
    await tester.pumpAndSettle();
    expect(mobile.routeSets, [AudioRoute.speaker, AudioRoute.earpiece]);
  });

  testWidgets('with Bluetooth there, the call shows where the audio goes and lists the rest', (tester) async {
    final mobile = FakeMobile()..routes = withCar;
    await open(tester, mobile);
    expect(find.byKey(const Key('speaker-route')), findsNothing);
    final route = find.byKey(const Key('audio-route'));
    expect(find.descendant(of: route, matching: find.text('Car kit')), findsOneWidget);
    await tester.tap(route);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('route-earpiece')), findsOneWidget);
    expect(find.byKey(const Key('route-speaker')), findsOneWidget);
    expect(find.byKey(const Key('route-bluetooth')), findsOneWidget);
    await tester.tap(find.byKey(const Key('route-earpiece')));
    await tester.pumpAndSettle();
    expect(mobile.routeSets, [AudioRoute.earpiece]);
    expect(find.byKey(const Key('route-earpiece')), findsNothing, reason: 'the list closed');
  });

  testWidgets('no route control until the system says what there is', (tester) async {
    await open(tester, FakeMobile());
    expect(find.byKey(const Key('speaker-route')), findsNothing);
    expect(find.byKey(const Key('audio-route')), findsNothing);
  });

  testWidgets('the screen goes off at the ear while a call is up on the earpiece, and not on the speaker', (tester) async {
    final mobile = FakeMobile()..routes = phoneOnly;
    await open(tester, mobile);
    expect(mobile.proximity, [true]);
    mobile.route(const AudioRoutes(current: AudioRoute.speaker, available: [AudioRoute.earpiece, AudioRoute.speaker]));
    await tester.pumpAndSettle();
    expect(mobile.proximity, [true, false]);
    mobile.route(phoneOnly);
    await tester.pumpAndSettle();
    expect(mobile.proximity, [true, false, true]);
    // every call over
    client.push(calls((c) => {...c, 'state': {'state': 'ended', 'reason': 'user.hangup'}}));
    await tester.pumpAndSettle();
    expect(mobile.proximity, [true, false, true, false]);
  });

  testWidgets('a call only ringing in does not turn the screen off', (tester) async {
    final mobile = FakeMobile()..routes = phoneOnly;
    await open(tester, mobile);
    client.push(calls((c) => c['id'] == 3 ? c : null));
    await tester.pumpAndSettle();
    expect(mobile.proximity.last, isFalse);
  });

  testWidgets('a route the system refuses says why', (tester) async {
    final mobile = FakeMobile()
      ..routes = phoneOnly
      ..routeFails = PlatformExceptionLike('no speaker here');
    await open(tester, mobile);
    await tester.tap(find.byKey(const Key('speaker-route')));
    await tester.pumpAndSettle();
    expect(find.textContaining('no speaker here'), findsOneWidget);
  });

  testWidgets('on a phone, Settings has no microphone and speaker lists: the call has its route', (tester) async {
    await open(tester, FakeMobile());
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('audio-input')), findsNothing);
    expect(find.byKey(const Key('audio-output')), findsNothing);
  });
}

/// An error as a platform channel would throw one: its text is what the user is told.
class PlatformExceptionLike implements Exception {
  PlatformExceptionLike(this.message);
  final String message;
  @override
  String toString() => message;
}
