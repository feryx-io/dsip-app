import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';

/// The settings: the sound devices calls use (chosen at once, kept for the next start), and where the app connects
/// (its relay, mailbox, hints node and STUN server: saved, then the app starts again with them).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller, required this.state});
  final Controller controller;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final heading = Theme.of(context).textTheme.titleMedium;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(s.settingsSound, style: heading),
        const SizedBox(height: 8),
        SoundSettings(controller: controller, audio: state.audio),
        const Divider(height: 32),
        Text(s.settingsConnection, style: heading),
        const SizedBox(height: 8),
        ConnectionSettings(controller: controller),
      ],
    );
  }
}

/// The microphone and speaker: the system's default of each, or one the system offers.
class SoundSettings extends StatelessWidget {
  const SoundSettings({super.key, required this.controller, required this.audio});
  final Controller controller;
  final AudioState audio;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    if (audio.host != 'system') {
      return Text(audio.host == 'tone' ? s.settingsSoundTone : s.settingsSoundNone);
    }
    Widget pick(String kind, String label, String? chosen) {
      final devices = audio.devices.where((d) => d.kind == kind).toList();
      // a device chosen and gone shows as the default, which is what the app uses then
      final value = devices.any((d) => d.id == chosen) ? chosen : null;
      return DropdownMenu<String?>(
        key: Key('audio-$kind'),
        label: Text(label),
        width: 420,
        initialSelection: value,
        dropdownMenuEntries: [
          DropdownMenuEntry(value: null, label: s.settingsSoundDefault),
          for (final d in devices)
            DropdownMenuEntry(value: d.id, label: d.isDefault ? s.settingsSoundSystemDefault(d.name) : d.name),
        ],
        onSelected: (id) => controller.chooseAudio(
          input: kind == 'input' ? id : audio.input,
          output: kind == 'output' ? id : audio.output,
        ),
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // keyed by the choice, so a change from elsewhere (the CLI) shows
        KeyedSubtree(key: ValueKey('in-${audio.input}'), child: pick('input', s.settingsMicrophone, audio.input)),
        KeyedSubtree(key: ValueKey('out-${audio.output}'), child: pick('output', s.settingsSpeaker, audio.output)),
        IconButton(
          tooltip: s.settingsSoundRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () => controller.run({'command': 'audio_devices'}),
        ),
      ],
    );
  }
}

/// The relay, mailbox, hints node and STUN server, from the settings saved; saving them starts the app again.
class ConnectionSettings extends StatefulWidget {
  const ConnectionSettings({super.key, required this.controller});
  final Controller controller;

  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _saved = widget.controller.settings ?? {};
  late final _relay = TextEditingController(text: _saved['relay'] as String? ?? '');
  late final _mailbox = TextEditingController(text: (_saved['mailbox'] as Map?)?['uri'] as String? ?? '');
  late final _mailboxDid = TextEditingController(text: (_saved['mailbox'] as Map?)?['did'] as String? ?? '');
  late final _hints = TextEditingController(text: _first('hints_nodes'));
  late final _stun = TextEditingController(text: _first('stun'));
  bool _busy = false;

  String _first(String key) => ((_saved[key] as List?) ?? const []).cast<String>().firstOrNull ?? '';

  @override
  void dispose() {
    for (final c in [_relay, _mailbox, _mailboxDid, _hints, _stun]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// The settings saved, with what this form edits replaced: the rest (identity, audio, ca, …) kept.
  Map<String, dynamic> _edited() {
    final s = {..._saved}..removeWhere((k, _) => const {'relay', 'mailbox', 'hints_nodes', 'stun'}.contains(k));
    final mailbox = _text(_mailbox);
    final hints = _text(_hints);
    final stun = _text(_stun);
    // a second hints node or STUN server (the CLI can set several) is kept behind the one shown
    List<String> rest(String key) => ((_saved[key] as List?) ?? const []).cast<String>().skip(1).toList();
    return {
      ...s,
      'relay': _text(_relay)!,
      if (mailbox != null) 'mailbox': {'uri': mailbox, 'did': _text(_mailboxDid)!},
      if (hints != null) 'hints_nodes': [hints, ...rest('hints_nodes')],
      if (stun != null) 'stun': [stun, ...rest('stun')],
    };
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = Strings.of(context);
    final busy = widget.controller.state?.calls.any((c) => !c.state.ended) ?? false;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.settingsRestartTitle),
        content: Text(busy ? s.settingsRestartCalls : s.settingsRestartBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.settingsRestart)),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _busy = true);
    await widget.controller.restart(_edited());
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    Widget field(String key, TextEditingController c, String label, {String? hint, String? Function(String?)? check}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            key: Key('settings-$key'),
            controller: c,
            decoration: InputDecoration(labelText: label, hintText: hint),
            validator: check,
          ),
        );
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.settingsIdentityFolder),
              subtitle: SelectableText(_saved['identity'] as String? ?? ''),
            ),
            field(
              'relay',
              _relay,
              s.firstRunRelay,
              hint: s.firstRunRelayHint,
              check: (v) => (v ?? '').trim().startsWith('wss://') ? null : s.firstRunRelayNeeded,
            ),
            field('mailbox', _mailbox, s.firstRunMailbox, hint: s.firstRunMailboxHint),
            field(
              'mailbox-did',
              _mailboxDid,
              s.firstRunMailboxDid,
              check: (v) => _text(_mailbox) != null && (v ?? '').trim().isEmpty ? s.firstRunMailboxDidNeeded : null,
            ),
            field('hints', _hints, s.firstRunHints, hint: s.firstRunHintsHint),
            field('stun', _stun, s.settingsStun, hint: s.settingsStunHint),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('settings-save'),
                onPressed: _busy ? null : _save,
                child: Text(s.settingsSave),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
