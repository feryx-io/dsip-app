import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';

/// Who this app is: the identity others call, this device, its relay and mailbox.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final m = state.messaging;
    Widget row(String label, String value, {bool copy = false}) => ListTile(
      title: Text(label),
      subtitle: SelectableText(value),
      trailing: copy
          ? IconButton(
              tooltip: s.meCopy,
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.meCopied)));
              },
            )
          : null,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(state.me.displayName, style: Theme.of(context).textTheme.headlineSmall),
        row(s.meIdentity, state.me.identity, copy: true),
        row(s.meDevice, state.me.device),
        row(s.meRelay, state.relay),
        row(
          s.meMailbox,
          m.mailbox == null ? s.meMailboxNone : '${m.mailbox} · ${m.connected ? s.meMailboxConnected : s.meMailboxOffline}',
        ),
      ],
    );
  }
}
