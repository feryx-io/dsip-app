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

  /// The new device's first step in joining an identity: the join code, and the check code both devices show (A6).
  Future<(String, String)> pairingStart(String dir);

  /// On a device holding the identity in [dir]: the welcome code for the device whose join code is [join], and the
  /// check code.
  Future<(String, String)> pairingWelcome(String dir, String join);

  /// The new device's last step: joined with the [welcome] code, in [dir]; the identity's DID.
  Future<String> pairingFinish(String dir, String welcome);

  /// The new device in [dir] listens on the local network for its welcome code (the handoff): the join code [code] in
  /// its QR form, with where it listens; null when it cannot (the QR is then the code alone).
  Future<String?> pairingListen(String dir, String code);

  /// A welcome code the handoff received within [wait], checked for this device and not joined yet; null when none
  /// came.
  Future<WelcomeReceived?> pairingReceive(Duration wait);

  /// Stop the handoff.
  Future<void> pairingStop();

  /// Send [welcome] to the new device at the addresses its join code's QR form ([join]) carries: the address that took
  /// it, or null when [join] carries none (it was typed). Throws when none took it.
  Future<String?> pairingSend(String join, String welcome);

  /// The document the identity in [dir] would serve as [did] (a `did:web`), naming [relay] and the mailbox: `{did, url,
  /// document}` (A6d). Nothing changes yet.
  Future<Map<String, dynamic>> webPrepare(String dir, String did, String relay, {String? mailboxDid, String? mailboxUri});

  /// How what the domain of [plan] serves differs from what it must, each in a sentence; empty when it serves it.
  Future<List<String>> webCheck(Map<String, dynamic> plan);

  /// Make the identity in [dir] the `did:web` of [plan]; its new DID. Only while the app is stopped.
  Future<String> webMove(String dir, Map<String, dynamic> plan);

  /// The settings for a new device from the servers [domain] lists at its `/.well-known/dsip`: one relay and one
  /// mailbox from its pools, its hints nodes and STUN servers, and `server`; `identity` empty, for the caller to fill.
  /// Throws, saying why, when the domain lists none or a list this app cannot use.
  Future<Map<String, dynamic>> discoverServers(String domain);

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

/// A welcome code the new device received over the local network: the code, and the identity it is from.
class WelcomeReceived {
  const WelcomeReceived({required this.welcome, required this.identity, required this.name});
  factory WelcomeReceived.fromJson(Map<String, dynamic> j) =>
      WelcomeReceived(welcome: j['welcome'] as String, identity: j['identity'] as String, name: j['name'] as String);
  final String welcome;
  final String identity;
  final String name;
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
