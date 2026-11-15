import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/screens/video_tile.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';
import 'fake_mobile.dart';

void main() {
  late Directory dir;
  late FakeClient client;
  final shown = <int?>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    shown.clear();
    showTile = (stream) async {
      shown.add(stream);
      return null; // no plugin: a dark box
    };
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, {FakeMobile? mobile, bool video = true}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    final controller = Controller(client, SettingsStore(dir), mobile: mobile);
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    final state = fixture()['state'] as Map<String, dynamic>;
    if (!video) state.remove('video');
    client.push(state);
    await tester.pumpAndSettle();
  }

  testWidgets('a video call is placed from its own button, where the app has video', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('call-to')), 'did:key:z6MkCarol');
    await tester.tap(find.byKey(const Key('video-call')));
    await tester.pump();
    expect(client.commands.last, {'command': 'call', 'to': 'did:key:z6MkCarol', 'video': true});
  });

  testWidgets('no video call button where the app has no video', (tester) async {
    await open(tester, video: false);
    expect(find.byKey(const Key('video-call')), findsNothing);
  });

  testWidgets("a video call shows the far end's picture and this side's camera, and turns the camera off", (tester) async {
    await open(tester);
    // the fixture's answered call (2) carries video, its camera on
    expect(find.byKey(const Key('video-2')), findsOneWidget);
    expect(find.byKey(const Key('video-far')), findsOneWidget);
    expect(find.byKey(const Key('video-self')), findsOneWidget);
    expect(shown.toSet(), {2, null}, reason: 'its stream, and the self-view');
    await tester.tap(find.byKey(const Key('camera-2')));
    await tester.pump();
    expect(client.commands.last, {'command': 'camera', 'call': 2, 'on': false});
  });

  testWidgets("each picture keeps its own shape: a phone's upright one is tall", (tester) async {
    showTile = (stream) async => _FakeTexture(stream == null ? 1 : 2);
    tileShape = (stream) => stream == null ? const Size(640, 480) : const Size(480, 640);
    addTearDown(() => tileShape = (_) => null);
    await open(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final area = tester.getSize(find.byKey(const Key('video-far')));
    expect(area.width / area.height, closeTo(480 / 640, 0.01), reason: "the far end's upright picture");
    final self = tester.getSize(find.byKey(const Key('video-self')));
    expect(self.width / self.height, closeTo(640 / 480, 0.01), reason: "this side's own camera");
    expect(find.byType(Texture), findsNWidgets(2));
  });

  testWidgets('on a phone, a video call asks for the camera first', (tester) async {
    final mobile = FakeMobile();
    await open(tester, mobile: mobile);
    await tester.enterText(find.byKey(const Key('call-to')), 'did:key:z6MkCarol');
    await tester.tap(find.byKey(const Key('video-call')));
    await tester.pumpAndSettle();
    expect(mobile.log, contains('requestCamera'));
    expect(client.commands.last, {'command': 'call', 'to': 'did:key:z6MkCarol', 'video': true});
  });
}

class _FakeTexture implements VideoTexture {
  _FakeTexture(this.textureId);
  @override
  final int textureId;
  @override
  Future<void> close() async {}
}
