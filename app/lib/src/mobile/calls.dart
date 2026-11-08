import 'dart:async';

import 'package:flutter/foundation.dart';

import '../client/models.dart';
import 'platform.dart';

/// The app's calls and the system's call screen kept in step (CallKit on iOS, Telecom on Android; app plan A5b, as
/// Anvil's U4b): a call ringing in rings there too (the lock screen as well), a call placed shows as dialling, then
/// answered and over as `dsip-app` has it; what the user does there (answer, decline or hang up, mute) becomes the
/// same command a button in the app sends. Also where a call's audio goes, for the call's screen to show and change,
/// and the proximity sensor while a call is at the ear (A5c, as Anvil's U4c). Where the system's call screen follows
/// the Rust core itself ([MobilePlatform.systemFollowsCore]: Android and iOS, A5d), only the routes and the sensor.
class SystemCalls {
  SystemCalls(this.mobile, {required this.run, required this.calls, this.failed}) {
    _events = mobile.callEvents.listen(_act);
    _routeChanges = mobile.audioRouteChanges.listen(_routed);
  }

  final MobilePlatform mobile;

  /// Do a `dsip-app` command (the controller's [Controller.run]).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> command) run;

  /// The calls as the app has them now.
  final List<CallView> Function() calls;

  /// Told why the system would not change the route.
  final void Function(String why)? failed;

  late final StreamSubscription<SystemCallEvent> _events;
  late final StreamSubscription<AudioRoutes> _routeChanges;

  /// Where a call's audio goes and may go; null with no call, or before the system says.
  final routes = ValueNotifier<AudioRoutes?>(null);

  /// Whether the screen goes off at the ear now, as last asked.
  bool? _proximity;

  /// Send the calls' audio this way.
  Future<void> setRoute(AudioRoute route) async {
    try {
      await mobile.setAudioRoute(route);
    } catch (e) {
      failed?.call('$e');
    }
  }

  void _routed(AudioRoutes routes) {
    if (_told.isEmpty) return;
    this.routes.value = routes;
    _proximityFor(calls());
  }

  /// The routes come and go with the calls (Telecom's come with a call): asked again whenever the calls change.
  Future<void> _askRoutes() async {
    final routes = await mobile.audioRoutes();
    if (routes != null) _routed(routes);
  }

  /// The screen goes off at the ear: a call answered or being placed, its audio on the earpiece (the phone's default
  /// when the system has not said). Not for a call only ringing in: the user is looking at it.
  void _proximityFor(List<CallView> now) {
    final atEar =
        now.any((c) => !c.state.ended && (c.state.answered || c.direction == Direction.outgoing)) &&
        (routes.value?.current ?? AudioRoute.earpiece) == AudioRoute.earpiece;
    if (atEar != _proximity) {
      _proximity = atEar;
      unawaited(mobile.setProximity(atEar).catchError((Object _) {}));
    }
  }

  /// The calls the system has been told of, and whether it was told they were answered.
  final _told = <int, bool>{};

  /// Tell the system what changed in [now] (the state's calls; empty when the app stops), naming each call's peer as
  /// [state] does.
  void sync(List<CallView> now, [AppState? state]) {
    final live = {for (final c in now.where((c) => !c.state.ended)) c.id: c};
    final changed = live.length != _told.length || live.values.any((c) => _told[c.id] != c.state.answered);
    for (final call in live.values) {
      final answered = _told[call.id];
      if (answered == null) {
        final name = state?.nameOf(call.peer, offered: call.peerName) ?? call.peerName ?? shortDid(call.peer);
        final system = SystemCall(id: call.id, name: name, address: call.peer);
        _told[call.id] = call.state.answered;
        // where the system follows the core, the core told it already
        if (mobile.systemFollowsCore) continue;
        if (call.ringingHere) {
          unawaited(mobile.reportIncoming(system));
        } else {
          unawaited(mobile.reportOutgoing(system));
          if (call.state.answered) unawaited(mobile.reportConnected(call.id));
        }
      } else if (call.state.answered && !answered) {
        _told[call.id] = true;
        if (!mobile.systemFollowsCore) unawaited(mobile.reportConnected(call.id));
      }
    }
    for (final id in _told.keys.where((id) => !live.containsKey(id)).toList()) {
      _told.remove(id);
      if (!mobile.systemFollowsCore) unawaited(mobile.reportEnded(id));
    }
    if (_told.isEmpty) {
      routes.value = null;
    } else if (changed) {
      unawaited(_askRoutes().catchError((Object _) {}));
    }
    _proximityFor(now);
  }

  Future<void> _act(SystemCallEvent event) async {
    // The core heard it already.
    if (mobile.systemFollowsCore) return;
    final call = calls().where((c) => c.id == event.call && !c.state.ended).firstOrNull;
    if (call == null) return;
    switch (event.action) {
      case SystemCallAction.shown:
        break;
      case SystemCallAction.failed:
        // Do Not Disturb or a blocked caller: the user asked not to be rung. Anything else leaves the app ringing on
        // its own.
        if (event.reason == 'filtered' && call.ringingHere) await run({'command': 'decline', 'call': call.id});
      case SystemCallAction.answer:
        if (call.ringingHere) await run({'command': 'answer', 'call': call.id});
      case SystemCallAction.end:
        await run({'command': call.ringingHere ? 'decline' : 'hangup', 'call': call.id});
      case SystemCallAction.mute:
        final on = event.on ?? true;
        if (call.muted != on) await run({'command': on ? 'mute' : 'unmute', 'call': call.id});
    }
  }

  void dispose() {
    unawaited(_events.cancel());
    unawaited(_routeChanges.cancel());
    routes.dispose();
  }
}
