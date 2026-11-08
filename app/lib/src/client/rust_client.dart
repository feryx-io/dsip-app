import 'dart:convert';

import '../rust/api/app.dart' as bridge;
import '../rust/api/update.dart' as update;
import 'client.dart';
import 'models.dart';

/// The app itself: `dsip-app` in this process, through the bridge (`rust/src/api/app.rs`).
class RustClient implements Client {
  @override
  Future<String> initIdentity(String dir, String displayName) =>
      bridge.initIdentity(dir: dir, displayName: displayName);

  @override
  Future<IdentityBackup> exportIdentity(String dir, String passphrase) async => IdentityBackup.fromJson(
    jsonDecode(await bridge.exportIdentity(dir: dir, passphrase: passphrase)) as Map<String, dynamic>,
  );

  @override
  Future<String> restoreIdentity(String dir, String code, String passphrase, String displayName) =>
      bridge.restoreIdentity(dir: dir, code: code, passphrase: passphrase, displayName: displayName);

  (String, String) _codes(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return (j['code'] as String, j['check'] as String);
  }

  @override
  Future<(String, String)> pairingStart(String dir) async => _codes(await bridge.pairingStart(dir: dir));

  @override
  Future<(String, String)> pairingWelcome(String dir, String join) async =>
      _codes(await bridge.pairingWelcome(dir: dir, join: join));

  @override
  Future<String> pairingFinish(String dir, String welcome) => bridge.pairingFinish(dir: dir, welcome: welcome);

  @override
  Future<String?> pairingListen(String dir, String code) => bridge.pairingListen(dir: dir, code: code);

  @override
  Future<WelcomeReceived?> pairingReceive(Duration wait) async {
    final j = await bridge.pairingReceive(waitMs: wait.inMilliseconds);
    return j == null ? null : WelcomeReceived.fromJson(jsonDecode(j) as Map<String, dynamic>);
  }

  @override
  Future<void> pairingStop() => bridge.pairingStop();

  @override
  Future<String?> pairingSend(String join, String welcome) => bridge.pairingSend(join: join, welcome: welcome);

  @override
  Future<Map<String, dynamic>> webPrepare(String dir, String did, String relay, {String? mailboxDid, String? mailboxUri}) async =>
      jsonDecode(await bridge.webPrepare(dir: dir, did: did, relay: relay, mailboxDid: mailboxDid, mailboxUri: mailboxUri))
          as Map<String, dynamic>;

  @override
  Future<List<String>> webCheck(Map<String, dynamic> plan) async =>
      (jsonDecode(await bridge.webCheck(plan: jsonEncode(plan))) as List).cast<String>();

  @override
  Future<String> webMove(String dir, Map<String, dynamic> plan) => bridge.webMove(dir: dir, plan: jsonEncode(plan));

  @override
  Future<void> start(Map<String, dynamic> settings) => bridge.start(settings: jsonEncode(settings));

  @override
  Future<Map<String, dynamic>> command(Map<String, dynamic> command) async =>
      decode(await bridge.command(command: jsonEncode(command)));

  @override
  Stream<Update> updates() => bridge.updates().map((line) => Update.fromJson(decode(line)));

  @override
  Future<void> stop() => bridge.stop();

  @override
  String appVersion() => update.appVersion();

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final j = jsonDecode(await update.checkForUpdate());
    return j == null ? null : UpdateInfo.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<void> downloadUpdate() => update.downloadUpdate();

  @override
  Future<void> installUpdate() => update.installUpdate();
}
