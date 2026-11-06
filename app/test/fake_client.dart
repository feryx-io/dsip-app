import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/client/client.dart';
import 'package:dsip_app/src/client/models.dart';

/// The fixture `dsip-app`'s own test makes (`crates/dsip-app/tests/wire_fixture.rs`): an update as the app sends it.
Map<String, dynamic> fixture() => jsonDecode(File('test/fixtures/state.json').readAsStringSync()) as Map<String, dynamic>;

/// The messages fixture, from the same test: a `thread` response, a `message` change, a `conversation` response, a
/// `granted` and a `removed` change.
Map<String, dynamic> messagesFixture() =>
    jsonDecode(File('test/fixtures/messages.json').readAsStringSync()) as Map<String, dynamic>;

/// A client with no app behind it: it records what it is asked, answers as told, and sends the updates a test pushes.
class FakeClient implements Client {
  final commands = <Map<String, dynamic>>[];
  final identities = <(String, String)>[];
  Map<String, dynamic>? started;
  int stops = 0;
  final _updates = StreamController<Update>.broadcast();
  Map<String, dynamic> Function(Map<String, dynamic>) answer = (_) => {'response': 'ok'};
  Object? startFails;

  /// Send an update with [state] (JSON, as the app's), after [change] if one is given.
  void push(Map<String, dynamic> state, [Map<String, dynamic>? change]) =>
      _updates.add(Update.fromJson({'state': state, 'change': change}));

  @override
  Future<String> initIdentity(String dir, String displayName) async {
    identities.add((dir, displayName));
    return 'did:key:z6MkNew';
  }

  /// What [restoreIdentity] was given: dir, code, passphrase, name.
  final restored = <(String, String, String, String)>[];

  /// What [exportIdentity] was given: dir, passphrase.
  final exported = <(String, String)>[];

  @override
  Future<IdentityBackup> exportIdentity(String dir, String passphrase) async {
    exported.add((dir, passphrase));
    return const IdentityBackup(identity: 'did:key:z6MkAnn', code: 'DSIP1-AAAAA-BBBBB', file: 'DSIP identity backup\n\nDSIP1-AAAAA-BBBBB\n');
  }

  @override
  Future<String> restoreIdentity(String dir, String code, String passphrase, String displayName) async {
    restored.add((dir, code, passphrase, displayName));
    return 'did:key:z6MkAnn';
  }

  /// What [webCheck] answers.
  List<String> webDiffers = const [];

  /// The DIDs [webMove] moved to, and whether the app was stopped then.
  final moves = <(String, bool)>[];
  bool _running = false;

  @override
  Future<Map<String, dynamic>> webPrepare(String dir, String did, String relay, {String? mailboxDid, String? mailboxUri}) async => {
    'did': did,
    'url': 'https://${did.substring('did:web:'.length).split(':').first}/.well-known/did.json',
    'document': {'id': did, 'service': [{'type': 'DSIPSignaling', 'serviceEndpoint': {'uri': relay}}]},
  };

  @override
  Future<List<String>> webCheck(Map<String, dynamic> plan) async => webDiffers;

  @override
  Future<String> webMove(String dir, Map<String, dynamic> plan) async {
    moves.add((plan['did'] as String, !_running));
    return plan['did'] as String;
  }

  @override
  Future<void> start(Map<String, dynamic> settings) async {
    _running = true;
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
  Future<void> stop() async {
    _running = false;
    stops++;
  }

  /// What [checkForUpdate] finds (null: nothing newer), or throws.
  UpdateInfo? release;
  Object? checkFails;
  Object? installFails;
  int checks = 0;

  /// The update calls made, in order: `download`, `install`.
  final updating = <String>[];

  @override
  String appVersion() => '0.1.0';

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    checks++;
    if (checkFails != null) throw checkFails!;
    return release;
  }

  @override
  Future<void> downloadUpdate() async => updating.add('download');

  @override
  Future<void> installUpdate() async {
    if (installFails != null) throw installFails!;
    updating.add('install');
  }
}
