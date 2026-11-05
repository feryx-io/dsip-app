import 'dart:async';

import '../client/models.dart';
import 'platform.dart';

/// The app's calls and the system's call screen kept in step (CallKit on iOS, Telecom on Android; app plan A5b, as
/// Anvil's U4b): a call ringing in rings there too (the lock screen as well), a call placed shows as dialling, then
/// answered and over as `dsip-app` has it; what the user does there (answer, decline or hang up, mute) becomes the
/// same command a button in the app sends.
class SystemCalls {
  SystemCalls(this.mobile, {required this.run, required this.calls}) {
    _events = mobile.callEvents.listen(_act);
  }

  final MobilePlatform mobile;

  /// Do a `dsip-app` command (the controller's [Controller.run]).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> command) run;

  /// The calls as the app has them now.
  final List<CallView> Function() calls;

  late final StreamSubscription<SystemCallEvent> _events;

  /// The calls the system has been told of, and whether it was told they were answered.
  final _told = <int, bool>{};

  /// Tell the system what changed in [now] (the state's calls; empty when the app stops).
  void sync(List<CallView> now) {
    final live = {for (final c in now.where((c) => !c.state.ended)) c.id: c};
    for (final call in live.values) {
      final answered = _told[call.id];
      if (answered == null) {
        final system = SystemCall(id: call.id, name: call.peerName ?? shortDid(call.peer), address: call.peer);
        _told[call.id] = call.state.answered;
        if (call.ringingHere) {
          unawaited(mobile.reportIncoming(system));
        } else {
          unawaited(mobile.reportOutgoing(system));
          if (call.state.answered) unawaited(mobile.reportConnected(call.id));
        }
      } else if (call.state.answered && !answered) {
        _told[call.id] = true;
        unawaited(mobile.reportConnected(call.id));
      }
    }
    for (final id in _told.keys.where((id) => !live.containsKey(id)).toList()) {
      _told.remove(id);
      unawaited(mobile.reportEnded(id));
    }
  }

  Future<void> _act(SystemCallEvent event) async {
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

  void dispose() => unawaited(_events.cancel());
}
