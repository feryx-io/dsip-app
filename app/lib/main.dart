import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/alerts.dart';
import 'src/app.dart';
import 'src/client/rust_client.dart';
import 'src/controller.dart';
import 'src/mobile/platform.dart';
import 'src/rust/frb_generated.dart';
import 'src/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final mobile = NativeMobile.supported ? NativeMobile() : null;
  final dir = await getApplicationSupportDirectory();
  // a desktop installed under the app's old id keeps its identity and settings
  if (mobile == null) {
    try {
      await moveOldFolder(dir);
    } on FileSystemException catch (e) {
      debugPrint('the old folder was not moved: $e');
    }
  }
  final controller = Controller(
    RustClient(),
    SettingsStore(dir),
    // A phone's store updates its app.
    checkUpdates: mobile == null,
    mobile: mobile,
    alerter: SystemAlerter(),
  );
  runApp(DsipApp(controller: controller));
  await controller.load();
}
