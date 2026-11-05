import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A call as the system's call screen shows it.
class SystemCall {
  const SystemCall({required this.id, required this.name, required this.address});

  /// The app's call id.
  final int id;

  /// Who it is with, as a person reads it (a caller's claimed name, else the short DID).
  final String name;

  /// Their DID: the call's handle at the system (`dsip:` on Android).
  final String address;

  Map<String, Object> toMap() => {'id': id, 'name': name, 'address': address};
}

/// What happened at the system's call screen.
enum SystemCallAction {
  /// The system took the call (it rings, or shows as dialling).
  shown,

  /// The system would not take the call: `reason` says why.
  failed,

  /// The user answered, ended or muted the call there.
  answer,
  end,
  mute,
}

class SystemCallEvent {
  const SystemCallEvent(this.action, this.call, {this.on, this.reason});

  final SystemCallAction action;
  final int call;

  /// For `mute`.
  final bool? on;

  /// For `failed`: `filtered` (Do Not Disturb, a blocked caller: the call should not ring), `busy` (another app's
  /// call, an emergency call, does not let it ring), `reset` (the system dropped its calls; they go on in the app), or
  /// `unavailable`.
  final String? reason;
}

/// The phone around the app on Android and iOS (app plan A5): what the app asks of the system there, and the system's
/// own call screen (CallKit, Android's Telecom), which shows the app's calls and hands back what the user does there.
/// None on a desktop and in the screens' tests. As Anvil's U4b, without hold and keys, which DSIP's calls do not have.
abstract class MobilePlatform {
  /// Ask for the microphone (and, where the system asks separately, to show the call's notification) if the system has
  /// not been asked yet; whether the app may use the microphone.
  Future<bool> requestMicrophone();

  /// Set the system's audio up for calls (iOS: play and record, voice chat), before the app starts.
  Future<void> startAudio();

  /// A call ringing in, for the system to ring and show.
  Future<void> reportIncoming(SystemCall call);

  /// A call the user placed, for the system to show as dialling.
  Future<void> reportOutgoing(SystemCall call);

  /// The call was answered.
  Future<void> reportConnected(int call);

  /// The call is over.
  Future<void> reportEnded(int call);

  /// What the user does at the system's call screen.
  Stream<SystemCallEvent> get callEvents;
}

/// The app's own channel to `MainActivity` (Kotlin) and `AppDelegate` (Swift).
class NativeMobile implements MobilePlatform {
  /// One for the app: the channel has one handler for what the system says.
  factory NativeMobile() => _instance;

  NativeMobile._() {
    _channel.setMethodCallHandler(_fromSystem);
  }

  static final _instance = NativeMobile._();
  static const _channel = MethodChannel('dsip/mobile');
  final _events = StreamController<SystemCallEvent>.broadcast();

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<bool> requestMicrophone() async => await _channel.invokeMethod<bool>('requestMicrophone') ?? false;

  @override
  Future<void> startAudio() => _channel.invokeMethod<void>('startAudio');

  @override
  Future<void> reportIncoming(SystemCall call) => _channel.invokeMethod<void>('reportIncoming', call.toMap());

  @override
  Future<void> reportOutgoing(SystemCall call) => _channel.invokeMethod<void>('reportOutgoing', call.toMap());

  @override
  Future<void> reportConnected(int call) => _channel.invokeMethod<void>('reportConnected', {'id': call});

  @override
  Future<void> reportEnded(int call) => _channel.invokeMethod<void>('reportEnded', {'id': call});

  @override
  Stream<SystemCallEvent> get callEvents => _events.stream;

  /// `callEvent` from the native side: `{action, id, on?, reason?}`.
  Future<void> _fromSystem(MethodCall call) async {
    if (call.method != 'callEvent') return;
    final m = Map<String, Object?>.from(call.arguments as Map);
    final action = SystemCallAction.values.where((a) => a.name == m['action']).firstOrNull;
    if (action == null) return;
    _events.add(
      SystemCallEvent(action, (m['id'] as num).toInt(), on: m['on'] as bool?, reason: m['reason'] as String?),
    );
  }
}
