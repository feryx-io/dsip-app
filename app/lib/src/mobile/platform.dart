import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone around the app on Android and iOS (app plan A5): what the app asks of the system there. None on a desktop
/// and in the screens' tests.
abstract class MobilePlatform {
  /// Ask for the microphone if the system has not been asked yet; whether the app may use it.
  Future<bool> requestMicrophone();

  /// Set the system's audio up for calls (iOS: play and record, voice chat), before the app starts.
  Future<void> startAudio();
}

/// The app's own channel to `MainActivity` (Kotlin) and `AppDelegate` (Swift).
class NativeMobile implements MobilePlatform {
  static const _channel = MethodChannel('dsip/mobile');

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<bool> requestMicrophone() async => await _channel.invokeMethod<bool>('requestMicrophone') ?? false;

  @override
  Future<void> startAudio() => _channel.invokeMethod<void>('startAudio');
}
