import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';

/// Calls: place one to an identity, answer or decline one ringing here, hang up, mute; the ones that ended below.
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

  Future<void> _call() async {
    final to = _to.text.trim();
    if (to.isEmpty) return;
    final r = await widget.controller.run({'command': 'call', 'to': to});
    if (r['response'] == 'call') _to.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final live = widget.state.live;
    final ended = widget.state.calls.where((c) => c.state.ended).toList().reversed.toList();
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
          ],
        ),
        const SizedBox(height: 16),
        if (live.isEmpty && ended.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(s.callsNone)),
        for (final c in live) _LiveCall(call: c, controller: widget.controller),
        if (ended.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(s.callsRecent, style: Theme.of(context).textTheme.titleMedium),
          for (final c in ended)
            ListTile(
              leading: Icon(c.direction == Direction.incoming ? Icons.call_received : Icons.call_made),
              title: Text(c.peerName ?? c.peer, overflow: TextOverflow.ellipsis),
              subtitle: Text(s.callEnded(c.state.reason ?? '')),
            ),
        ],
      ],
    );
  }
}

class _LiveCall extends StatelessWidget {
  const _LiveCall({required this.call, required this.controller});
  final CallView call;
  final Controller controller;

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
    return Card(
      key: Key('call-${call.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(call.peerName ?? call.peer, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
            if (call.peerName != null) Text(call.peer, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(_status(s)),
            if (call.state.answered && !call.media) Text(s.callNoSound, style: Theme.of(context).textTheme.bodySmall),
            if (call.via != null) Text(s.callVia(call.via!), style: Theme.of(context).textTheme.bodySmall),
            if (call.error != null) Text(call.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: call.ringingHere
                  ? [
                      FilledButton.icon(onPressed: () => act('answer'), icon: const Icon(Icons.call), label: Text(s.callAnswer)),
                      OutlinedButton.icon(onPressed: () => act('decline'), icon: const Icon(Icons.call_end), label: Text(s.callDecline)),
                    ]
                  : [
                      FilledButton.icon(
                        onPressed: () => act('hangup'),
                        icon: const Icon(Icons.call_end),
                        label: Text(s.callHangUp),
                        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                      ),
                      if (call.state.answered)
                        OutlinedButton.icon(
                          onPressed: () => act(call.muted ? 'unmute' : 'mute'),
                          icon: Icon(call.muted ? Icons.mic : Icons.mic_off),
                          label: Text(call.muted ? s.callUnmute : s.callMute),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
