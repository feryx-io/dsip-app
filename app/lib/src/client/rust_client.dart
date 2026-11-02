import 'dart:convert';

import '../rust/api/app.dart' as bridge;
import 'client.dart';
import 'models.dart';

/// The app itself: `dsip-app` in this process, through the bridge (`rust/src/api/app.rs`).
class RustClient implements Client {
  @override
  Future<String> initIdentity(String dir, String displayName) =>
      bridge.initIdentity(dir: dir, displayName: displayName);

  @override
  Future<void> start(Map<String, dynamic> settings) => bridge.start(settings: jsonEncode(settings));

  @override
  Future<Map<String, dynamic>> command(Map<String, dynamic> command) async =>
      decode(await bridge.command(command: jsonEncode(command)));

  @override
  Stream<Update> updates() => bridge.updates().map((line) => Update.fromJson(decode(line)));

  @override
  Future<void> stop() => bridge.stop();
}
