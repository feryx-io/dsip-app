import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client/client.dart';
import 'client/models.dart';
import 'settings.dart';

/// The app as the screens see it: first run until there are settings, then the running app's state, one update at a
/// time. Every action is a `dsip-app` command; nothing here decides what the protocol does.
class Controller extends ChangeNotifier {
  Controller(this.client, this.store);

  final Client client;
  final SettingsStore store;

  /// Null before the app runs (first run, or starting).
  AppState? state;

  /// Whether the app has settings to start from; null until [load] knows.
  bool? configured;

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
    final settings = await store.load();
    configured = settings != null;
    notifyListeners();
    if (settings != null) await _start(settings);
  }

  /// First run: make the identity when [displayName] is given (else the settings name one that exists), save the
  /// settings, start.
  Future<void> setUp({required Map<String, dynamic> settings, String? displayName}) async {
    if (displayName != null) await client.initIdentity(settings['identity'] as String, displayName);
    await store.save(settings);
    configured = true;
    await _start(settings);
  }

  Future<void> _start(Map<String, dynamic> settings) async {
    await client.start(settings);
    _updates = client.updates().listen((u) {
      state = u.state;
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
    _updates?.cancel();
    super.dispose();
  }
}
