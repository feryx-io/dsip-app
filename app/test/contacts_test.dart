// Contacts, the call history and deleting (found testing on real devices): the contacts tab (the state's `names`) to
// call, message, rename and delete from; the history kept across restarts, to call back from and delete; a request's
// purpose and whole identity; the introductions sent; a message and a conversation deleted on this device.

import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/models.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/pictures.dart';
import 'package:dsip_app/src/screens/address.dart';
import 'package:dsip_app/src/screens/avatar.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

const group = 'MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk';
const carol = 'did:key:z6MkCarol';

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;
  late Map<String, dynamic> state;
  final m = messagesFixture();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    client = FakeClient();
    client.answer = (cmd) => switch (cmd['command']) {
      'thread' => m['thread'] as Map<String, dynamic>,
      'message' => m['conversation'] as Map<String, dynamic>,
      'call' => {'response': 'call', 'call': 9},
      _ => {'response': 'ok'},
    };
    controller = Controller(client, SettingsStore(dir));
    state = fixture()['state'] as Map<String, dynamic>;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, String tab, {Size size = const Size(1200, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(state);
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab).last);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();
  }

  test('the history and the introductions sent are read whole', () {
    final s = AppState.fromJson(state);
    expect(s.history.map((c) => (c.peer, c.direction, c.answered, c.missed)), [
      ('did:key:z6MkBob', Direction.outgoing, true, false),
      (carol, Direction.incoming, false, true),
    ]);
    final i = s.messaging.introduced.single;
    expect((i.to, i.name, i.purpose, i.accepted), ('did:key:z6MkDave', 'Dave', 'Lunch on Friday?', false));
    expect(s.messaging.requests.single.purpose, 'We met at the conference');
  });

  testWidgets('a contact is called, messaged, renamed and deleted from the contacts', (tester) async {
    await open(tester, 'Contacts');
    final tile = find.byKey(const Key('contact-$carol'));
    expect(find.descendant(of: tile, matching: find.text('Carol Jones')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text(carol)), findsOneWidget, reason: 'the whole identity');

    await tester.tap(find.byKey(const Key('contact-call-$carol')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'call', 'to': carol});
    expect(controller.tab, Tabs.calls, reason: 'the call is shown');

    await tester.tap(find.text('Contacts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-message-$carol')));
    await tester.pumpAndSettle();
    expect(find.text('Message Carol Jones'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-0')), 'hello');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(client.commands.reversed.skip(1).first, {'command': 'message', 'to': carol, 'text': 'hello'});
    expect(client.commands.last, {'command': 'thread', 'conversation': group}, reason: 'the conversation is opened');
    expect(controller.tab, Tabs.messages);

    await tester.tap(find.text('Contacts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-menu-$carol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete Carol Jones from your contacts?'), findsOneWidget);
    await confirm(tester);
    expect(client.commands.last, {'command': 'set_name', 'identity': carol}, reason: 'no name: no longer a contact');
  });

  testWidgets('a contact and a recent call are called with video, and their address copied', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    const bobs = '01M6BTTMQ9QMKY9SYTY8415VZ0';
    (state['history'] as List).first['video'] = true;

    // with room, a video button beside the call button (tall enough for the history under the fixture's video call)
    await open(tester, 'Contacts', size: const Size(1200, 1400));
    await tester.tap(find.byKey(const Key('contact-video-$carol')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'call', 'to': carol, 'video': true});
    expect(controller.tab, Tabs.calls);
    await tester.tap(find.text('Contacts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-menu-$carol')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-copy-$carol')));
    await tester.pumpAndSettle();
    expect(copied, carol);
    expect(tester.widget(find.byKey(const Key('contact-address-$carol'))), isA<SelectableText>(), reason: 'selectable, as on Me');

    // the history says which calls were video calls, and calls back either way
    await tester.tap(find.text('Calls').last);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('history-$bobs')), matching: find.textContaining('Video call ·')), findsOneWidget);
    await tester.tap(find.byKey(const Key('call-back-video-$bobs')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'call', 'to': 'did:key:z6MkBob', 'video': true});
    await tester.tap(find.byKey(const Key('history-menu-$bobs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copy-call-$bobs')));
    await tester.pumpAndSettle();
    expect(copied, 'did:key:z6MkBob');
  });

  testWidgets('on a phone\'s width the video call is in the row\'s menu', (tester) async {
    await open(tester, 'Contacts', size: const Size(400, 800));
    expect(find.byKey(const Key('contact-video-$carol')), findsNothing);
    await tester.tap(find.byKey(const Key('contact-menu-$carol')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-video-$carol')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'call', 'to': carol, 'video': true});
  });

  /// Let the app's file work, started by what was tapped, come to its end: each step ends in real time, and the
  /// next starts when the frame is pumped.
  Future<void> settleFiles(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a contact shows its initials, or the picture the user chose for it, in the contacts and the calls', (tester) async {
    expect([initialsOf('Carol Jones'), initialsOf(' bob '), initialsOf('Ana María de la Cruz'), initialsOf(null)], ['CJ', 'B', 'AC', '']);
    await open(tester, 'Contacts', size: const Size(1200, 1400));
    final tile = find.byKey(const Key('contact-$carol'));
    expect(find.descendant(of: tile, matching: find.text('CJ')), findsOneWidget);
    expect(find.byKey(const Key('avatar-picture-$carol')), findsNothing);

    // a 1×1 PNG, picked from the contact's menu
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
    pickPicture = () async => png;
    await tester.tap(find.byKey(const Key('contact-menu-$carol')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact-no-picture-$carol')), findsNothing, reason: 'none to remove yet');
    await tester.tap(find.byKey(const Key('contact-picture-$carol')));
    await settleFiles(tester);
    expect(controller.pictures.has(carol), isTrue);
    expect(dir.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('pictures')).single.readAsBytesSync(), png);
    expect(find.byKey(const Key('avatar-picture-$carol')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('CJ')), findsNothing);

    // the same picture on her calls
    await tester.tap(find.text('Calls').last);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('history-01M6BTTMQ9QMKY9SYTY8415VZ9')), matching: find.byKey(const Key('avatar-picture-$carol'))), findsOneWidget);

    // kept for the next start, until removed
    final again = Pictures(controller.pictures.dir);
    await tester.runAsync(again.load);
    expect(again.has(carol), isTrue);
    await tester.tap(find.text('Contacts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-menu-$carol')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-no-picture-$carol')));
    await settleFiles(tester);
    expect(controller.pictures.has(carol), isFalse);
    expect(find.descendant(of: tile, matching: find.text('CJ')), findsOneWidget);
  });

  testWidgets('a contact is added by identity and name', (tester) async {
    state.remove('names');
    await open(tester, 'Contacts');
    expect(find.textContaining('No contacts yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('contact-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-0')), 'did:key:z6MkErin');
    await tester.enterText(find.byKey(const Key('field-1')), 'Erin');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'set_name', 'identity': 'did:key:z6MkErin', 'name': 'Erin'});
  });

  testWidgets('a call in the history is called back, deleted, and the history cleared', (tester) async {
    // tall enough for the history under the fixture's video call
    await open(tester, 'Calls', size: const Size(1200, 1400));
    const missed = '01M6BTTMQ9QMKY9SYTY8415VZ9';
    final tile = find.byKey(const Key('history-$missed'));
    expect(find.descendant(of: tile, matching: find.textContaining('Missed')), findsOneWidget);

    await tester.tap(find.byKey(const Key('call-back-$missed')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'call', 'to': carol});

    await tester.tap(find.byKey(const Key('history-menu-$missed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from history'));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'forget_call', 'session': missed});

    await tester.tap(find.byKey(const Key('calls-clear')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(client.commands.last, {'command': 'clear_history'});
  });

  testWidgets('a request says what it asks, and who asks, whole, on a phone too', (tester) async {
    await open(tester, 'Messages', size: const Size(390, 844));
    final tile = find.byKey(const Key('request-01M6EKRTVG3C55DFMQ401G3MB0'));
    expect(find.descendant(of: tile, matching: find.text('We met at the conference')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text(carol)), findsOneWidget);
  });

  testWidgets('the introductions sent are listed, and one removed from the list', (tester) async {
    await open(tester, 'Messages');
    final tile = find.byKey(const Key('introduced-did:key:z6MkDave'));
    expect(find.descendant(of: tile, matching: find.text('Dave')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.textContaining('Waiting for them to accept')), findsOneWidget);
    await tester.tap(find.byKey(const Key('introduced-forget-did:key:z6MkDave')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'forget_introduction', 'to': 'did:key:z6MkDave'});
  });

  testWidgets('an introduction names whom it goes to, when the user says', (tester) async {
    await open(tester, 'Messages');
    await tester.tap(find.text('Introduce yourself').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-0')), 'did:key:z6MkFay');
    await tester.enterText(find.byKey(const Key('field-1')), 'hi');
    await tester.enterText(find.byKey(const Key('field-2')), 'Fay');
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'introduce', 'to': 'did:key:z6MkFay', 'purpose': 'hi', 'name': 'Fay'});
  });

  testWidgets('a message is deleted from its long press, and the conversation from its menu', (tester) async {
    await open(tester, 'Messages');
    await tester.tap(find.byKey(const Key('conversation-$group')));
    await tester.pumpAndSettle();
    final id = (((m['thread'] as Map)['messages'] as List).first as Map)['id'] as String;
    await tester.longPress(find.descendant(of: find.byKey(Key('message-$id')), matching: find.byType(Text)).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete this message from this device?'), findsOneWidget);
    await confirm(tester);
    expect(client.commands.last, {'command': 'delete_message', 'conversation': group, 'id': id});
    expect(find.byKey(Key('message-$id')), findsNothing, reason: 'gone from the thread shown');

    await tester.tap(find.byKey(const Key('conversation-menu-$group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete conversation').last);
    await tester.pumpAndSettle();
    expect(find.textContaining("Delete this conversation's messages"), findsOneWidget);
    await confirm(tester);
    expect(client.commands.last, {'command': 'delete_conversation', 'conversation': group});
    expect(controller.threads.containsKey(group), isFalse);
  });
}
