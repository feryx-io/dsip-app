// The store screenshots (app plan A7; store/README.md), drawn from the goldens' fixtures with the app's own fonts at the
// sizes the stores ask for, light theme. Not part of `flutter test`; made with, from app/:
//   flutter test test_store/screenshots_test.dart --update-goldens
// into ../store/screenshots/<device>-<n>-<screen>.png.

import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/fake_client.dart';
import '../test/goldens/goldens_test.dart' show loadFonts, seeded;

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Each store's device: its name, its size in logical pixels, and its pixel ratio.
const devices = <(String, Size, double)>[
  ('iphone-6.9', Size(430, 932), 3), // 1290 × 2796, App Store's required iPhone size
  ('ipad-13', Size(1032, 1376), 2), // 2064 × 2752, App Store's iPad size
  ('android-phone', Size(360, 640), 3), // 1080 × 1920, Google Play
  ('desktop', Size(1440, 900), 1), // 1440 × 900, the Mac App Store's smallest, and the download pages
];

/// The screens shown, in order: a tab's label (null: the first run), and what to do there first.
final shots = <(String, String?, Future<void> Function(WidgetTester)?)>[
  ('calls', 'Calls', null),
  ('messages', 'Messages', (t) => t.tap(find.byKey(const Key('conversation-MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk')))),
  ('presence', 'Presence', null),
  ('settings', 'Settings', null),
  ('first-run', null, null),
];

void main() {
  setUpAll(loadFonts);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dsip-app-store'));
  tearDown(() => dir.deleteSync(recursive: true));

  for (final (device, size, ratio) in devices) {
    for (final (i, (name, tab, arrange)) in shots.indexed) {
      testWidgets('$device: $name', (tester) async {
        tester.view.physicalSize = size * ratio;
        tester.view.devicePixelRatio = ratio;
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final client = FakeClient()
          ..answer = (cmd) => switch (cmd['command']) {
            'thread' => _fixture('messages')['thread'] as Map<String, dynamic>,
            _ => {'response': 'ok'},
          };
        final controller = Controller(client, SettingsStore(dir));
        if (tab != null) {
          await tester.runAsync(() => SettingsStore(dir).save(_fixture('settings')['settings'] as Map<String, dynamic>));
        }
        await tester.pumpWidget(DsipApp(controller: controller));
        await tester.runAsync(controller.load);
        if (tab != null) {
          client.push(seeded());
          await tester.pumpAndSettle();
          await tester.tap(find.text(tab).last);
        }
        await tester.pumpAndSettle();
        if (arrange != null) await arrange(tester);
        await tester.pumpAndSettle();
        await expectLater(find.byType(DsipApp), matchesGoldenFile('../../store/screenshots/$device-${i + 1}-$name.png'));
      });
    }
  }
}
