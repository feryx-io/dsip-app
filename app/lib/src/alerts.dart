import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Which alerts the user wants (Settings, Alerts): all on by default. Kept on this device in `alerts.json`, beside
/// `settings.json` (which is `dsip-app`'s, so this is not in it).
class AlertSettings {
  const AlertSettings({this.enabled = true, this.messages = true, this.requests = true, this.calls = true});

  /// Any alert at all.
  final bool enabled;

  /// A message in a conversation.
  final bool messages;

  /// Someone asks to message you, or accepts your asking.
  final bool requests;

  /// A missed call; on a desktop, a call ringing while the app is not in front too (a phone rings on its own screen).
  final bool calls;

  AlertSettings copyWith({bool? enabled, bool? messages, bool? requests, bool? calls}) => AlertSettings(
    enabled: enabled ?? this.enabled,
    messages: messages ?? this.messages,
    requests: requests ?? this.requests,
    calls: calls ?? this.calls,
  );

  Map<String, dynamic> toJson() => {'enabled': enabled, 'messages': messages, 'requests': requests, 'calls': calls};

  factory AlertSettings.fromJson(Map<String, dynamic> j) => AlertSettings(
    enabled: j['enabled'] as bool? ?? true,
    messages: j['messages'] as bool? ?? true,
    requests: j['requests'] as bool? ?? true,
    calls: j['calls'] as bool? ?? true,
  );

  /// The settings kept in [dir], or the defaults.
  static Future<AlertSettings> load(Directory dir) async {
    try {
      final f = File('${dir.path}${Platform.pathSeparator}alerts.json');
      if (!await f.exists()) return const AlertSettings();
      return AlertSettings.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const AlertSettings();
    }
  }

  Future<void> save(Directory dir) async {
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}alerts.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()));
    await tmp.rename(f.path);
  }
}

/// One alert: what it says, and what tapping it opens ([payload]: `conversation:<group>`, `messages` or `calls`).
class Alert {
  const Alert(this.title, this.body, this.payload);
  final String title;
  final String body;
  final String payload;
}

/// Where alerts are shown while the app is not in front: the system's notifications. Tests give their own.
abstract class Alerter {
  /// Get ready; [opened] is called with an alert's payload when the user taps it.
  Future<void> init(void Function(String payload) opened);

  /// Show [alert], replacing the one shown before under the same [id].
  Future<void> show(int id, Alert alert);
}

/// The system's notifications (flutter_local_notifications): Android's and Apple's notification centres, Windows'
/// toasts, the Linux desktop's notifications over D-Bus.
class SystemAlerter implements Alerter {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'dsip-alerts',
    'Messages and calls',
    channelDescription: 'New messages, requests to message you, and missed calls',
    importance: Importance.high,
    priority: Priority.high,
  );

  @override
  Future<void> init(void Function(String payload) opened) async {
    try {
      _ready = await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(),
              macOS: DarwinInitializationSettings(),
              linux: LinuxInitializationSettings(defaultActionName: 'Open'),
              windows: WindowsInitializationSettings(
                appName: 'DSIP',
                appUserModelId: 'com.thevoiceguy.dsip',
                guid: '5b0c7d2e-4c1f-4f63-9a43-7d5d2f1e8a61',
              ),
            ),
            onDidReceiveNotificationResponse: (r) => opened(r.payload ?? ''),
          ) ??
          false;
      // Android 13 and later ask before an app may notify
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('alerts: not available: $e');
    }
  }

  @override
  Future<void> show(int id, Alert alert) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: alert.title,
        body: alert.body,
        notificationDetails: const NotificationDetails(android: _channel),
        payload: alert.payload,
      );
    } catch (e) {
      debugPrint('alerts: $e');
    }
  }
}
