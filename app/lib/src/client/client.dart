import 'dart:async';
import 'dart:convert';

import 'models.dart';

/// What the screens drive: the running app, through `dsip-app`'s commands (as the CLI sends them) and its updates.
/// The real one is [RustClient]; tests use a fake.
abstract class Client {
  /// Make an identity in [dir]; its DID.
  Future<String> initIdentity(String dir, String displayName);

  /// Back up the identity in [dir]: its key sealed under [passphrase], as a recovery code (A6b).
  Future<IdentityBackup> exportIdentity(String dir, String passphrase);

  /// Make the identity in [code] (a recovery code, or a backup file's text) this install's, in [dir]; its DID.
  Future<String> restoreIdentity(String dir, String code, String passphrase, String displayName);

  /// Start the app from [settings] (`dsip-app`'s `Settings` as JSON).
  Future<void> start(Map<String, dynamic> settings);

  /// Do [command] (`{"command": "call", "to": …}`); the response (`{"response": "ok"}`, `{"response": "error",
  /// "message": …}`, …).
  Future<Map<String, dynamic>> command(Map<String, dynamic> command);

  /// The state now, then after every change, until the app stops.
  Stream<Update> updates();

  Future<void> stop();

  /// This copy's version.
  String appVersion();

  /// The latest release when it is newer than this copy; null when this is the latest.
  Future<UpdateInfo?> checkForUpdate();

  /// Fetch the release [checkForUpdate] found, checked against its signed manifest.
  Future<void> downloadUpdate();

  /// Install the release fetched once this process has gone, and start the app again: the caller quits right after.
  Future<void> installUpdate();
}

/// A backup of an identity: its DID, the recovery code, and the text of a file holding it.
class IdentityBackup {
  const IdentityBackup({required this.identity, required this.code, required this.file});
  factory IdentityBackup.fromJson(Map<String, dynamic> j) =>
      IdentityBackup(identity: j['identity'] as String, code: j['code'] as String, file: j['file'] as String);
  final String identity;
  final String code;
  final String file;
}

/// A response that is an error: its message; null otherwise.
String? errorOf(Map<String, dynamic> response) =>
    response['response'] == 'error' ? response['message'] as String? ?? 'error' : null;

Map<String, dynamic> decode(String json) => jsonDecode(json) as Map<String, dynamic>;
