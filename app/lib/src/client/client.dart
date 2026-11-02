import 'dart:async';
import 'dart:convert';

import 'models.dart';

/// What the screens drive: the running app, through `dsip-app`'s commands (as the CLI sends them) and its updates.
/// The real one is [RustClient]; tests use a fake.
abstract class Client {
  /// Make an identity in [dir]; its DID.
  Future<String> initIdentity(String dir, String displayName);

  /// Start the app from [settings] (`dsip-app`'s `Settings` as JSON).
  Future<void> start(Map<String, dynamic> settings);

  /// Do [command] (`{"command": "call", "to": …}`); the response (`{"response": "ok"}`, `{"response": "error",
  /// "message": …}`, …).
  Future<Map<String, dynamic>> command(Map<String, dynamic> command);

  /// The state now, then after every change, until the app stops.
  Stream<Update> updates();

  Future<void> stop();
}

/// A response that is an error: its message; null otherwise.
String? errorOf(Map<String, dynamic> response) =>
    response['response'] == 'error' ? response['message'] as String? ?? 'error' : null;

Map<String, dynamic> decode(String json) => jsonDecode(json) as Map<String, dynamic>;
