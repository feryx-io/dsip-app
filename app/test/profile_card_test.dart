// Profile cards (core §19.4): the user's own, under Me, sent only by their choice; and those others sent, shown as
// what they are, claims nobody checked.

import 'dart:io';
import 'dart:typed_data';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/card_picture.dart';
import 'package:dsip_app/src/client/models.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/screens/address.dart';
import 'package:dsip_app/src/screens/me.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'fake_client.dart';

const carol = 'did:key:z6MkCarol';
const request = '01M6EKRTVG3C55DFMQ401G3MB0';

/// A photograph's worth of detail: [side] pixels square, no two neighbours alike, as a PNG.
Uint8List noisyPng(int side) {
  final image = img.Image(width: side, height: side);
  for (final p in image) {
    p
      ..r = (p.x * 37 + p.y * 91) % 256
      ..g = (p.x * 113 + p.y * 17) % 256
      ..b = (p.x * 7 + p.y * 201) % 256;
  }
  return img.encodePng(image);
}

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
    shrinkPicture = (bytes) async => shrinkCardPicture(bytes);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, String tab) async {
    tester.view.physicalSize = const Size(1200, 1400);
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

  Future<void> settleFiles(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    }
    await tester.pumpAndSettle();
  }

  test('the state says what the card is, whether it is sent, and whose cards are held', () {
    final s = Update.fromJson(fixture()).state;
    expect((s.profile.withIntroductions, s.profile.withGrants), (true, false));
    expect(s.profile.picture, endsWith('.jpg'));
    expect(s.messaging.requests.single.card?.name, 'Carol N.');
    expect(s.cards['did:key:z6MkBob']?.name, 'Bob Marsh');
    // a state from before cards: nothing shared, nothing held
    final old = Map<String, dynamic>.of(fixture()['state'] as Map<String, dynamic>)
      ..remove('profile')
      ..remove('cards');
    final before = AppState.fromJson(old);
    expect((before.profile.withIntroductions, before.profile.withGrants), (false, false));
    expect(before.cards, isEmpty);
  });

  test('a picture is shrunk to what a card carries: a small JPEG of at most 4,096 bytes', () {
    final small = shrinkCardPicture(noisyPng(600))!;
    expect(small.length, lessThanOrEqualTo(cardPictureMaxBytes));
    expect(small.sublist(0, 3), [0xff, 0xd8, 0xff], reason: 'a JPEG');
    final decoded = img.decodeJpg(small)!;
    expect(decoded.width, decoded.height, reason: 'its middle square');
    // a wide one is cut to its middle, not squeezed
    final wide = img.Image(width: 400, height: 100);
    img.fill(wide, color: img.ColorRgb8(200, 30, 30));
    final cut = img.decodeJpg(shrinkCardPicture(img.encodePng(wide))!)!;
    expect((cut.width, cut.height), (100, 100));
    expect(shrinkCardPicture(Uint8List.fromList('not an image'.codeUnits)), isNull);
  });

  testWidgets('Me: the card is sent only once switched on, each way its own switch', (tester) async {
    state['profile'] = {'with_introductions': false, 'with_grants': false};
    await open(tester, 'Me');
    expect(find.text('Your card'), findsOneWidget);
    SwitchListTile toggle(String key) => tester.widget<SwitchListTile>(find.byKey(Key(key)));
    expect((toggle('card-with-introductions').value, toggle('card-with-grants').value), (false, false));
    expect(find.byKey(const Key('card-picture-remove')), findsNothing, reason: 'no picture to remove');

    await tester.tap(find.byKey(const Key('card-with-introductions')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'share_profile', 'introductions': true});
    await tester.tap(find.byKey(const Key('card-with-grants')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'share_profile', 'grants': true});

    // the app says they are on: the switches follow it
    state['profile'] = {'with_introductions': true, 'with_grants': true};
    client.push(state);
    await tester.pumpAndSettle();
    expect((toggle('card-with-introductions').value, toggle('card-with-grants').value), (true, true));
    await tester.tap(find.byKey(const Key('card-with-grants')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'share_profile', 'grants': false});
  });

  testWidgets('Me: a picture chosen is shrunk before the app is given it, and can be removed', (tester) async {
    state['profile'] = {'with_introductions': false, 'with_grants': false};
    await open(tester, 'Me');
    final photo = noisyPng(600);
    pickPicture = () async => photo;
    Uint8List? given;
    client.answer = (cmd) {
      if (cmd['command'] == 'set_picture' && cmd['path'] != null) given = File(cmd['path'] as String).readAsBytesSync();
      return {'response': 'ok'};
    };
    await tester.tap(find.byKey(const Key('card-picture-choose')));
    await settleFiles(tester);
    expect(given, isNotNull, reason: 'the app was given a file');
    expect(given!.length, lessThanOrEqualTo(cardPictureMaxBytes));
    expect(given!.sublist(0, 3), [0xff, 0xd8, 0xff]);

    // a file that is no picture: said, and the app is not asked
    final asked = client.commands.length;
    pickPicture = () async => Uint8List.fromList('not an image'.codeUnits);
    await tester.tap(find.byKey(const Key('card-picture-choose')));
    await settleFiles(tester);
    expect(find.text('That file is not a picture this app can read.'), findsOneWidget);
    expect(client.commands.length, asked);

    // with a picture, it can be taken away
    state['profile'] = {'picture': '${dir.path}/mine.jpg', 'with_introductions': false, 'with_grants': false};
    client.push(state);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-picture-remove')));
    await tester.pumpAndSettle();
    expect(client.commands.last, {'command': 'set_picture'});
  });

  testWidgets('without a mailbox there is nobody to send a card to: Me does not offer one', (tester) async {
    (state['messaging'] as Map<String, dynamic>).remove('mailbox');
    await open(tester, 'Me');
    expect(find.text('Your card'), findsNothing);
  });

  testWidgets('a request shows the card it came with as a claim, not verified', (tester) async {
    await open(tester, 'Messages');
    final row = find.byKey(const Key('request-$request'));
    expect(
      find.descendant(of: row, matching: find.text('Their card says “Carol N.”, with this picture · not verified')),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: find.text(carol)), findsOneWidget, reason: 'beside the identity itself');

    // a request without a card says nothing of one
    ((state['messaging'] as Map<String, dynamic>)['requests'] as List).single.remove('card');
    client.push(state);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-card-$request')), findsNothing);
  });

  testWidgets('a contact shows the card they sent as a claim; the picture the user chose comes first', (tester) async {
    final png = noisyPng(8);
    final theirs = File('${dir.path}/theirs.png')..writeAsBytesSync(png);
    state['cards'] = {
      carol: {'name': 'Carol N.', 'picture': theirs.path},
    };
    await open(tester, 'Contacts');
    final row = find.byKey(const Key('contact-$carol'));
    expect(find.descendant(of: row, matching: find.text('Carol Jones')), findsOneWidget, reason: 'the name the user gave');
    expect(find.byKey(const Key('contact-card-$carol')), findsOneWidget);
    expect(find.text('Their card says “Carol N.”, with this picture · not verified'), findsOneWidget);
    expect(find.byKey(const Key('avatar-picture-$carol')), findsOneWidget, reason: "the card's picture");
    Image shown() => tester.widget<Image>(find.byKey(const Key('avatar-picture-$carol')));
    expect(((shown().image as ResizeImage).imageProvider as FileImage).file.path, theirs.path);

    // the user's own choice for her is shown instead
    await tester.runAsync(() => controller.setPicture(carol, png));
    await tester.pumpAndSettle();
    expect(((shown().image as ResizeImage).imageProvider as FileImage).file.path, isNot(theirs.path));

    // a card with a name only says only that
    state['cards'] = {
      carol: {'name': 'Carol N.'},
    };
    client.push(state);
    await tester.pumpAndSettle();
    expect(find.text('Their card says “Carol N.” · not verified'), findsOneWidget);
  });

  testWidgets('their card\'s picture is shown wherever they are, marked as not verified where no words say so', (tester) async {
    const bob = 'did:key:z6MkBob';
    final theirs = File('${dir.path}/bob.png')..writeAsBytesSync(noisyPng(8));
    state['cards'] = {
      bob: {'name': 'Bob Marsh', 'picture': theirs.path},
    };
    String shown(Finder within) {
      final image = tester.widget<Image>(find.descendant(of: within, matching: find.byKey(const Key('avatar-picture-$bob'))));
      return ((image.image as ResizeImage).imageProvider as FileImage).file.path;
    }

    Finder mark(Finder within) => find.descendant(of: within, matching: find.byKey(const Key('avatar-claim-$bob')));

    // the conversation with him
    await open(tester, 'Messages');
    final conversation = find.byWidgetPredicate((w) => w.key.toString().contains('conversation-') && w is ListTile);
    expect(shown(conversation), theirs.path);
    expect(tester.widget<Tooltip>(mark(conversation)).message, 'Picture from their card · not verified');

    // his calls: the ones going on, and the ones before
    await tester.tap(find.text('Calls').last);
    await tester.pumpAndSettle();
    for (final row in [find.byKey(const Key('call-2')), find.byKey(const Key('call-3'))]) {
      expect(shown(row), theirs.path);
      expect(mark(row), findsOneWidget);
    }
    final before = find.byWidgetPredicate((w) => w.key.toString().contains('history-') && w is ListTile);
    expect(shown(before), theirs.path);
    expect(mark(before), findsOneWidget);

    // the picture the user chose for him is theirs to vouch for: no mark
    await tester.runAsync(() => controller.setPicture(bob, noisyPng(8)));
    await tester.pumpAndSettle();
    expect(shown(before), isNot(theirs.path));
    expect(find.byKey(const Key('avatar-claim-$bob')), findsNothing);
  });

  testWidgets('where the screen says in words that a card is not verified, its picture carries no mark', (tester) async {
    final theirs = File('${dir.path}/theirs.png')..writeAsBytesSync(noisyPng(8));
    state['cards'] = {
      carol: {'name': 'Carol N.', 'picture': theirs.path},
    };
    await open(tester, 'Contacts');
    expect(find.byKey(const Key('avatar-picture-$carol')), findsOneWidget);
    expect(find.byKey(const Key('contact-card-$carol')), findsOneWidget);
    expect(find.byKey(const Key('avatar-claim-$carol')), findsNothing);
  });
}
