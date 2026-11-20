import 'dart:io';

import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// The app in Windows' notification area (`windows/runner/tray.cpp`): closing the window hides it there, so calls
/// still ring; the icon opens it again, and Quit in the icon's menu ends the app. The runner does it all; from here
/// it only learns its menu's words in the app's language.
class Tray {
  static const _channel = MethodChannel('dsip/tray');
  static String? _told;

  /// Give the runner its words from [s], once a language. Nothing on other systems.
  static void labels(Strings s) {
    if (!Platform.isWindows || _told == s.localeName) return;
    _told = s.localeName;
    _channel
        .invokeMethod<void>('labels', {'open': s.trayOpen, 'quit': s.trayQuit, 'running': s.trayRunning})
        // a runner without a tray (a test's): its own words stay
        .catchError((Object _) {});
  }
}
