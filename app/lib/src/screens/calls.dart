import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import '../mobile/calls.dart';
import '../mobile/platform.dart';
import 'confirm.dart';
import 'name_dialog.dart';
import 'reasons.dart';
import 'video_tile.dart';

/// Calls: place one to an identity, answer or decline one ringing here, hang up, mute; the history below, each call in
/// it to call back, name or delete.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key, required this.controller, required this.state});
  final Controller controller;
  final AppState state;

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final _to = TextEditingController();

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  /// Call who is typed in, with video when [video] (asking for the camera first on a phone).
  Future<void> _call({bool video = false}) async {
    final to = _to.text.trim();
    if (to.isEmpty) return;
    if (video) await widget.controller.mobile?.requestCamera();
    final r = await widget.controller.run({'command': 'call', 'to': to, if (video) 'video': true});
    if (r['response'] == 'call') _to.clear();
  }

  Future<void> _clear() async {
    final s = Strings.of(context);
    if (!await confirm(context, s.callsClearConfirm, s.deleteAction)) return;
    await widget.controller.run({'command': 'clear_history'});
  }

  /// When [c] ended, as the locale writes a date and a time.
  String _when(BuildContext context, CallRecord c) {
    final l = MaterialLocalizations.of(context);
    final at = DateTime.fromMillisecondsSinceEpoch(c.endedAt * 1000);
    final time = l.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    return '${l.formatShortDate(at)} $time';
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final live = widget.state.live;
    final ended = widget.state.history.reversed.toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('call-to'),
                controller: _to,
                decoration: InputDecoration(labelText: s.callTo, hintText: s.callToHint),
                onSubmitted: (_) => _call(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: _call, icon: const Icon(Icons.call), label: Text(s.callButton)),
            if (widget.state.video) ...[
              const SizedBox(width: 8),
              // on a phone's width the address keeps its room: the camera alone says what it is
              if (MediaQuery.sizeOf(context).width < 600)
                IconButton.outlined(
                  key: const Key('video-call'),
                  tooltip: s.callVideoButton,
                  onPressed: () => _call(video: true),
                  icon: const Icon(Icons.videocam),
                )
              else
                OutlinedButton.icon(
                  key: const Key('video-call'),
                  onPressed: () => _call(video: true),
                  icon: const Icon(Icons.videocam),
                  label: Text(s.callVideoButton),
                ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (live.isEmpty && ended.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(s.callsNone)),
        for (final c in live) _LiveCall(call: c, controller: widget.controller, state: widget.state),
        if (ended.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(s.callsRecent, style: Theme.of(context).textTheme.titleMedium)),
              TextButton(key: const Key('calls-clear'), onPressed: _clear, child: Text(s.callsClear)),
            ],
          ),
          for (final c in ended)
            ListTile(
              key: Key('history-${c.session}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                c.missed ? Icons.call_missed : (c.direction == Direction.incoming ? Icons.call_received : Icons.call_made),
                color: c.missed ? Theme.of(context).colorScheme.error : null,
                semanticLabel: c.missed ? s.callMissed : null,
              ),
              title: Text(widget.state.nameOf(c.peer, offered: c.peerName), overflow: TextOverflow.ellipsis),
              subtitle: Tooltip(
                message: s.callEndedCode(c.reason),
                child: Text(
                  '${c.missed ? s.callMissed : s.callEnded(endedReason(s, c.reason))} · ${_when(context, c)}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    key: Key('call-back-${c.session}'),
                    tooltip: s.callBack,
                    icon: const Icon(Icons.call),
                    onPressed: () => widget.controller.run({'command': 'call', 'to': c.peer}),
                  ),
                  PopupMenuButton<String>(
                    key: Key('history-menu-${c.session}'),
                    onSelected: (what) => what == 'name'
                        ? editName(context, widget.controller, widget.state, c.peer)
                        : widget.controller.run({'command': 'forget_call', 'session': c.session}),
                    itemBuilder: (_) => [
                      PopupMenuItem(key: Key('name-call-${c.session}'), value: 'name', child: Text(s.nameAction)),
                      PopupMenuItem(value: 'forget', child: Text(s.callForget)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _LiveCall extends StatelessWidget {
  const _LiveCall({required this.call, required this.controller, required this.state});
  final CallView call;
  final Controller controller;
  final AppState state;

  String _status(Strings s) => switch (call.state.name) {
    'calling' => s.callCalling,
    'ringing' => call.direction == Direction.incoming ? s.callRingingHere : s.callRingingThere,
    'answered' => call.state.answeredBy == null || call.state.answeredBy == 'user'
        ? s.callAnswered
        : s.callAnsweredBy(call.state.answeredBy!),
    _ => call.state.name,
  };

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    void act(String command) => controller.run({'command': command, 'call': call.id});
    // the keyboard's way to each (app.dart's CallKeys), said in the button's tooltip on a desktop
    final mod = defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl+';
    final desktop = controller.mobile == null;
    Widget keyed(String keys, Widget button) => desktop ? Tooltip(message: '$mod$keys', child: button) : button;
    final name = state.nameOf(call.peer, offered: call.peerName);
    return Card(
      key: Key('call-${call.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
            if (state.named(call.peer, offered: call.peerName))
              Text(call.peer, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            // a screen reader says a call ringing in, and each change of state, without the user moving there (A7)
            Announced('${_status(s)}: $name', child: Text(_status(s))),
            if (call.state.answered && !call.media) Text(s.callNoSound, style: Theme.of(context).textTheme.bodySmall),
            if (call.via != null) Text(s.callVia(call.via!), style: Theme.of(context).textTheme.bodySmall),
            if (call.error != null) Text(call.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            // where the call's sound stops on this device, when a stage stalls or fails
            if (call.sound case final n? when n.troubled) ...[
              Text(
                s.callSound(n.mic, n.sent, n.heard, n.decoded, n.played, n.ringback),
                key: Key('call-sound-${call.id}'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (n.stalled case final stage?)
                Text(s.callSoundStalled(stage), key: Key('call-stalled-${call.id}'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              for (final e in [?n.micError, ?n.speakerError])
                Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (call.video && call.state.answered) ...[
              const SizedBox(height: 12),
              _VideoArea(key: Key('video-${call.id}'), call: call, controller: controller),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: call.ringingHere
                  ? [
                      keyed('Enter', FilledButton.icon(onPressed: () => act('answer'), icon: const Icon(Icons.call), label: Text(s.callAnswer))),
                      keyed('Backspace', OutlinedButton.icon(onPressed: () => act('decline'), icon: const Icon(Icons.call_end), label: Text(s.callDecline))),
                    ]
                  : [
                      keyed('Backspace', FilledButton.icon(
                        onPressed: () => act('hangup'),
                        icon: const Icon(Icons.call_end),
                        label: Text(s.callHangUp),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                      )),
                      if (call.state.answered)
                        keyed('M', OutlinedButton.icon(
                          onPressed: () => act(call.muted ? 'unmute' : 'mute'),
                          icon: Icon(call.muted ? Icons.mic : Icons.mic_off),
                          label: Text(call.muted ? s.callUnmute : s.callMute),
                        )),
                      if (call.video && call.state.answered)
                        OutlinedButton.icon(
                          key: Key('camera-${call.id}'),
                          onPressed: () => controller.run({'command': 'camera', 'call': call.id, 'on': !call.camera}),
                          icon: Icon(call.camera ? Icons.videocam_off : Icons.videocam),
                          label: Text(call.camera ? s.callCameraOff : s.callCameraOn),
                        ),
                      if (controller.system case final system?) AudioRouteButton(system: system),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A video call's pictures: the far end's, and this side's camera in a corner while it sends; at most 240 high, 4:3,
/// so the call's card stays a card. On a phone the camera is asked for when the call starts showing video, and turned
/// on once allowed (the core starts it with the call, which fails while the system has not said yes).
class _VideoArea extends StatefulWidget {
  const _VideoArea({super.key, required this.call, required this.controller});
  final CallView call;
  final Controller controller;

  @override
  State<_VideoArea> createState() => _VideoAreaState();
}

class _VideoAreaState extends State<_VideoArea> {
  @override
  void initState() {
    super.initState();
    final mobile = widget.controller.mobile;
    if (mobile != null && !widget.call.camera) {
      mobile.requestCamera().then((allowed) {
        if (allowed && mounted) widget.controller.run({'command': 'camera', 'call': widget.call.id, 'on': true});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final far = VideoTile(key: const Key('video-far'), stream: widget.call.id);
    const self = VideoTile(key: Key('video-self'), stream: null, mirror: true);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Positioned.fill(child: far),
                if (widget.call.camera) const Positioned(right: 8, bottom: 8, width: 80, height: 60, child: self),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the call's audio goes, on a phone (app plan A5c, as Anvil's U4c): a speaker switch when the earpiece and the
/// speaker are all there is; with Bluetooth or a headset too, the route in use, opening the list to choose from. Nothing
/// until the system says what there is.
class AudioRouteButton extends StatelessWidget {
  const AudioRouteButton({super.key, required this.system});
  final SystemCalls system;

  static IconData icon(AudioRoute route) => switch (route) {
    AudioRoute.earpiece => Icons.phone_in_talk,
    AudioRoute.speaker => Icons.volume_up,
    AudioRoute.bluetooth => Icons.bluetooth_audio,
    AudioRoute.wired => Icons.headset,
  };

  static String label(Strings s, AudioRoutes routes, AudioRoute route) => switch (route) {
    AudioRoute.earpiece => s.routeEarpiece,
    AudioRoute.speaker => s.routeSpeaker,
    AudioRoute.bluetooth => routes.bluetoothName ?? s.routeBluetooth,
    AudioRoute.wired => s.routeWired,
  };

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return ValueListenableBuilder<AudioRoutes?>(
      valueListenable: system.routes,
      builder: (context, routes, _) {
        if (routes == null || routes.available.length < 2) return const SizedBox.shrink();
        if (routes.justSpeaker) {
          final on = routes.current == AudioRoute.speaker;
          void onPressed() => system.setRoute(on ? AudioRoute.earpiece : AudioRoute.speaker);
          return on
              ? FilledButton.tonalIcon(
                  key: const Key('speaker-route'),
                  onPressed: onPressed,
                  icon: const Icon(Icons.volume_up),
                  label: Text(s.routeSpeaker),
                )
              : OutlinedButton.icon(
                  key: const Key('speaker-route'),
                  onPressed: onPressed,
                  icon: const Icon(Icons.volume_up),
                  label: Text(s.routeSpeaker),
                );
        }
        return OutlinedButton.icon(
          key: const Key('audio-route'),
          icon: Icon(icon(routes.current)),
          label: Text(label(s, routes, routes.current)),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final route in routes.available)
                    ListTile(
                      key: Key('route-${route.name}'),
                      leading: Icon(icon(route)),
                      title: Text(label(s, routes, route)),
                      trailing: route == routes.current ? const Icon(Icons.check) : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        system.setRoute(route);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [child], and [message] said by a screen reader when it first shows and whenever it changes (an announcement, not a
/// live region: the text keeps its own place in the screen's semantics).
class Announced extends StatefulWidget {
  const Announced(this.message, {super.key, required this.child});
  final String message;
  final Widget child;

  @override
  State<Announced> createState() => _AnnouncedState();
}

class _AnnouncedState extends State<Announced> {
  void _say() {
    final view = View.of(context);
    SemanticsService.sendAnnouncement(view, widget.message, Directionality.of(context));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_said) {
      _said = true;
      _say();
    }
  }

  bool _said = false;

  @override
  void didUpdateWidget(Announced old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) _say();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
