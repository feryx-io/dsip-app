import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/mobile/platform.dart';
import 'package:dsip_app/src/screens/settings.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

/// The phone, as the app asks things of it: what it was asked, in order, and whether it allows the microphone.
class FakeMobile implements MobilePlatform {
  FakeMobile({this.allow = true, this.client});
  final bool allow;
  final FakeClient? client;
  final log = <String>[];

  @override
  Future<bool> requestMicrophone() async {
    log.add('requestMicrophone${client?.started == null ? '' : ' after start'}');
    return allow;
  }

  @override
  Future<void> startAudio() async => log.add('startAudio${client?.started == null ? '' : ' after start'}');
}

/// The app on a phone (app plan A5): the microphone asked for and the audio set up before the app starts, a refusal
/// told; no self-update (a store updates the app); the screens laid out for a phone's width.
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
    expect(mobile.log, ['requestMicrophone', 'startAudio']);
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
}
