import 'dart:async';

import 'package:dsip_app/src/mobile/platform.dart';

import 'fake_client.dart';

/// The phone around the app, as a log of what it was told and a way for a test to act at the system's call screen.
class FakeMobile implements MobilePlatform {
  FakeMobile({this.allow = true, this.client});
  final bool allow;

  /// When given, the log says whether the app had started yet.
  final FakeClient? client;
  final log = <String>[];
  final _events = StreamController<SystemCallEvent>.broadcast();

  String get _when => client?.started == null ? '' : ' after start';

  /// The user does something at the system's call screen.
  void act(SystemCallEvent event) => _events.add(event);

  @override
  Future<bool> requestMicrophone() async {
    log.add('requestMicrophone$_when');
    return allow;
  }

  @override
  Future<void> startAudio() async => log.add('startAudio$_when');

  @override
  Future<void> reportIncoming(SystemCall call) async => log.add('incoming ${call.id} ${call.name} ${call.address}');

  @override
  Future<void> reportOutgoing(SystemCall call) async => log.add('outgoing ${call.id} ${call.name} ${call.address}');

  @override
  Future<void> reportConnected(int call) async => log.add('connected $call');

  @override
  Future<void> reportEnded(int call) async => log.add('ended $call');

  @override
  Stream<SystemCallEvent> get callEvents => _events.stream;
}
