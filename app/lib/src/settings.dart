import 'dart:convert';
import 'dart:io';

/// Where the app keeps `settings.json` (`dsip-app`'s `Settings`, as `dsip-app run`'s flags say them) and, unless the
/// user picked another, its identity folder.
class SettingsStore {
  SettingsStore(this.dir);

  /// The app's own folder (the platform's application support directory).
  final Directory dir;

  File get _file => File('${dir.path}${Platform.pathSeparator}settings.json');

  /// Where a new identity goes.
  String get defaultIdentity => '${dir.path}${Platform.pathSeparator}identity';

  /// The settings saved, or null on first run.
  Future<Map<String, dynamic>?> load() async {
    if (!await _file.exists()) return null;
    return jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> save(Map<String, dynamic> settings) async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(settings));
    await tmp.rename(_file.path);
  }
}

/// The app's id before it was `com.feryx.dsip` (2026-11-10), which named its folder on a desktop.
const oldAppId = 'com.thevoiceguy.dsip';
const appId = 'com.feryx.dsip';

/// Move the app's folder from where the old id put it to [dir], once: when [dir] holds no settings and the old folder
/// does. The paths saved in the settings that were inside the old folder (the identity folder, its messaging state)
/// follow. Whether it moved. Where the old folder cannot be seen (macOS keeps each id's apart), nothing moves.
Future<bool> moveOldFolder(Directory dir) async {
  if (!dir.path.contains(appId)) return false;
  final old = Directory(dir.path.replaceAll(appId, oldAppId));
  final sep = Platform.pathSeparator;
  if (await File('${dir.path}${sep}settings.json').exists()) return false;
  if (!await File('${old.path}${sep}settings.json').exists()) return false;
  if (await dir.exists()) {
    // an identity made here already is not overwritten; anything else is what the new id's first start left
    if (await Directory('${dir.path}${sep}identity').exists()) return false;
    await dir.delete(recursive: true);
  }
  await dir.parent.create(recursive: true);
  await old.rename(dir.path);
  final store = SettingsStore(dir);
  final settings = await store.load();
  if (settings != null) {
    String? moved(Object? p) => p is String && p.startsWith(old.path) ? dir.path + p.substring(old.path.length) : null;
    final edited = {
      ...settings,
      for (final k in const ['identity', 'messaging_state', 'ca'])
        if (moved(settings[k]) != null) k: moved(settings[k]),
    };
    await store.save(edited);
  }
  // the old id's empty parent (Windows: %APPDATA%\com.thevoiceguy.dsip)
  try {
    if (old.parent.path.endsWith(oldAppId) && await old.parent.list().isEmpty) await old.parent.delete();
  } on FileSystemException {
    // kept: not empty, or not ours to remove
  }
  return true;
}

/// `dsip-app`'s `Settings` from what the first run asks.
Map<String, dynamic> settingsFor({
  required String identity,
  required String relay,
  String? mailboxUri,
  String? mailboxDid,
  String? hintsNode,
}) => {
  'identity': identity,
  'relay': relay,
  if (mailboxUri != null && mailboxDid != null) 'mailbox': {'uri': mailboxUri, 'did': mailboxDid},
  if (hintsNode != null) 'hints_nodes': [hintsNode],
};
