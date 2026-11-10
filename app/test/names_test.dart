// The names the user gives identities (the state's `names`, `set_name`): shown in place of the identity everywhere, and
// before a caller's own name; given and taken away from the calls, presence and a conversation.

import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/models.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';
import 'presence_test.dart' show presenceFixture;

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;
  late Map<String, dynamic> state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    controller = Controller(client, SettingsStore(dir));
    state = fixture()['state'] as Map<String, dynamic>;
    (state['presence'] as Map<String, dynamic>)['following'] = presenceFixture()['following'];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, String tab) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(state);
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab).last);
    await tester.pumpAndSettle();
  }

  /// Name [did] [name] (or, empty, take its name away) in the dialog open now, and answer as the app does.
  Future<void> name(WidgetTester tester, String did, String name) async {
    await tester.enterText(find.byKey(const Key('field-0')), name);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final names = Map<String, dynamic>.from(state['names'] as Map? ?? {});
    name.trim().isEmpty ? names.remove(did) : names[did] = name.trim();
    state['names'] = names;
    client.push(state, {'change': 'names', 'names': names});
    await tester.pumpAndSettle();
  }

  test('a name of the user\'s first, then the one offered, then the identity', () {
    final s = AppState.fromJson({...state, 'names': {'did:key:z6MkBob': 'Robert'}});
    expect(s.nameOf('did:key:z6MkBob', offered: 'Bob'), 'Robert');
    expect(s.nameOf('did:key:z6MkCarol', offered: 'Carol'), 'Carol');
    expect(s.nameOf('did:key:z6MkCarol'), 'did:key:z6MkCarol');
    expect(s.named('did:key:z6MkBob'), isTrue);
    expect(s.named('did:key:z6MkCarol'), isFalse);
  });

  testWidgets('a call ended is named from the calls, and every call to that identity shows it', (tester) async {
    await open(tester, 'Calls');
    await tester.tap(find.byKey(const Key('history-menu-01M6BTTMQ9QMKY9SYTY8415VZ0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('name-call-01M6BTTMQ9QMKY9SYTY8415VZ0')));
    await tester.pumpAndSettle();
    expect(find.text('Name did:key:z6MkBob'), findsOneWidget);
    await name(tester, 'did:key:z6MkBob', '  Robert ');
    expect(client.commands.last, {'command': 'set_name', 'identity': 'did:key:z6MkBob', 'name': 'Robert'});
    // the user's name before the one the caller offered ("Bob"), and the identity beside it
    expect(find.text('Robert'), findsNWidgets(3));
    expect(find.text('Bob'), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('call-2')), matching: find.text('did:key:z6MkBob')), findsOneWidget);
  });

  testWidgets('a followed identity is named, and its name taken away, from its menu', (tester) async {
    await open(tester, 'Presence');
    Future<void> menu() async {
      await tester.tap(find.descendant(of: find.byKey(const Key('following-did:key:z6MkDave')), matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();
    }

    await menu();
    await name(tester, 'did:key:z6MkDave', 'Dave');
    expect(find.descendant(of: find.byKey(const Key('following-did:key:z6MkDave')), matching: find.text('Dave')), findsOneWidget);

    await menu();
    expect(tester.widget<TextField>(find.byKey(const Key('field-0'))).controller!.text, 'Dave', reason: 'starts from its name');
    await name(tester, 'did:key:z6MkDave', '');
    expect(client.commands.last, {'command': 'set_name', 'identity': 'did:key:z6MkDave'});
    expect(find.text('Dave'), findsNothing);
  });

  testWidgets('a conversation is named from its header, and a request shows the user\'s name', (tester) async {
    state['names'] = {'did:key:z6MkCarol': 'Carol Jones'};
    await open(tester, 'Messages');
    expect(find.text('Carol Jones'), findsOneWidget, reason: 'the request, by the name the user gave, not "Carol" asking');
    await tester.tap(find.byKey(const Key('conversation-MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('name-thread')));
    await tester.pumpAndSettle();
    await name(tester, 'did:key:z6MkBob', 'Robert');
    expect(find.text('Robert'), findsWidgets);
  });
}
