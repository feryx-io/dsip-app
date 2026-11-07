// Ready for translation (app plan A7): every screen, at a desktop's size and a phone's, in the pseudo-locale en_XA
// (every message accented, bracketed and a third longer: tool/pseudo_l10n.py), and laid out right to left. An
// overflow is an error in a test, so a screen that cannot take a longer translation, or does not mirror, fails here;
// text drawn in the pseudo-locale and still plain English is not in the ARB.

import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accessibility_test.dart' show screens;
import 'fake_client.dart';
import 'goldens/goldens_test.dart' show loadFonts, seeded;

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  setUpAll(loadFonts);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dsip-app-locales'));
  tearDown(() {
    DsipApp.textDirection = null;
    dir.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester, Size size, String? tab, Future<void> Function(WidgetTester)? arrange) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final client = FakeClient()
      ..answer = (cmd) => switch (cmd['command']) {
        'thread' => _fixture('messages')['thread'] as Map<String, dynamic>,
        _ => {'response': 'ok'},
      };
    final controller = Controller(client, SettingsStore(dir));
    if (tab != null) await tester.runAsync(() => SettingsStore(dir).save(_fixture('settings')['settings'] as Map<String, dynamic>));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    if (tab != null) {
      client.push(seeded());
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(tab).last);
    }
    await tester.pumpAndSettle();
    if (arrange != null) await arrange(tester);
    await tester.pumpAndSettle();
  }

  for (final (form, size) in [('desktop', const Size(1100, 760)), ('phone', const Size(390, 844))]) {
    for (final (name, tab, arrange, _) in screens) {
      testWidgets('$name, $form, en_XA: a longer translation fits', (tester) async {
        tester.platformDispatcher.localesTestValue = const [Locale('en', 'XA')];
        await open(tester, size, tab == null ? null : _pseudo(tab), arrange);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('['), findsWidgets, reason: 'drawn in the pseudo-locale');
      });

      testWidgets('$name, $form: laid out right to left', (tester) async {
        DsipApp.textDirection = TextDirection.rtl;
        await open(tester, size, tab, arrange);
        expect(tester.takeException(), isNull);
        expect(Directionality.of(tester.element(find.byType(Scaffold).first)), TextDirection.rtl);
      });
    }
  }
}

/// A tab's label as en_XA draws it (accented), for finding it.
String _pseudo(String label) {
  const plain = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const accented = 'àƀçđéƒĝĥíĵķĺɱñóþǫŕšţúṽŵẋýžÀƁÇĐÉƑĜĤÍĴĶĹḾÑÓÞǪŔŠŢÚṼŴẊÝŽ';
  return String.fromCharCodes(label.runes.map((r) {
    final i = plain.runes.toList().indexOf(r);
    return i < 0 ? r : accented.runes.elementAt(i);
  }));
}
