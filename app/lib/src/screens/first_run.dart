import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../controller.dart';
import '../settings.dart';

/// The first run: make an identity (or name a folder holding one), and say where its relay is, and its mailbox and a
/// hints node if it has them. Joining as another device of an identity on another machine comes later.
class FirstRun extends StatefulWidget {
  const FirstRun({super.key, required this.controller});
  final Controller controller;

  @override
  State<FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends State<FirstRun> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _folder = TextEditingController();
  final _relay = TextEditingController();
  final _mailbox = TextEditingController();
  final _mailboxDid = TextEditingController();
  final _hints = TextEditingController();
  bool _existing = false;
  bool _busy = false;
  String? _failed;

  @override
  void dispose() {
    for (final c in [_name, _folder, _relay, _mailbox, _mailboxDid, _hints]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    final settings = settingsFor(
      identity: _existing ? _text(_folder)! : widget.controller.store.defaultIdentity,
      relay: _text(_relay)!,
      mailboxUri: _text(_mailbox),
      mailboxDid: _text(_mailboxDid),
      hintsNode: _text(_hints),
    );
    try {
      await widget.controller.setUp(settings: settings, displayName: _existing ? null : _text(_name));
    } catch (e) {
      if (mounted) setState(() => _failed = Strings.of(context).firstRunFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.firstRunTitle, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(s.firstRunIntro),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(s.firstRunNew)),
                      ButtonSegment(value: true, label: Text(s.firstRunExisting)),
                    ],
                    selected: {_existing},
                    onSelectionChanged: (v) => setState(() => _existing = v.first),
                  ),
                  const SizedBox(height: 16),
                  if (_existing)
                    TextFormField(
                      key: const Key('folder'),
                      controller: _folder,
                      decoration: InputDecoration(labelText: s.firstRunFolder, helperText: s.firstRunFolderHint),
                      validator: (v) => (v ?? '').trim().isEmpty ? s.firstRunFolderNeeded : null,
                    )
                  else
                    TextFormField(
                      key: const Key('name'),
                      controller: _name,
                      decoration: InputDecoration(labelText: s.firstRunName, helperText: s.firstRunNameHint),
                      validator: (v) => (v ?? '').trim().isEmpty ? s.firstRunNameNeeded : null,
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('relay'),
                    controller: _relay,
                    decoration: InputDecoration(labelText: s.firstRunRelay, hintText: s.firstRunRelayHint),
                    validator: (v) => (v ?? '').trim().startsWith('wss://') ? null : s.firstRunRelayNeeded,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('mailbox'),
                    controller: _mailbox,
                    decoration: InputDecoration(labelText: s.firstRunMailbox, hintText: s.firstRunMailboxHint),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('mailbox-did'),
                    controller: _mailboxDid,
                    decoration: InputDecoration(labelText: s.firstRunMailboxDid),
                    validator: (v) => _text(_mailbox) != null && (v ?? '').trim().isEmpty ? s.firstRunMailboxDidNeeded : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('hints'),
                    controller: _hints,
                    decoration: InputDecoration(labelText: s.firstRunHints, hintText: s.firstRunHintsHint),
                  ),
                  const SizedBox(height: 24),
                  if (_failed != null) ...[
                    Text(_failed!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(onPressed: _busy ? null : _start, child: Text(s.firstRunStart)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
