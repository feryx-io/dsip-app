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

/// Where a call's audio goes: the phone held to the ear, its loudspeaker, a Bluetooth headset or car, a headset on a
/// wire.
enum AudioRoute { earpiece, speaker, bluetooth, wired }

/// The routes a call may take now, and the one it takes.
class AudioRoutes {
  const AudioRoutes({required this.current, required this.available, this.bluetoothName});

  final AudioRoute current;
  final List<AudioRoute> available;

  /// The Bluetooth device's own name, when the system gives it.
  final String? bluetoothName;

  /// Only the earpiece and the speaker: a speaker switch is enough.
  bool get justSpeaker =>
      available.length == 2 && available.contains(AudioRoute.earpiece) && available.contains(AudioRoute.speaker);

  /// From the native side's `{current, available, bluetoothName}`; null when it names no route.
  static AudioRoutes? fromMap(Object? raw) {
    if (raw is! Map) return null;
    AudioRoute? route(Object? name) => AudioRoute.values.where((r) => r.name == name).firstOrNull;
    final current = route(raw['current']);
    if (current == null) return null;
    final available = [for (final r in (raw['available'] as List? ?? const [])) ?route(r)];
    return AudioRoutes(
      current: current,
      available: available.contains(current) ? available : [...available, current],
      bluetoothName: raw['bluetoothName'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioRoutes &&
      other.current == current &&
      listEquals(other.available, available) &&
      other.bluetoothName == bluetoothName;

  @override
  int get hashCode => Object.hash(current, Object.hashAll(available), bluetoothName);
}

/// The phone around the app on Android and iOS (app plan A5): what the app asks of the system there (the microphone,
/// the audio session, where a call's audio goes, the proximity sensor), and the system's own call screen (CallKit,
/// Android's Telecom), which shows the app's calls and hands back what the user does there.
/// None on a desktop and in the screens' tests. As Anvil's U4b, without hold and keys, which DSIP's calls do not have.
abstract class MobilePlatform {
  /// Ask for the microphone (and, where the system asks separately, to show the call's notification) if the system has
  /// not been asked yet; whether the app may use the microphone.
  Future<bool> requestMicrophone();

  /// Ask for the camera, for a video call, if the system has not been asked yet; whether the app may use it.
  Future<bool> requestCamera();

  /// Set the system's audio up for calls (iOS: play and record, voice chat), before the app starts.
  Future<void> startAudio();

  /// Whether the system's call screen follows the Rust core itself, Dart or not (Telecom on Android, A5d-2; CallKit on
  /// iOS, A5d-3: a push starts the app with no Flutter running): Dart then reports no calls and acts on nothing done
  /// there.
  bool get systemFollowsCore;

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

  /// The routes a call's audio may take, as the system has them now (none known: null), and each change to them
  /// (A5c).
  Future<AudioRoutes?> audioRoutes();
  Stream<AudioRoutes> get audioRouteChanges;

  /// Send the call's audio this way.
  Future<void> setAudioRoute(AudioRoute route);

  /// Turn the screen off while the phone is held to the ear (a call on the earpiece), or stop.
  Future<void> setProximity(bool on);
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
  final _routes = StreamController<AudioRoutes>.broadcast();

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<bool> requestMicrophone() async => await _channel.invokeMethod<bool>('requestMicrophone') ?? false;

  @override
  Future<bool> requestCamera() async {
    try {
      return await _channel.invokeMethod<bool>('requestCamera') ?? false;
    } on MissingPluginException {
      return false; // a system without video calls (iOS, for now)
    }
  }

  @override
  Future<void> startAudio() => _channel.invokeMethod<void>('startAudio');

  @override
  bool get systemFollowsCore => supported;

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

  @override
  Future<AudioRoutes?> audioRoutes() async => AudioRoutes.fromMap(await _channel.invokeMethod<Object>('audioRoutes'));

  @override
  Stream<AudioRoutes> get audioRouteChanges => _routes.stream;

  @override
  Future<void> setAudioRoute(AudioRoute route) => _channel.invokeMethod<void>('setAudioRoute', {'route': route.name});

  @override
  Future<void> setProximity(bool on) => _channel.invokeMethod<void>('setProximity', {'on': on});

  /// From the native side: `audioRoutes` (`{current, available, bluetoothName}`) at each change of route, and
  /// `callEvent` (`{action, id, on?, reason?}`).
  Future<void> _fromSystem(MethodCall call) async {
    if (call.method == 'audioRoutes') {
      final routes = AudioRoutes.fromMap(call.arguments);
      if (routes != null) _routes.add(routes);
      return;
    }
    if (call.method != 'callEvent') return;
    final m = Map<String, Object?>.from(call.arguments as Map);
    final action = SystemCallAction.values.where((a) => a.name == m['action']).firstOrNull;
    if (action == null) return;
    _events.add(
      SystemCallEvent(action, (m['id'] as num).toInt(), on: m['on'] as bool?, reason: m['reason'] as String?),
    );
  }
}
