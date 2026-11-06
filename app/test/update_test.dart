import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/models.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:dsip_app/src/screens/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

const release = UpdateInfo(
  version: '0.2.0',
  notes: 'https://github.com/thevoiceguy/dsip-app/releases/tag/v0.2.0',
  canInstall: true,
);

/// The settings screen's list (the page has other scrollables).
Finder settingsList() => find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;
  late Map<String, dynamic> state;
  late int quits;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    quits = 0;
    controller = Controller(client, SettingsStore(dir), quit: () => quits++);
    state = fixture()['state'] as Map<String, dynamic>;
    // no call up: the fixture's calls ended
    for (final c in state['calls'] as List) {
      (c as Map<String, dynamic>)['state'] = {'state': 'ended', 'reason': 'user.hangup'};
    }
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(state);
    await tester.pumpAndSettle();
  }

  /// Frames, and turns of the real event loop: stopping the app cancels its update stream, which completes there.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  testWidgets('a check by hand finds nothing newer, then a release', (tester) async {
    await open(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('DSIP 0.1.0'), 300, scrollable: settingsList());
    expect(find.text('DSIP 0.1.0'), findsOneWidget);
    expect(find.byKey(const Key('update-banner')), findsNothing);

    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();
    expect(find.text('This is the latest version.'), findsOneWidget);

    client.release = release;
    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();
    // under About here; the banner is at the list's top, out of view since the list scrolled down to About
    expect(find.text('DSIP 0.2.0 is out.'), findsWidgets);
    await tester.scrollUntilVisible(find.byKey(const Key('update-banner')), -300, scrollable: settingsList());
    expect(find.descendant(of: find.byKey(const Key('update-banner')), matching: find.text('DSIP 0.2.0 is out.')), findsOneWidget);
  });

  testWidgets('update and restart looks again, fetches, stops the app, installs and quits', (tester) async {
    client.release = release;
    await open(tester);
    await controller.checkForUpdate();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update and restart'));
    await settle(tester);
    expect(client.checks, 2, reason: 'looked again before installing');
    expect(client.updating, ['download', 'install']);
    expect(client.stops, 1);
    expect(quits, 1);
  });

  testWidgets('an install that fails starts the app again and says why', (tester) async {
    client.release = release;
    client.installFails = Exception('the setup is missing');
    await open(tester);
    await controller.checkForUpdate();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update and restart'));
    await settle(tester);
    expect(quits, 0);
    expect(client.started, isNotNull);
    expect(client.stops, 1);
    expect(find.textContaining('the setup is missing'), findsOneWidget);
  });

  testWidgets('not during a call', (tester) async {
    client.release = release;
    state = fixture()['state'] as Map<String, dynamic>; // a call up and one ringing
    await open(tester);
    await controller.checkForUpdate();
    await tester.pumpAndSettle();
    expect(find.text('DSIP 0.2.0 is out: update once your call is over.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Update and restart'));
    expect(button.onPressed, isNull);
    await controller.installUpdate();
    expect(client.updating, isEmpty);
  });

  testWidgets('a copy that cannot update itself is given the file; later puts the banner off', (tester) async {
    client.release = const UpdateInfo(
      version: '0.2.0',
      notes: 'https://github.com/thevoiceguy/dsip-app/releases/tag/v0.2.0',
      canInstall: false,
      reason: 'installed from the .deb: install the new one with apt',
      download: 'https://github.com/thevoiceguy/dsip-app/releases/download/v0.2.0/dsip_v0.2.0_amd64.deb',
    );
    await open(tester);
    await controller.checkForUpdate();
    await tester.pumpAndSettle();
    expect(find.textContaining('This copy does not update itself (installed from the .deb'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Update and restart'), findsNothing);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-banner')), findsNothing);
  });

  testWidgets('a check that fails says why', (tester) async {
    client.checkFails = Exception('no network');
    await open(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('check-updates')), 300, scrollable: settingsList());
    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not update: Exception: no network'), findsOneWidget);
  });
}
