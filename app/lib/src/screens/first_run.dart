import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../controller.dart';
import '../settings.dart';
import 'backup_file.dart';
import 'scan.dart';

/// The server the first run offers: where a new user's relay and mailbox are found (its `/.well-known/dsip`).
const defaultServer = 'feryx.io';

/// How the first run finds its identity.
enum Origin { make, folder, restore, join }

/// The first run: make an identity, restore one from its recovery code (A6b), join one as another device (A6c), or
/// name a folder holding one; and say where its servers are: a domain listing them ([defaultServer]), or by hand its
/// relay, and its mailbox and a hints node if it has them.
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
  final _server = TextEditingController(text: defaultServer);
  final _code = TextEditingController();
  final _passphrase = TextEditingController();
  final _welcome = TextEditingController();
  Origin _origin = Origin.make;

  /// The relay and mailbox typed in, not found at [_server].
  bool _byHand = false;

  /// The join code and check code, once this device has started joining (A6).
  (String, String)? _join;

  /// The join code's QR form, with where this device listens for its welcome code (the handoff); null when it does not.
  String? _joinQr;

  /// The identity a welcome code came from over the local network: its name and DID.
  (String, String)? _received;
  bool _listening = false;
  bool _busy = false;
  String? _failed;

  @override
  void dispose() {
    _stopListening();
    for (final c in [_name, _folder, _relay, _mailbox, _mailboxDid, _hints, _server, _code, _passphrase, _welcome]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _startJoin() async {
    try {
      final client = widget.controller.client;
      final dir = widget.controller.store.defaultIdentity;
      final codes = await client.pairingStart(dir);
      if (!mounted) return;
      setState(() => _join = codes);
      // and listen for the welcome code: a phone that scans the QR sends it back by itself
      final qr = await client.pairingListen(dir, codes.$1);
      if (!mounted || qr == null) return;
      setState(() => _joinQr = qr);
      _listening = true;
      while (mounted && _listening) {
        final got = await client.pairingReceive(const Duration(seconds: 1));
        if (got == null || !mounted || !_listening) continue;
        setState(() {
          _welcome.text = got.welcome;
          _received = (got.name, got.identity);
        });
        _stopListening();
      }
    } catch (e) {
      if (mounted) setState(() => _failed = Strings.of(context).firstRunFailed('$e'));
    }
  }

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    widget.controller.client.pairingStop();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    final s = Strings.of(context);
    setState(() {
      _busy = true;
      _failed = null;
    });
    final identity = _origin == Origin.folder ? _text(_folder)! : widget.controller.store.defaultIdentity;
    final Map<String, dynamic> settings;
    if (_byHand) {
      settings = settingsFor(
        identity: identity,
        relay: _text(_relay)!,
        mailboxUri: _text(_mailbox),
        mailboxDid: _text(_mailboxDid),
        hintsNode: _text(_hints),
      );
    } else {
      final server = _text(_server)!;
      try {
        settings = {...await widget.controller.client.discoverServers(server), 'identity': identity};
      } catch (e) {
        if (mounted) {
          setState(() {
            _failed = s.firstRunServersFailed(server, '$e');
            _busy = false;
          });
        }
        return;
      }
    }
    try {
      await widget.controller.setUp(
        settings: settings,
        displayName: _origin == Origin.folder || _origin == Origin.join ? null : _text(_name),
        restore: _origin == Origin.restore ? (_code.text.trim(), _passphrase.text) : null,
        joinWelcome: _origin == Origin.join ? _welcome.text.trim() : null,
      );
    } catch (e) {
      if (mounted) setState(() => _failed = Strings.of(context).firstRunFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFile() async {
    try {
      final text = await openBackupFile();
      if (text != null && mounted) {
        setState(() {
          _code.text = text.trim();
          _failed = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _failed = Strings.of(context).firstRunOpenFailed('$e'));
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
                      ButtonSegment(value: Origin.join, label: Text(s.firstRunJoin)),
                      ButtonSegment(value: Origin.folder, label: Text(s.firstRunExisting)),
                    ],
                    selected: {_origin},
                    // the chosen one is shown by its fill; a check mark beside the label only crowds it on a phone
                    showSelectedIcon: false,
                    onSelectionChanged: (v) {
                      setState(() => _origin = v.first);
                      if (v.first == Origin.join && _join == null) _startJoin();
                    },
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
                    // a backup saved as a file: its text, as if pasted
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('open-file'),
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(s.firstRunOpenFile),
                        onPressed: _busy ? null : _openFile,
                      ),
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
                  if (_origin == Origin.join) ...[
                    Text(s.firstRunJoinIntro),
                    const SizedBox(height: 8),
                    if (_join case (final code, final check)) ...[
                      InputDecorator(
                        decoration: InputDecoration(labelText: s.firstRunJoinCode),
                        child: SelectableText(code, key: const Key('join-code'), style: const TextStyle(fontFamily: 'monospace')),
                      ),
                      const SizedBox(height: 8),
                      Center(child: CodeQr(_joinQr ?? code, key: const Key('join-qr'))),
                      if (_joinQr != null && _received == null) ...[
                        const SizedBox(height: 4),
                        Text(s.firstRunJoinNearby, key: const Key('join-nearby')),
                      ],
                      const SizedBox(height: 4),
                      Text(s.firstRunCheckCode(check), key: const Key('check-code')),
                    ] else
                      const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('welcome'),
                      controller: _welcome,
                      minLines: 2,
                      maxLines: 6,
                      decoration: InputDecoration(labelText: s.firstRunWelcome, helperText: s.firstRunWelcomeHint),
                      validator: (v) => (v ?? '').trim().isEmpty ? s.firstRunWelcomeNeeded : null,
                    ),
                    // from the network: whose it is, before anything joins
                    if (_received case (final name, final identity)) ...[
                      const SizedBox(height: 4),
                      Text(s.firstRunWelcomeReceived(name, identity), key: const Key('welcome-received')),
                    ],
                    ScanButton(prefix: 'DSIPW', into: _welcome),
                  ] else if (_origin == Origin.folder)
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
                  if (!_byHand)
                    TextFormField(
                      key: const Key('server'),
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: s.firstRunServer,
                        helperText: s.firstRunServerHint,
                        helperMaxLines: 3,
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty ? s.firstRunServerNeeded : null,
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('by-hand'),
                      onPressed: _busy ? null : () => setState(() => _byHand = !_byHand),
                      child: Text(_byHand ? s.firstRunByServer : s.firstRunByHand),
                    ),
                  ),
                  if (_byHand) ...[
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
                      validator: (v) =>
                          _text(_mailbox) != null && (v ?? '').trim().isEmpty ? s.firstRunMailboxDidNeeded : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('hints'),
                      controller: _hints,
                      decoration: InputDecoration(labelText: s.firstRunHints, hintText: s.firstRunHintsHint),
                      validator: (v) => hintsCheck(s, v, mailbox: _text(_mailbox)),
                    ),
                  ],
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

/// Whether `v` will do as the hints node: an http(s) address, and present whenever there is a mailbox, since a contact
/// finds a did:key identity's mailbox only through its hint (core §8.3), and with none the messages go nowhere.
String? hintsCheck(Strings s, String? v, {required String? mailbox}) {
  final h = (v ?? '').trim();
  if (h.isEmpty) return mailbox == null ? null : s.firstRunHintsNeeded;
  return h.startsWith('https://') || h.startsWith('http://') ? null : s.firstRunHintsBad;
}
