import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import 'update.dart';
import 'scan.dart';

/// The settings: the sound devices calls use (chosen at once, kept for the next start), where the app connects (its
/// relay, mailbox, hints node and STUN server: saved, then the app starts again with them), and the identity's backup
/// (A6b).
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
        // A phone's microphone and speaker follow the call's route (the call's screen), not a list here.
        if (controller.mobile == null) ...[
          Text(s.settingsSound, style: heading),
          const SizedBox(height: 8),
          SoundSettings(controller: controller, audio: state.audio),
          const Divider(height: 32),
        ],
        Text(s.settingsConnection, style: heading),
        const SizedBox(height: 8),
        ConnectionSettings(controller: controller),
        const Divider(height: 32),
        Text(s.settingsBackup, style: heading),
        const SizedBox(height: 8),
        BackupSettings(controller: controller),
        const Divider(height: 32),
        Text(s.settingsDevices, style: heading),
        const SizedBox(height: 8),
        DevicesSettings(controller: controller),
        const Divider(height: 32),
        Text(s.settingsWeb, style: heading),
        const SizedBox(height: 8),
        WebSettings(controller: controller),
        const Divider(height: 32),
        Text(s.settingsAbout, style: heading),
        const SizedBox(height: 8),
        AboutSettings(controller: controller),
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

/// The identity's backup (A6b): a recovery code made under a passphrase, shown to write down or copy.
class BackupSettings extends StatelessWidget {
  const BackupSettings({super.key, required this.controller});
  final Controller controller;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.settingsBackupIntro),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('backup'),
          icon: const Icon(Icons.key),
          label: Text(s.settingsBackupMake),
          onPressed: () => showDialog<void>(context: context, builder: (_) => BackupDialog(controller: controller)),
        ),
      ],
    );
  }
}

/// The passphrase twice, then the code.
class BackupDialog extends StatefulWidget {
  const BackupDialog({super.key, required this.controller});
  final Controller controller;

  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  final _form = GlobalKey<FormState>();
  final _passphrase = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _failed;
  String? _code;

  /// The backup file's text: the code, and the names and identities followed, sealed (when there are any).
  String? _file;

  @override
  void dispose() {
    _passphrase.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final dir = widget.controller.settings?['identity'] as String? ?? '';
      final backup = await widget.controller.client.exportIdentity(dir, _passphrase.text);
      if (mounted) {
        setState(() {
          _code = backup.code;
          _file = backup.file;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _failed = Strings.of(context).backupFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final code = _code;
    final withContacts = _file?.contains('DSIPC1-') ?? false;
    if (code != null) {
      return AlertDialog(
        title: Text(s.backupCodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.backupCodeBody),
            const SizedBox(height: 12),
            SelectableText(code, key: const Key('code'), style: const TextStyle(fontFamily: 'monospace')),
            // the names given and the identities followed are in the file's text, sealed, not in the code
            if (withContacts) ...[const SizedBox(height: 12), Text(s.backupContactsBody)],
          ],
        ),
        actions: [
          if (withContacts)
            TextButton(
              key: const Key('copy-file'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _file!));
                if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.backupCopied)));
              },
              child: Text(s.backupCopyFile),
            ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.backupCopied)));
            },
            child: Text(s.backupCopy),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.backupDone)),
        ],
      );
    }
    return AlertDialog(
      title: Text(s.backupTitle),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('passphrase'),
              controller: _passphrase,
              obscureText: true,
              decoration: InputDecoration(labelText: s.backupPassphrase, helperText: s.backupPassphraseHint, helperMaxLines: 3),
              validator: (v) => (v ?? '').characters.length < 10 ? s.backupPassphraseShort : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('again'),
              controller: _again,
              obscureText: true,
              decoration: InputDecoration(labelText: s.backupPassphraseAgain),
              validator: (v) => v != _passphrase.text ? s.backupPassphraseDiffers : null,
            ),
            if (_failed != null) ...[
              const SizedBox(height: 12),
              Text(_failed!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.backupCancel)),
        FilledButton(onPressed: _busy ? null : _make, child: Text(s.backupMake)),
      ],
    );
  }
}

/// The identity on a domain of the person's own (A6d): the document to serve, a check of what the domain serves, and
/// the move once it does.
class WebSettings extends StatelessWidget {
  const WebSettings({super.key, required this.controller});
  final Controller controller;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.settingsWebIntro),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('web'),
          icon: const Icon(Icons.language),
          label: Text(s.settingsWebStart),
          onPressed: () => showDialog<void>(context: context, builder: (_) => WebDialog(controller: controller)),
        ),
      ],
    );
  }
}

/// The DID, then the document and its URL, then the check, then the move.
class WebDialog extends StatefulWidget {
  const WebDialog({super.key, required this.controller});
  final Controller controller;

  @override
  State<WebDialog> createState() => _WebDialogState();
}

class _WebDialogState extends State<WebDialog> {
  final _form = GlobalKey<FormState>();
  final _did = TextEditingController();
  Map<String, dynamic>? _plan;
  List<String>? _differs;
  bool _busy = false;
  String? _failed;

  @override
  void dispose() {
    _did.dispose();
    super.dispose();
  }

  Future<void> _step(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => _failed = Strings.of(context).webFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() async {
    if (!_form.currentState!.validate()) return;
    final settings = widget.controller.settings ?? const {};
    final mailbox = settings['mailbox'] as Map<String, dynamic>?;
    await _step(() async {
      final plan = await widget.controller.client.webPrepare(
        settings['identity'] as String? ?? '',
        _did.text.trim(),
        settings['relay'] as String? ?? '',
        mailboxDid: mailbox?['did'] as String?,
        mailboxUri: mailbox?['uri'] as String?,
      );
      if (mounted) {
        setState(() {
          _plan = plan;
          _differs = null;
        });
      }
    });
  }

  Future<void> _check() => _step(() async {
    final differs = await widget.controller.client.webCheck(_plan!);
    if (mounted) setState(() => _differs = differs);
  });

  Future<void> _move() async {
    final s = Strings.of(context);
    final did = _plan!['did'] as String;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.webMoveConfirmTitle),
        content: Text(s.webMoveConfirm(did)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.backupCancel)),
          FilledButton(key: const Key('web-move-sure'), onPressed: () => Navigator.pop(context, true), child: Text(s.webMove)),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final plan = _plan!;
    Navigator.pop(context);
    await widget.controller.moveToWeb(plan);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final plan = _plan;
    final differs = _differs;
    return AlertDialog(
      title: Text(s.webTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('web-did'),
                controller: _did,
                decoration: InputDecoration(labelText: s.webDid, helperText: s.webDidHint),
                validator: (v) => (v ?? '').trim().startsWith('did:web:') ? null : s.webDidNeeded,
                onChanged: (_) => setState(() {
                  _plan = null;
                  _differs = null;
                }),
              ),
              if (plan != null) ...[
                const SizedBox(height: 12),
                Text(s.webServe(plan['url'] as String)),
                const SizedBox(height: 8),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(plan['document']),
                  key: const Key('web-document'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
              if (differs != null) ...[
                const SizedBox(height: 12),
                Text(differs.isEmpty ? s.webServed : s.webDiffers(differs.join('; ')), key: const Key('web-check')),
              ],
              if (_failed != null) ...[
                const SizedBox(height: 12),
                Text(_failed!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.backupCancel)),
        if (plan != null)
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(plan['document']))),
            child: Text(s.backupCopy),
          ),
        if (plan == null) FilledButton(onPressed: _busy ? null : _prepare, child: Text(s.webPrepare)),
        if (plan != null && differs?.isEmpty != true) FilledButton(onPressed: _busy ? null : _check, child: Text(s.webCheck)),
        if (plan != null && differs?.isEmpty == true) FilledButton(onPressed: _busy ? null : _move, child: Text(s.webMove)),
      ],
    );
  }
}

/// Another device of this identity (A6): the new device's join code in, the welcome code out, and the check code
/// both show.
class DevicesSettings extends StatelessWidget {
  const DevicesSettings({super.key, required this.controller});
  final Controller controller;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.settingsDevicesIntro),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('add-device'),
          icon: const Icon(Icons.devices),
          label: Text(s.settingsAddDevice),
          onPressed: () => showDialog<void>(context: context, builder: (_) => AddDeviceDialog(controller: controller)),
        ),
      ],
    );
  }
}

class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key, required this.controller});
  final Controller controller;

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final _form = GlobalKey<FormState>();
  final _join = TextEditingController();
  (String, String)? _welcome;
  bool _busy = false;
  String? _failed;

  @override
  void dispose() {
    _join.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final dir = widget.controller.settings?['identity'] as String? ?? '';
      final codes = await widget.controller.client.pairingWelcome(dir, _join.text.trim());
      if (mounted) setState(() => _welcome = codes);
    } catch (e) {
      if (mounted) setState(() => _failed = Strings.of(context).webFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final welcome = _welcome;
    return AlertDialog(
      title: Text(s.addDeviceTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (welcome == null)
                TextFormField(
                  key: const Key('join'),
                  controller: _join,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: s.addDeviceJoin),
                  validator: (v) => (v ?? '').trim().isEmpty ? s.addDeviceJoinNeeded : null,
                ),
              if (welcome == null) ScanButton(prefix: 'DSIPJ1-', into: _join, onScanned: () => setState(() {}))
              else ...[
                Text(s.addDeviceWelcome(welcome.$2)),
                const SizedBox(height: 8),
                Center(child: CodeQr(welcome.$1, key: const Key('welcome-qr'), size: 260)),
                const SizedBox(height: 8),
                SelectableText(welcome.$1, key: const Key('welcome-code'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
              if (_failed != null) ...[
                const SizedBox(height: 12),
                Text(_failed!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(welcome == null ? s.backupCancel : s.backupDone)),
        if (welcome != null)
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: welcome.$1)), child: Text(s.backupCopy)),
        if (welcome == null) FilledButton(onPressed: _busy ? null : _make, child: Text(s.addDeviceMake)),
      ],
    );
  }
}
