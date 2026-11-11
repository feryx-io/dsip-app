import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';

/// Voice messages and voicemail: a recording's length as `m:ss`.
String clock(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A voice message or a voicemail in a conversation: played here, from its file once fetched.
class VoiceNote extends StatelessWidget {
  const VoiceNote({
    super.key,
    required this.message,
    required this.playing,
    required this.controller,
    required this.color,
  });
  final MessageView message;

  /// Whether it is the one playing.
  final bool playing;
  final Controller controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final path = message.path;
    final label = message.voicemail ? s.voicemail : s.voiceMessage;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('play-${message.id}'),
          tooltip: playing ? s.voiceStop : s.voicePlay,
          color: color,
          icon: Icon(playing ? Icons.stop : (message.voicemail ? Icons.voicemail : Icons.play_arrow)),
          onPressed: path == null
              ? null
              : () => controller.run(playing ? {'command': 'stop_playing'} : {'command': 'play', 'path': path}),
        ),
        Flexible(
          child: Text(
            [label, if (message.durationMs != null) clock(message.durationMs!), if (path == null) s.attachmentFetching]
                .join(' · '),
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

/// The recording under way, or stopped at its limit: how long it is, and to send it or drop it.
class RecorderBar extends StatefulWidget {
  const RecorderBar({super.key, required this.recording, required this.onSend, required this.onDrop});
  final Recording recording;
  final VoidCallback onSend;
  final VoidCallback onDrop;

  @override
  State<RecorderBar> createState() => _RecorderBarState();
}

class _RecorderBarState extends State<RecorderBar> {
  late final Timer _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final r = widget.recording;
    final since = DateTime.now().millisecondsSinceEpoch - r.startedAt * 1000;
    final elapsed = r.durationMs ?? since.clamp(0, r.maxMs ?? 1 << 40);
    final time = [clock(elapsed), if (r.maxMs != null) clock(r.maxMs!)].join(' / ');
    return Row(
      key: const Key('recorder'),
      children: [
        IconButton(
          key: const Key('record-drop'),
          tooltip: s.voiceDrop,
          icon: const Icon(Icons.delete_outline),
          onPressed: widget.onDrop,
        ),
        Icon(r.running ? Icons.fiber_manual_record : Icons.mic_none, color: r.running ? Colors.red : null, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(r.running ? s.voiceRecordingTime(time) : s.voiceRecorded(time))),
        IconButton(
          key: const Key('record-send'),
          tooltip: s.send,
          icon: const Icon(Icons.send),
          onPressed: widget.onSend,
        ),
      ],
    );
  }
}

/// After a call to [offer]'s callee went unanswered: leave a voicemail (M§13.2), recorded here up to their limit.
class VoicemailDialog extends StatefulWidget {
  const VoicemailDialog({super.key, required this.controller, required this.offer});
  final Controller controller;
  final VoicemailOffer offer;

  @override
  State<VoicemailDialog> createState() => _VoicemailDialogState();
}

class _VoicemailDialogState extends State<VoicemailDialog> {
  bool _started = false;
  bool _sending = false;
  Controller get c => widget.controller;

  @override
  void dispose() {
    // closed without sending: nothing is left behind
    if (_started && !_sending) c.run({'command': 'cancel_recording'});
    c.recordingFor = null;
    super.dispose();
  }

  Future<void> _record() async {
    c.recordingFor = VoicemailOffer.target;
    final r = await c.run({'command': 'record', 'max_s': widget.offer.maxS});
    if (mounted && r['response'] == 'ok') setState(() => _started = true);
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await c.sendRecording(widget.offer.peer, purpose: 'voicemail', session: widget.offer.session);
    if (!mounted) return;
    Navigator.pop(context);
    if (ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).voicemailSent)));
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final o = widget.offer;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final recording = c.state?.voice.recording;
        return AlertDialog(
          key: const Key('voicemail-offer'),
          title: Text(s.voicemailOfferTitle(c.state?.nameOf(o.peer) ?? shortDid(o.peer))),
          content: _started && recording != null
              ? RecorderBar(
                  recording: recording,
                  onSend: _sending ? () {} : _send,
                  onDrop: () => Navigator.pop(context),
                )
              : Text(s.voicemailOfferBody(clock((o.maxS ?? 180) * 1000))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
            if (!_started)
              FilledButton.icon(
                key: const Key('voicemail-record'),
                onPressed: _record,
                icon: const Icon(Icons.mic),
                label: Text(s.voicemailRecord),
              ),
          ],
        );
      },
    );
  }
}
