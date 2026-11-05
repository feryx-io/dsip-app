import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
  final controller = Controller(
    RustClient(),
    SettingsStore(await getApplicationSupportDirectory()),
    // A phone's store updates its app.
    checkUpdates: mobile == null,
    mobile: mobile,
  );
  runApp(DsipApp(controller: controller));
  await controller.load();
}
