import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import 'client/models.dart';
import 'controller.dart';
import 'screens/calls.dart';
import 'screens/first_run.dart';
import 'screens/me.dart';

/// The app: the first run until there are settings, then the home screen over the running app's state.
class DsipApp extends StatelessWidget {
  const DsipApp({super.key, required this.controller});
  final Controller controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => Strings.of(context).appName,
    localizationsDelegates: const [...Strings.localizationsDelegates, GlobalMaterialLocalizations.delegate],
    supportedLocales: Strings.supportedLocales,
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final error = widget.controller.takeError();
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.commandFailed(error)))),
      );
    }
    final state = widget.state;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(icon: const Icon(Icons.call), label: Text(s.navCalls)),
              NavigationRailDestination(icon: const Icon(Icons.person), label: Text(s.navMe)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_tab) {
              0 => CallsScreen(controller: widget.controller, state: state),
              _ => MeScreen(state: state),
            },
          ),
        ],
      ),
    );
  }
}
