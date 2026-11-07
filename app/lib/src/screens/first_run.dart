import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../controller.dart';
import '../settings.dart';

/// How the first run finds its identity.
enum Origin { make, folder, restore }

/// The first run: make an identity, restore one from its recovery code (A6b), or name a folder holding one; and say
/// where its relay is, and its mailbox and a hints node if it has them. Joining as another device of an identity on
/// another machine comes later (A6c).
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
  final _code = TextEditingController();
  final _passphrase = TextEditingController();
  Origin _origin = Origin.make;
  bool _busy = false;
  String? _failed;

  @override
  void dispose() {
    for (final c in [_name, _folder, _relay, _mailbox, _mailboxDid, _hints, _code, _passphrase]) {
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
      identity: _origin == Origin.folder ? _text(_folder)! : widget.controller.store.defaultIdentity,
      relay: _text(_relay)!,
      mailboxUri: _text(_mailbox),
      mailboxDid: _text(_mailboxDid),
      hintsNode: _text(_hints),
    );
    try {
      await widget.controller.setUp(
        settings: settings,
        displayName: _origin == Origin.folder ? null : _text(_name),
        restore: _origin == Origin.restore ? (_code.text.trim(), _passphrase.text) : null,
      );
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
                  SegmentedButton<Origin>(
                    segments: [
                      ButtonSegment(value: Origin.make, label: Text(s.firstRunNew)),
                      ButtonSegment(value: Origin.restore, label: Text(s.firstRunRestore)),
                      ButtonSegment(value: Origin.folder, label: Text(s.firstRunExisting)),
                    ],
                    selected: {_origin},
                    // the chosen one is shown by its fill; a check mark beside the label only crowds it on a phone
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _origin = v.first),
                  ),
                  const SizedBox(height: 16),
                  if (_origin == Origin.restore) ...[
                    TextFormField(
                      key: const Key('code'),
                      controller: _code,
                      minLines: 2,
                      maxLines: 6,
                      decoration: InputDecoration(labelText: s.firstRunCode, helperText: s.firstRunCodeHint),
                      validator: (v) => (v ?? '').trim().isEmpty ? s.firstRunCodeNeeded : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('passphrase'),
                      controller: _passphrase,
                      obscureText: true,
                      decoration: InputDecoration(labelText: s.backupPassphrase),
                      validator: (v) => (v ?? '').isEmpty ? s.backupPassphraseNeeded : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_origin == Origin.folder)
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
