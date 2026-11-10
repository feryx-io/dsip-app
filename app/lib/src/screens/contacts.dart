import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import 'confirm.dart';
import 'form_dialog.dart';
import 'name_dialog.dart';
import 'presence.dart';

/// Contacts: the identities the user gave names to (`set_name`), the app's own address book, kept on this device only.
/// Whoever accepts the user's introduction, and whoever the user accepts, is added. From here, call or message one,
/// rename it, copy its identity, or delete it.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key, required this.controller, required this.state});
  final Controller controller;
  final AppState state;

  Future<void> _add(BuildContext context) async {
    final s = Strings.of(context);
    final v = await showDialog<List<String>>(
      context: context,
      builder: (_) => FormDialog(title: s.contactAddTitle, fields: [s.introduceTo, s.nameField], action: s.nameSave),
    );
    if (v == null) return;
    await controller.run({'command': 'set_name', 'identity': v[0], 'name': v[1]});
  }

  Future<void> _message(BuildContext context, String did, String name) async {
    final s = Strings.of(context);
    final v = await showDialog<List<String>>(
      context: context,
      builder: (_) => FormDialog(title: s.contactMessageTitle(name), fields: [s.messageHint], action: s.send, lines: 3),
    );
    if (v == null) return;
    final r = await controller.run({'command': 'message', 'to': did, 'text': v[0]});
    if (r['response'] == 'conversation') controller.showConversation(r['conversation'] as String);
  }

  Future<void> _call(String did) async {
    final r = await controller.run({'command': 'call', 'to': did});
    if (r['response'] == 'call') controller.showTab(Tabs.calls);
  }

  Future<void> _delete(BuildContext context, String did, String name) async {
    final s = Strings.of(context);
    if (!await confirm(context, s.contactDeleteConfirm(name), s.deleteAction)) return;
    await controller.run({'command': 'set_name', 'identity': did});
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final contacts = state.names.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final presence = {for (final p in state.presence.following) p.identity: p.state};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            key: const Key('contact-add'),
            onPressed: () => _add(context),
            icon: const Icon(Icons.person_add),
            label: Text(s.contactAdd),
          ),
        ),
        const SizedBox(height: 8),
        if (contacts.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(s.contactsNone)),
        for (final MapEntry(key: did, value: name) in contacts)
          ListTile(
            key: Key('contact-$did'),
            contentPadding: EdgeInsets.zero,
            leading: presence.containsKey(did)
                ? PresenceDot(presence[did])
                : const Icon(Icons.person_outline),
            title: Text(name, overflow: TextOverflow.ellipsis),
            subtitle: Text(did, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Wrap(
              children: [
                IconButton(
                  key: Key('contact-call-$did'),
                  tooltip: s.contactCall,
                  icon: const Icon(Icons.call),
                  onPressed: () => _call(did),
                ),
                if (state.messaging.mailbox != null)
                  IconButton(
                    key: Key('contact-message-$did'),
                    tooltip: s.contactMessage,
                    icon: const Icon(Icons.chat_outlined),
                    onPressed: () => _message(context, did, name),
                  ),
                PopupMenuButton<String>(
                  key: Key('contact-menu-$did'),
                  onSelected: (what) => switch (what) {
                    'rename' => editName(context, controller, state, did),
                    'copy' => _copy(context, did),
                    _ => _delete(context, did, name),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'rename', child: Text(s.contactRename)),
                    PopupMenuItem(value: 'copy', child: Text(s.meCopy)),
                    PopupMenuItem(value: 'delete', child: Text(s.deleteAction)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String did) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: did));
    messenger.showSnackBar(SnackBar(content: Text(s.meCopied)));
  }
}
