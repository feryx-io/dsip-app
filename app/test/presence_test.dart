import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

/// The presence fixture, from `dsip-app`'s `wire_fixture` test: followed identities of every kind, a `revoked`
/// response.
Map<String, dynamic> presenceFixture() =>
    jsonDecode(File('test/fixtures/presence.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;
  late Map<String, dynamic> state;
  final p = presenceFixture();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    client.answer = (cmd) => switch (cmd['command']) {
      'revoke_grants' => p['revoked'] as Map<String, dynamic>,
      _ => {'response': 'ok'},
    };
    controller = Controller(client, SettingsStore(dir));
    state = fixture()['state'] as Map<String, dynamic>;
    (state['presence'] as Map<String, dynamic>)['following'] = p['following'];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The app started, its state the fixture's with every kind of followed identity, on the Presence screen.
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(state);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Presence'));
    await tester.pumpAndSettle();
  }

  String subtitle(WidgetTester tester, String identity) {
    final tile = tester.widget<ListTile>(find.byKey(Key('following-$identity')));
    return (tile.subtitle! as Text).data!;
  }

  testWidgets('each followed identity says what is known of it', (tester) async {
    await open(tester);
    expect(subtitle(tester, 'did:key:z6MkBob'), 'Away · 1 device sealed to others');
    // named by the user (the fixture's names): the identity said beside it
    expect(subtitle(tester, 'did:key:z6MkCarol'), 'did:key:z6MkCarol · Available · their relay says they are connected');
    expect(subtitle(tester, 'did:key:z6MkDave'), 'Busy (in-a-meeting)');
    expect(subtitle(tester, 'did:key:z6MkErin'), startsWith('Not shown'));
  });

  testWidgets('my presence is set from the menu, automatic without a state', (tester) async {
    await open(tester);
    expect(find.textContaining('sealed so that only they can read it'), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-presence')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Do not disturb').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-presence')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic').last);
    await tester.pumpAndSettle();
    expect(client.commands, [
      {'command': 'set_presence', 'state': 'dnd'},
      {'command': 'set_presence'},
    ]);
  });

  testWidgets('someone is followed, unfollowed, and no longer shared with', (tester) async {
    await open(tester);
    await tester.tap(find.text('Follow someone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-0')), ' did:key:z6MkFrank ');
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();

    final more = find.descendant(of: find.byKey(const Key('following-did:key:z6MkBob')), matching: find.byTooltip('More'));
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop following'));
    await tester.pumpAndSettle();

    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop sharing with them'));
    await tester.pumpAndSettle();
    expect(find.textContaining('your presence keys change'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(find.text('Withdrew 2 grants from did:key:z6MkBob.'), findsOneWidget);

    expect(client.commands, [
      {'command': 'watch_presence', 'identity': 'did:key:z6MkFrank'},
      {'command': 'unwatch_presence', 'identity': 'did:key:z6MkBob'},
      {'command': 'revoke_grants', 'identity': 'did:key:z6MkBob'},
    ]);
  });

  testWidgets('no one followed', (tester) async {
    (state['presence'] as Map<String, dynamic>)['following'] = <dynamic>[];
    await open(tester);
    expect(find.textContaining('You follow no one'), findsOneWidget);
  });
}
