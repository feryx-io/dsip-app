// Attachments (found on real devices: no way to send a file): a file picked and sent, one received shown as a card to
// open or save once it is here, and the card filled in when its file arrives.

import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/screens/attachments.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client.dart';

const group = 'MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk';
const fileId = '01M6EKRTVG3C55DFMQ401G3MC4';

void main() {
  late Directory dir;
  late FakeClient client;
  late Controller controller;
  late Map<String, dynamic> thread;
  final m = messagesFixture();
  final opened = <String>[];
  final saved = <(String, String)>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsip-app-test');
    thread = Map<String, dynamic>.from(m['thread'] as Map<String, dynamic>);
    client = FakeClient();
    client.answer = (cmd) => switch (cmd['command']) {
      'thread' => thread,
      'send_file' => m['conversation'] as Map<String, dynamic>,
      _ => {'response': 'ok'},
    };
    controller = Controller(client, SettingsStore(dir));
    opened.clear();
    saved.clear();
    openAttachment = (path, type) async {
      opened.add(path);
      return true;
    };
    saveAttachment = (name, path) async {
      saved.add((name, path));
      return true;
    };
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.runAsync(() => SettingsStore(dir).save({'identity': '/x', 'relay': 'wss://r/dsip'}));
    await tester.pumpWidget(DsipApp(controller: controller));
    await tester.runAsync(controller.load);
    client.push(fixture()['state'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-$group')));
    await tester.pumpAndSettle();
  }

  test('sizes for people', () {
    expect([sizeText(512), sizeText(48213), sizeText(3 * 1024 * 1024 + 200000)], ['512 B', '47 KB', '3.2 MB']);
  });

  testWidgets('a file received is a card with its name and size, opened or saved', (tester) async {
    await open(tester);
    final card = find.byKey(const Key('message-$fileId'));
    expect(find.descendant(of: card, matching: find.text('plan.pdf')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('47 KB')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-$fileId')));
    await tester.tap(find.byKey(const Key('save-$fileId')));
    await tester.pumpAndSettle();
    const path = '/home/alice/.local/share/dsip/media/$fileId-plan.pdf';
    expect(opened, [path]);
    expect(saved, [('plan.pdf', path)]);
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('a file not here yet says so, and is filled in when it arrives', (tester) async {
    final messages = [for (final x in thread['messages'] as List) Map<String, dynamic>.from(x as Map)];
    messages.last.remove('path');
    thread = {...thread, 'messages': messages};
    await open(tester);
    expect(find.text('Downloading…'), findsOneWidget);
    expect(find.byKey(const Key('open-$fileId')), findsNothing);
    client.push(fixture()['state'] as Map<String, dynamic>, m['message_file'] as Map<String, dynamic>);
    await tester.pumpAndSettle();
    expect(find.text('Downloading…'), findsNothing);
    expect(find.byKey(const Key('open-$fileId')), findsOneWidget);
  });

  testWidgets('a file picked is sent to the conversation open', (tester) async {
    pickToSend = () async => ('/tmp/photo.jpg', 'photo.jpg');
    await open(tester);
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'send_file', 'to': group, 'path': '/tmp/photo.jpg', 'name': 'photo.jpg'});

    pickToSend = () async => null;
    final before = client.commands.length;
    await tester.tap(find.byKey(const Key('attach')));
    await tester.pumpAndSettle();
    expect(client.commands.length, before, reason: 'nothing picked, nothing sent');
  });
}
