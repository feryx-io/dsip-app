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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// The app as built for a phone (app plan A5), its Rust core loaded: it starts at the first run, makes an identity,
/// and, the audio set up for calls, reaches the phone's microphone and speaker from Rust (on Android through the JVM
/// `MainActivity` hands over); the system's call screen takes a call ringing in and a call placed (A5b); and a call's
/// audio goes to the speaker and back (A5c); on Android, a wake rings at once, before the app has started (A5d-2). Run on an emulator or a simulator (CI's Android and iOS jobs):
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

  /// The routes once [ok] holds, asked now and at each change; none within ten seconds is null.
  Future<AudioRoutes?> routesWhen(bool Function(AudioRoutes) ok) async {
    final mobile = NativeMobile();
    final now = await mobile.audioRoutes();
    if (now != null && ok(now)) return now;
    try {
      return await mobile.audioRouteChanges.firstWhere(ok).timeout(const Duration(seconds: 10));
    } catch (_) {
      final last = await mobile.audioRoutes();
      return last != null && ok(last) ? last : null;
    }
  }

  // Android's routes come with a Telecom call; iOS's from the audio session.
  testWidgets("a call's audio goes to the speaker and back", (tester) async {
    final mobile = NativeMobile();
    if (Platform.isAndroid) {
      final shown = next(903);
      await mobile.reportIncoming(const SystemCall(id: 903, name: 'Bob', address: 'did:key:z6MkBob'));
      expect((await shown)?.action, SystemCallAction.shown);
      await mobile.reportConnected(903);
    }
    final routes = await routesWhen((r) => r.available.isNotEmpty);
    debugPrint('routes: ${routes?.current.name} of ${routes?.available.map((r) => r.name).join(',')}');
    expect(routes, isNotNull);
    expect(routes!.available, contains(AudioRoute.speaker));
    await mobile.setAudioRoute(AudioRoute.speaker);
    if (Platform.isAndroid) {
      expect(await routesWhen((r) => r.current == AudioRoute.speaker), isNotNull, reason: 'Telecom moved it to the speaker');
      if (routes.available.contains(AudioRoute.earpiece)) {
        await mobile.setAudioRoute(AudioRoute.earpiece);
        expect(await routesWhen((r) => r.current == AudioRoute.earpiece), isNotNull, reason: 'and back to the earpiece');
      }
    }
    await mobile.setProximity(true);
    await mobile.setProximity(false);
    if (Platform.isAndroid) await mobile.reportEnded(903);
  });

  // Android woken by FCM (A5d-2): pushes handed in as FCM delivers them (the debug build's `deliverPush`), to the app's
  // own folder, where Dart keeps its settings.
  const channel = MethodChannel('dsip/mobile');
  Future<List<int>> systemCalls() async => [
    for (final id in await channel.invokeListMethod<num>('systemCalls') ?? const <num>[]) id.toInt(),
  ];
  Future<bool> until(bool Function(List<int> calls) ok) async {
    for (var i = 0; i < 100; i++) {
      if (ok(await systemCalls())) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  bool pushed(List<int> calls) => calls.any((id) => id < 0);
  Map<String, String> wake(String kind, String session) => {
    'dsip-wake': jsonEncode({'kind': kind, 'waker': 'did:web:relay.example', 'session': session}),
  };

  testWidgets('a wake for an app not set up rings nothing', (tester) async {
    await channel.invokeMethod<void>('deliverPush', wake('call', '01K8S0E8M3000000000INVITE01'));
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(pushed(await systemCalls()), isFalse);
  }, skip: !Platform.isAndroid);

  testWidgets('a call wake rings at once, and stops when the app cannot start', (tester) async {
    final folder = await getApplicationSupportDirectory();
    final settings = File('${folder.path}/settings.json');
    // settings naming an identity that is not there: the core does not start
    await SettingsStore(folder).save({'identity': '${folder.path}/no-identity', 'relay': 'wss://127.0.0.1:9/dsip'});
    addTearDown(() {
      if (settings.existsSync()) settings.deleteSync();
    });
    final shown = NativeMobile().callEvents.firstWhere((e) => e.call < 0).timeout(const Duration(seconds: 10));
    await channel.invokeMethod<void>('deliverPush', wake('call', '01K8S0E8M3000000000INVITE02'));
    expect((await shown).action, SystemCallAction.shown, reason: 'Telecom took the call the wake told of');
    expect(await until((calls) => !pushed(calls)), isTrue, reason: 'it ends when the app cannot start');
  }, skip: !Platform.isAndroid);
}
