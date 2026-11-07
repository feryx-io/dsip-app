import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import 'client/models.dart';
import 'controller.dart';
import 'screens/update.dart';
import 'screens/calls.dart';
import 'screens/first_run.dart';
import 'screens/me.dart';
import 'screens/messages.dart';
import 'screens/presence.dart';
import 'screens/settings.dart';

/// The app: the first run until there are settings, then the home screen over the running app's state.
class DsipApp extends StatelessWidget {
  const DsipApp({super.key, required this.controller});
  final Controller controller;

  /// Lay every screen out in this direction whatever the locale: the tests' right-to-left check (A7), as no
  /// right-to-left locale ships yet.
  @visibleForTesting
  static TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, child) =>
        textDirection == null ? child! : Directionality(textDirection: textDirection!, child: child!),
    onGenerateTitle: (context) => Strings.of(context).appName,
    localizationsDelegates: const [...Strings.localizationsDelegates, GlobalMaterialLocalizations.delegate],
    supportedLocales: Strings.supportedLocales,
    theme: ThemeData(colorSchemeSeed: Colors.teal, fontFamily: 'Inter'),
    darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, fontFamily: 'Inter'),
    home: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => switch ((controller.configured, controller.state)) {
        (false, _) => FirstRun(controller: controller),
        (true, final state?) => Home(controller: controller, state: state),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      },
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.controller, required this.state});
  final Controller controller;
  final AppState state;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int get _tab => widget.controller.tab;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final error = widget.controller.takeError();
    final notice = widget.controller.takeNotice();
    final told = switch (notice?['change']) {
      'granted' => s.noticeGranted(shortDid(notice!['by'] as String)),
      'removed' => s.noticeRemoved(shortDid(notice!['by'] as String)),
      _ => null,
    };
    for (final text in [if (error != null) s.commandFailed(error), ?told]) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))),
      );
    }
    final state = widget.state;
    final destinations = <(Widget, String)>[
      (const Icon(Icons.call), s.navCalls),
      (
        Badge(
          isLabelVisible: state.messaging.requests.isNotEmpty,
          label: Text('${state.messaging.requests.length}'),
          child: const Icon(Icons.chat),
        ),
        s.navMessages,
      ),
      (PresenceDot(state.presence.mine ?? 'available'), s.navPresence),
      (const Icon(Icons.person), s.navMe),
      (const Icon(Icons.settings), s.navSettings),
    ];
    void select(int i) => setState(() => widget.controller.tab = i);
    final body = Column(
      children: [
        UpdateBanner(controller: widget.controller),
        if (widget.controller.microphoneRefused)
          MaterialBanner(
            key: const Key('microphone-refused'),
            leading: const Icon(Icons.mic_off),
            content: Text(s.microphoneRefused),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(
          child: switch (_tab) {
            0 => CallsScreen(controller: widget.controller, state: state),
            1 => MessagesScreen(controller: widget.controller, state: state),
            2 => PresenceScreen(controller: widget.controller, state: state),
            3 => MeScreen(state: state),
            _ => SettingsScreen(controller: widget.controller, state: state),
          },
        ),
      ],
    );
    // A phone (or a narrow window): the tabs along the bottom, clear of the system's bars; else down the side.
    if (MediaQuery.sizeOf(context).width < 600) {
      return CallKeys(controller: widget.controller, state: state, child: Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: select,
          destinations: [for (final (icon, label) in destinations) NavigationDestination(icon: icon, label: label)],
        ),
      ));
    }
    return CallKeys(controller: widget.controller, state: state, child: Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: select,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final (icon, label) in destinations) NavigationRailDestination(icon: icon, label: Text(label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    ));
  }
}

/// The calls from the keyboard, wherever the app is (A7): Ctrl+Enter answers the call ringing in, Ctrl+Backspace
/// declines it or hangs up the call in progress, Ctrl+M mutes or unmutes it; Cmd in place of Ctrl on a Mac. A text
/// field being typed in keeps its own keys (Ctrl+Backspace deletes a word there).
class CallKeys extends StatelessWidget {
  const CallKeys({super.key, required this.controller, required this.state, required this.child});
  final Controller controller;
  final AppState state;
  final Widget child;

  static final answer = [
    const SingleActivator(LogicalKeyboardKey.enter, control: true),
    const SingleActivator(LogicalKeyboardKey.enter, meta: true),
  ];
  static final end = [
    const SingleActivator(LogicalKeyboardKey.backspace, control: true),
    const SingleActivator(LogicalKeyboardKey.backspace, meta: true),
  ];
  static final mute = [
    const SingleActivator(LogicalKeyboardKey.keyM, control: true),
    const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
  ];

  @override
  Widget build(BuildContext context) {
    final live = state.live;
    final ringing = live.where((c) => c.ringingHere).firstOrNull;
    final up = live.where((c) => c.state.answered).firstOrNull;
    void run(String command, int call) => controller.run({'command': command, 'call': call});
    return CallbackShortcuts(
      bindings: {
        for (final k in answer) k: () => ringing == null ? null : run('answer', ringing.id),
        for (final k in end) k: () => switch ((ringing, up ?? live.firstOrNull)) {
          (final r?, _) => run('decline', r.id),
          (null, final c?) => run('hangup', c.id),
          _ => null,
        },
        for (final k in mute) k: () => up == null ? null : run(up.muted ? 'unmute' : 'mute', up.id),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
