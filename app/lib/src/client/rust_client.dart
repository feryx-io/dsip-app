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
