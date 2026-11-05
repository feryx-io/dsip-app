import 'dart:convert';
import 'dart:io';

import 'package:dsip_app/src/app.dart';
import 'package:dsip_app/src/client/rust_client.dart';
import 'package:dsip_app/src/controller.dart';
import 'package:dsip_app/src/mobile/platform.dart';
import 'package:dsip_app/src/rust/api/app.dart' as rust;
import 'package:dsip_app/src/rust/frb_generated.dart';
import 'package:dsip_app/src/screens/first_run.dart';
import 'package:dsip_app/src/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The app as built for a phone (app plan A5), its Rust core loaded: it starts at the first run, makes an identity,
/// and, the audio set up for calls, reaches the phone's microphone and speaker from Rust (on Android through the JVM
/// `MainActivity` hands over); and the system's call screen takes a call ringing in and a call placed (A5b). Run on an emulator or a simulator (CI's Android and iOS jobs):
/// `flutter test integration_test/mobile_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('the app starts with its Rust core, at the first run', (tester) async {
    expect(NativeMobile.supported, isTrue);
    final dir = Directory.systemTemp.createTempSync('dsip-app-mobile');
    // Not the microphone: asking would wait on the system's dialog. The next test sets the audio up.
    final controller = Controller(RustClient(), SettingsStore(dir));
    await tester.pumpWidget(DsipApp(controller: controller));
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.byType(FirstRun), findsOneWidget);
    final did = await RustClient().initIdentity('${dir.path}/identity', 'Alice');
    expect(did, startsWith('did:key:z6Mk'));
    dir.deleteSync(recursive: true);
  });

  // As the app does before it starts: on iOS the microphone is an input only once the session plays and records.
  testWidgets('the audio is set up for calls, and Rust reaches it', (tester) async {
    await NativeMobile().startAudio();
    final audio = jsonDecode(await rust.systemAudio()) as Map<String, dynamic>;
    final devices = (audio['devices'] as List).cast<Map<String, dynamic>>();
    expect(audio['host'], 'system');
    expect(devices.where((d) => d['kind'] == 'input'), isNotEmpty, reason: 'a microphone: $devices');
    expect(devices.where((d) => d['kind'] == 'output'), isNotEmpty, reason: 'a speaker: $devices');
  });

  /// The next event the system sends for [call]; none within ten seconds is null.
  Future<SystemCallEvent?> next(int call) async {
    try {
      return await NativeMobile().callEvents.firstWhere((e) => e.call == call).timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  /// Telecom on Android (the emulator has it) takes the call; CallKit on iOS may refuse it on a simulator, and then
  /// the app rings on its own, and nothing breaks.
  void taken(SystemCallEvent? event) => Platform.isAndroid
      ? expect(event?.action, SystemCallAction.shown)
      : expect(event?.action, isIn([SystemCallAction.shown, SystemCallAction.failed]));

  testWidgets('the system takes a call ringing in, and lets it go', (tester) async {
    final mobile = NativeMobile();
    final said = mobile.callEvents.listen((e) => debugPrint('system: ${e.action.name} ${e.call} ${e.reason ?? ''}'));
    addTearDown(said.cancel);
    final shown = next(901);
    await mobile.reportIncoming(const SystemCall(id: 901, name: 'Bob', address: 'did:key:z6MkBob'));
    taken(await shown);
    await mobile.reportConnected(901);
    await mobile.reportEnded(901);
  });

  testWidgets('the system takes a call placed, and lets it go', (tester) async {
    final mobile = NativeMobile();
    final shown = next(902);
    await mobile.reportOutgoing(const SystemCall(id: 902, name: 'Carol', address: 'did:key:z6MkCarol'));
    taken(await shown);
    await mobile.reportConnected(902);
    await mobile.reportEnded(902);
  });
}
