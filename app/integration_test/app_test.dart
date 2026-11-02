import 'dart:io';

import 'package:dsip_app/src/client/client.dart';
import 'package:dsip_app/src/client/rust_client.dart';
import 'package:dsip_app/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The app as built, its Rust core loaded: `dsip-app` itself answers through the bridge.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('the Rust core makes an identity and answers commands', (tester) async {
    final client = RustClient();
    final dir = Directory.systemTemp.createTempSync('dsip-app-it');
    final did = await client.initIdentity('${dir.path}${Platform.pathSeparator}identity', 'Alice');
    expect(did, startsWith('did:key:z6Mk'));
    // not started: the app says so, as JSON from dsip-app's own Response
    final r = await client.command({'command': 'state'});
    expect(errorOf(r), 'the app is not running');
    final bad = await client.command({'command': 'fly'});
    expect(errorOf(bad), anyOf('the app is not running', startsWith('not a command')));
    dir.deleteSync(recursive: true);
  });
}
