// Accessibility (app plan A7), every screen at a desktop's size and a phone's, light and dark, from the fixtures the
// goldens draw: Flutter's guidelines for tap targets (48 dp on Android, 44 on iOS), labels on everything tappable, and
// text contrast (WCAG AA); and every screen at twice the text size without overflowing (an overflow is an error here).

import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';
import 'goldens/goldens_test.dart' show loadFonts, seeded;

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// The screens: a tab's label (null: the first run), what to do there first, and whether Flutter's sampling contrast
/// guideline reads it right. It reads the colours inside each text's semantics rectangle; on two screens that
/// rectangle is not the text's: a segmented button's takes in its outline (4.28 measured, the outline's against the
/// surface), and a message bubble in the scrolled thread is placed in the list's coordinates, over the app bar. Every
/// colour pair those screens draw text in is checked exactly instead (`the theme's text colours meet AA`).
final screens = <(String, String?, Future<void> Function(WidgetTester)?, bool)>[
  ('first run', null, null, false),
  ('calls', 'Calls', null, true),
  ('messages', 'Messages', (t) => t.tap(find.byKey(const Key('conversation-MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk'))), false),
  ('contacts', 'Contacts', null, true),
  ('presence', 'Presence', null, true),
  ('me', 'Me', null, true),
  ('settings', 'Settings', null, true),
];

/// WCAG 2's contrast ratio of two colours.
double contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUpAll(loadFonts);

  // the app's theme, as app.dart makes it: a teal seed, light and dark
  for (final brightness in Brightness.values) {
    test("the theme's text colours meet AA (4.5:1), ${brightness.name}", () {
      final c = ThemeData(colorSchemeSeed: Colors.teal, brightness: brightness).colorScheme;
      final pairs = {
        'text on the surface': (c.onSurface, c.surface),
        'secondary text on the surface': (c.onSurfaceVariant, c.surface),
        'text on raised surfaces (bubbles, cards)': (c.onSurface, c.surfaceContainerHighest),
        'text on the navigation bar': (c.onSurface, c.surfaceContainer),
        'own message bubble': (c.onPrimaryContainer, c.primaryContainer),
        'a chosen segment, a selected tab': (c.onSecondaryContainer, c.secondaryContainer),
        'a filled button': (c.onPrimary, c.primary),
        'links and text buttons': (c.primary, c.surface),
        'errors': (c.error, c.surface),
        'the hang-up button': (c.onError, c.error),
        'an error container': (c.onErrorContainer, c.errorContainer),
      };
      for (final MapEntry(key: what, value: (fg, bg)) in pairs.entries) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: what);
      }
    });
  }

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dsip-app-a11y'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// The app at [size], [brightness] and [textScale], on [tab] after [arrange].
  Future<void> open(WidgetTester tester, Size size, Brightness brightness, String? tab,
      Future<void> Function(WidgetTester)? arrange, {double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
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
      await tester.tap(find.text(tab).last);
    }
    await tester.pumpAndSettle();
    if (arrange != null) await arrange(tester);
    await tester.pumpAndSettle();
  }

  for (final (form, size) in [('desktop', const Size(1100, 760)), ('phone', const Size(390, 844))]) {
    for (final (name, tab, arrange, sampled) in screens) {
      testWidgets('$name, $form: tap targets and labels', (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester, size, Brightness.light, tab, arrange);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      });

      for (final brightness in sampled ? Brightness.values : const <Brightness>[]) {
        testWidgets('$name, $form, ${brightness.name}: text contrast', (tester) async {
          final semantics = tester.ensureSemantics();
          await open(tester, size, brightness, tab, arrange);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantics.dispose();
        });
      }

      testWidgets('$name, $form: twice the text size fits', (tester) async {
        await open(tester, size, Brightness.light, tab, arrange, textScale: 2);
        expect(MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first)).scale(10), 20, reason: 'drawn at twice the size');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a call ringing in is announced to a screen reader', (tester) async {
    final said = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
      final data = (m as Map)['data'] as Map?;
      if (m['type'] == 'announce' && data != null) said.add(data['message'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
    await open(tester, const Size(1100, 760), Brightness.light, 'Calls', null);
    // the fixture's call 3 rings here
    expect(said.where((m) => m.startsWith('Incoming call: ')), isNotEmpty, reason: '$said');
  });

  testWidgets('the first run is done from the keyboard: Tab reaches each field and Start', (tester) async {
    await open(tester, const Size(1100, 760), Brightness.light, null, null);
    Future<Set<String>> tabThrough() async {
      final reached = <String>{};
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        final key = focused?.findAncestorWidgetOfExactType<TextFormField>()?.key ??
            focused?.findAncestorWidgetOfExactType<TextButton>()?.key ??
            focused?.widget.key;
        if (key is ValueKey<String>) reached.add(key.value);
        if (focused?.findAncestorWidgetOfExactType<FilledButton>() != null) reached.add('start');
      }
      return reached;
    }

    expect(await tabThrough(), containsAll(['name', 'server', 'by-hand', 'start']));
    await tester.tap(find.byKey(const Key('by-hand')));
    await tester.pumpAndSettle();
    expect(await tabThrough(), containsAll(['name', 'relay', 'mailbox', 'mailbox-did', 'hints', 'start']));
  });

  testWidgets('the calls from the keyboard, from any tab: answer, mute, hang up, decline', (tester) async {
    final client = FakeClient();
    final controller = Controller(client, SettingsStore(dir));
    await tester.runAsync(() => SettingsStore(dir).save(_fixture('settings')['settings'] as Map<String, dynamic>));
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(seeded());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Presence').last); // another tab: the keys work wherever the app is
    await tester.pumpAndSettle();
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    // the fixture: call 3 rings here, and another is up
    await press(LogicalKeyboardKey.enter);
    expect(client.commands.last, {'command': 'answer', 'call': 3});
    await press(LogicalKeyboardKey.backspace);
    expect(client.commands.last, {'command': 'decline', 'call': 3}, reason: 'the call ringing in, first');
    final up = (seeded()['calls'] as List).cast<Map<String, dynamic>>().firstWhere((c) => (c['state'] as Map)['state'] == 'answered');
    await press(LogicalKeyboardKey.keyM);
    expect(client.commands.last, {'command': up['muted'] == true ? 'unmute' : 'mute', 'call': up['id']});
  });
}
