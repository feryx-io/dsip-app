import 'dart:io';

import 'package:dsip_app/src/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// A desktop installed under the app's old id (com.thevoiceguy.dsip): its folder, with the identity and the settings
/// naming it, moves to the new id's once, and nothing made under the new id is overwritten.
void main() {
  late Directory root;
  final sep = Platform.pathSeparator;
  setUp(() async => root = await Directory.systemTemp.createTemp('dsip-move-'));
  tearDown(() => root.delete(recursive: true));

  Directory under(String id, [String at = '']) => Directory('${root.path}$at$sep$id${sep}DSIP');

  Future<void> oldInstall([String at = '']) async {
    final old = under(oldAppId, at);
    await Directory('${old.path}${sep}identity').create(recursive: true);
    await File('${old.path}${sep}identity${sep}identity.json').writeAsString('{"identity": "did:key:z6MkAnn"}');
    await SettingsStore(old).save({
      'identity': '${old.path}${sep}identity',
      'relay': 'wss://relay.example.com:8443/dsip',
      'ca': '/etc/dsip/ca.pem',
    });
  }

  test('the old folder moves, and the identity folder saved in its settings follows', () async {
    await oldInstall();
    final dir = under(appId);
    expect(await moveOldFolder(dir), isTrue);
    final settings = await SettingsStore(dir).load();
    expect(settings?['identity'], '${dir.path}${sep}identity');
    expect(settings?['ca'], '/etc/dsip/ca.pem', reason: 'outside the folder: kept');
    expect(await File('${dir.path}${sep}identity${sep}identity.json').exists(), isTrue);
    expect(await Directory('${root.path}$sep$oldAppId').exists(), isFalse, reason: 'the empty parent goes');
    expect(await moveOldFolder(dir), isFalse, reason: 'once');
  });

  test('a new folder left by a first start is replaced; one with an identity is not', () async {
    await oldInstall();
    final dir = under(appId);
    await dir.create(recursive: true);
    expect(await moveOldFolder(dir), isTrue);

    await oldInstall('${sep}b');
    final made = under(appId, '${sep}b');
    await Directory('${made.path}${sep}identity').create(recursive: true);
    expect(await moveOldFolder(made), isFalse);
    expect(await under(oldAppId, '${sep}b').exists(), isTrue);
  });

  test('no old folder, or a folder not named for the app: nothing moves', () async {
    expect(await moveOldFolder(under(appId)), isFalse);
    expect(await moveOldFolder(Directory('${root.path}${sep}elsewhere')), isFalse);
  });
}
