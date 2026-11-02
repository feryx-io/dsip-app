import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/client/rust_client.dart';
import 'src/controller.dart';
import 'src/rust/frb_generated.dart';
import 'src/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final controller = Controller(RustClient(), SettingsStore(await getApplicationSupportDirectory()));
  runApp(DsipApp(controller: controller));
  await controller.load();
}
