import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/client/client.dart';
import 'package:dsip_app/src/client/models.dart';

/// The fixture `dsip-app`'s own test makes (`crates/dsip-app/tests/wire_fixture.rs`): an update as the app sends it.
Map<String, dynamic> fixture() => jsonDecode(File('test/fixtures/state.json').readAsStringSync()) as Map<String, dynamic>;

/// A client with no app behind it: it records what it is asked, answers as told, and sends the updates a test pushes.
class FakeClient implements Client {
  final commands = <Map<String, dynamic>>[];
  final identities = <(String, String)>[];
  Map<String, dynamic>? started;
  final _updates = StreamController<Update>.broadcast();
  Map<String, dynamic> Function(Map<String, dynamic>) answer = (_) => {'response': 'ok'};
  Object? startFails;

  /// Send an update with [state] (JSON, as the app's).
  void push(Map<String, dynamic> state) => _updates.add(Update.fromJson({'state': state, 'change': null}));

  @override
  Future<String> initIdentity(String dir, String displayName) async {
    identities.add((dir, displayName));
    return 'did:key:z6MkNew';
  }

  @override
  Future<void> start(Map<String, dynamic> settings) async {
    if (startFails != null) throw startFails!;
    started = settings;
  }

  @override
  Future<Map<String, dynamic>> command(Map<String, dynamic> command) async {
    commands.add(command);
    return answer(command);
  }

  @override
  Stream<Update> updates() => _updates.stream;

  @override
  Future<void> stop() async {}
}
