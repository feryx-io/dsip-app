import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'client/client.dart';
import 'client/models.dart';
import 'mobile/calls.dart';
import 'mobile/platform.dart';
import 'settings.dart';

/// The app as the screens see it: first run until there are settings, then the running app's state, one update at a
/// time. Every action is a `dsip-app` command; nothing here decides what the protocol does.
class Controller extends ChangeNotifier {
  Controller(this.client, this.store, {this.checkUpdates = false, this.mobile, void Function()? quit})
    : quit = quit ?? (() => exit(0)) {
    final mobile = this.mobile;
    if (mobile != null) {
      _system = SystemCalls(
        mobile,
        run: run,
        calls: () => state?.calls ?? const [],
        failed: (why) {
          error = why;
          notifyListeners();
        },
      );
    }
  }

  /// The system's call screen and where a call's audio goes, on a phone.
  SystemCalls? _system;
  SystemCalls? get system => _system;

  final Client client;
  final SettingsStore store;

  /// The phone around the app, on Android and iOS; null on a desktop. A phone's app is updated by its store, not by
  /// itself.
  final MobilePlatform? mobile;

  /// The system said no to the microphone: calls still ring and connect, but the other side hears nothing.
  bool microphoneRefused = false;

  /// Look for a newer release half a minute after the start and every hour (the app does; tests do not).
  final bool checkUpdates;

  /// End this process, for an update to install: [exit] in the app.
  final void Function() quit;

  /// A newer release, once a check found one.
  UpdateInfo? update;

  /// The version the user said "Later" to: its banner is not shown again.
  String? updateDismissed;

  /// Where updating is: `idle`, `checking`, `latest` (a check found nothing newer), `downloading`, `failed`.
  String updateStatus = 'idle';

  /// Why the last check or update failed.
  String? updateError;

  Timer? _updateTimer;

  /// Null before the app runs (first run, or starting).
  AppState? state;

  /// Whether the app has settings to start from; null until [load] knows.
  bool? configured;

  /// The settings the app runs with (`dsip-app`'s `Settings` as JSON), as saved.
  Map<String, dynamic>? settings;

  /// The home screen's tab: kept here, so that the app starting again (new settings) comes back to it.
  int tab = 0;

  /// The latest command that failed, for the screen to show once.
  String? error;

  /// Something the app was told that the user should see once: a grant arrived, this identity was removed from a
  /// conversation (the change's JSON).
  Map<String, dynamic>? notice;

  /// The messages of the conversations opened, by group id, oldest first: loaded by [openThread], then kept up by
  /// the messages that arrive.
  final threads = <String, List<MessageView>>{};

  StreamSubscription<Update>? _updates;

  /// Read the settings; start the app when there are some.
  Future<void> load() async {
    final settings = this.settings = await store.load();
    configured = settings != null;
    notifyListeners();
    if (checkUpdates) {
      _updateTimer = Timer(const Duration(seconds: 30), () {
        checkForUpdate();
        _updateTimer = Timer.periodic(const Duration(hours: 1), (_) => checkForUpdate());
      });
    }
    if (settings != null) await _start(settings);
  }

  /// First run: make the identity when [displayName] is given, or restore it from [restore] (a recovery code and its
  /// passphrase) under that name (else the settings name one that exists), save the settings, start.
  /// With [joinWelcome], the identity is another device's, joined by the pairing codes (A6).
  Future<void> setUp({
    required Map<String, dynamic> settings,
    String? displayName,
    (String, String)? restore,
    String? joinWelcome,
  }) async {
    final dir = settings['identity'] as String;
    if (joinWelcome != null) {
      await client.pairingFinish(dir, joinWelcome);
    } else if (restore != null) {
      await client.restoreIdentity(dir, restore.$1, restore.$2, displayName ?? '');
    } else if (displayName != null) {
      await client.initIdentity(dir, displayName);
    }
    await store.save(settings);
    this.settings = settings;
    configured = true;
    await _start(settings);
  }

  /// Stop the app, save [settings], start it again with them: what changing the relay, mailbox or hints nodes takes.
  /// Calls up end. If it does not start, the state stays empty and [error] says why.
  /// [between] runs while the app is stopped (moving the identity, A6d); its failure is [error], and the app starts
  /// again as it was.
  Future<void> restart(Map<String, dynamic> settings, {Future<void> Function()? between}) async {
    await _updates?.cancel();
    _updates = null;
    await client.stop();
    state = null;
    _system?.sync(const []);
    threads.clear();
    notifyListeners();
    if (between != null) {
      try {
        await between();
      } catch (e) {
        error = '$e';
      }
    }
    await store.save(settings);
    this.settings = settings;
    try {
      await _start(settings);
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  /// Move the identity onto a domain of its own: the `did:web` of [plan] ([Client.webPrepare], checked by
  /// [Client.webCheck]), with the app stopped while it moves, and started again as it (A6d).
  Future<void> moveToWeb(Map<String, dynamic> plan) async {
    final s = settings;
    if (s == null) return;
    await restart(s, between: () async {
      await client.webMove(s['identity'] as String, plan);
    });
  }

  /// Use the microphone [input] and the speaker [output] (device ids; null: the system's default), and keep the
  /// choice in the settings for the next start.
  Future<void> chooseAudio({String? input, String? output}) async {
    final r = await run({'command': 'choose_audio', 'input': ?input, 'output': ?output});
    if (errorOf(r) != null || settings == null) return;
    final s = {...settings!}
      ..remove('audio_input')
      ..remove('audio_output');
    settings = {...s, 'audio_input': ?input, 'audio_output': ?output};
    await store.save(settings!);
  }

  Future<void> _start(Map<String, dynamic> settings) async {
    final mobile = this.mobile;
    if (mobile != null) {
      // Before the app starts, as on Anvil: a refusal is told, and the app still starts.
      microphoneRefused = !await mobile.requestMicrophone();
      try {
        await mobile.startAudio();
      } catch (e) {
        error = '$e';
      }
    }
    await client.start(settings);
    _updates = client.updates().listen((u) {
      state = u.state;
      _system?.sync(u.state.calls, u.state);
      switch (u.kind) {
        case 'message':
          final m = MessageView.fromJson(u.change!['message'] as Map<String, dynamic>);
          final thread = threads[m.conversation];
          if (thread != null && !thread.any((t) => t.id == m.id)) thread.add(m);
        case 'granted' || 'removed':
          notice = u.change;
      }
      notifyListeners();
    });
  }

  /// Do [command]; on an error response, [error] says why. Returns the response.
  Future<Map<String, dynamic>> run(Map<String, dynamic> command) async {
    final r = await client.command(command);
    final e = errorOf(r);
    if (e != null) {
      error = e;
      notifyListeners();
    }
    return r;
  }

  /// Load the messages of the conversation [group].
  Future<void> openThread(String group) async {
    final r = await run({'command': 'thread', 'conversation': group});
    if (r['response'] != 'thread') return;
    threads[group] = [for (final m in r['messages'] as List) MessageView.fromJson(m as Map<String, dynamic>)];
    notifyListeners();
  }

  /// Whether a call is placed, ringing or up: no update restarts the app then.
  bool get inCall => state?.calls.any((c) => !c.state.ended) ?? false;

  /// Look for a newer release.
  Future<void> checkForUpdate() async {
    if (updateStatus == 'checking' || updateStatus == 'downloading') return;
    updateStatus = 'checking';
    notifyListeners();
    try {
      update = await client.checkForUpdate();
      updateStatus = update == null ? 'latest' : 'idle';
      updateError = null;
    } catch (e) {
      updateStatus = 'failed';
      updateError = '$e';
    }
    notifyListeners();
  }

  /// Not now: the banner for [update]'s version goes until a newer one.
  void dismissUpdate() {
    updateDismissed = update?.version;
    notifyListeners();
  }

  /// Update and restart: look again (an offer made hours ago installs the release out now, as Anvil learnt), fetch
  /// it, stop the app, and quit for the installer, which starts the app again. Not during a call.
  Future<void> installUpdate() async {
    if (inCall) return;
    await checkForUpdate();
    final u = update;
    if (u == null || !u.canInstall || updateStatus == 'failed') return;
    updateStatus = 'downloading';
    notifyListeners();
    var stopped = false;
    try {
      await client.downloadUpdate();
      await _updates?.cancel();
      _updates = null;
      await client.stop();
      stopped = true;
      await client.installUpdate();
    } catch (e) {
      updateStatus = 'failed';
      updateError = '$e';
      notifyListeners();
      // the app stopped for an install that did not start: it runs again as it was
      if (stopped && settings != null) await _start(settings!);
      return;
    }
    quit();
  }

  /// The notice shown: cleared once read.
  Map<String, dynamic>? takeNotice() {
    final n = notice;
    notice = null;
    return n;
  }

  /// The error shown: cleared once read.
  String? takeError() {
    final e = error;
    error = null;
    return e;
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _updates?.cancel();
    _system?.dispose();
    super.dispose();
  }
}
