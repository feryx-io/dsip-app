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
