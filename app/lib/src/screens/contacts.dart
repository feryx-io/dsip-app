import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import 'address.dart';
import 'avatar.dart';
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

  Future<void> _call(String did, {bool video = false}) async {
    final r = await placeCall(controller, did, video: video);
    if (r['response'] == 'call') controller.showTab(Tabs.calls);
  }

  Future<void> _delete(BuildContext context, String did, String name) async {
    final s = Strings.of(context);
    if (!await confirm(context, s.contactDeleteConfirm(name), s.deleteAction)) return;
    await controller.run({'command': 'set_name', 'identity': did});
    await controller.setPicture(did, null);
  }

  Future<void> _picture(String did) async {
    final bytes = await pickPicture();
    if (bytes != null) await controller.setPicture(did, bytes);
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
            // their picture or initials; their presence, when followed, on its corner
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                Avatar(controller: controller, did: did, name: name, cardPicture: state.cards[did]?.picture),
                if (presence.containsKey(did))
                  PositionedDirectional(
                    end: -2,
                    bottom: -2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.surface),
                      child: PresenceDot(presence[did]),
                    ),
                  ),
              ],
            ),
            title: Text(name, overflow: TextOverflow.ellipsis),
            // selectable, like the user's own on Me: to copy a part, or all of it with the menu's entry
            subtitle: state.cards[did] == null
                ? SelectableText(did, key: Key('contact-address-$did'), maxLines: 2)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(did, key: Key('contact-address-$did'), maxLines: 2),
                      // what they sent of themselves is their claim (core §19.4): said so, beside the identity
                      Text(
                        cardClaim(s, state.cards[did]!),
                        key: Key('contact-card-$did'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
            trailing: Wrap(
              children: [
                IconButton(
                  key: Key('contact-call-$did'),
                  tooltip: s.contactCall,
                  icon: const Icon(Icons.call),
                  onPressed: () => _call(did),
                ),
                // audio or video; on a phone's width the video call is in the menu
                if (state.video && roomForVideoButton(context))
                  IconButton(
                    key: Key('contact-video-$did'),
                    tooltip: s.callVideoButton,
                    icon: const Icon(Icons.videocam),
                    onPressed: () => _call(did, video: true),
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
                    'copy' => copyAddress(context, did),
                    'video' => _call(did, video: true),
                    'picture' => _picture(did),
                    'no-picture' => controller.setPicture(did, null),
                    _ => _delete(context, did, name),
                  },
                  itemBuilder: (context) => [
                    if (state.video && !roomForVideoButton(context))
                      PopupMenuItem(key: Key('contact-video-$did'), value: 'video', child: Text(s.callVideoButton)),
                    PopupMenuItem(value: 'rename', child: Text(s.contactRename)),
                    PopupMenuItem(key: Key('contact-picture-$did'), value: 'picture', child: Text(s.contactPicture)),
                    if (controller.pictures.has(did))
                      PopupMenuItem(key: Key('contact-no-picture-$did'), value: 'no-picture', child: Text(s.contactPictureRemove)),
                    PopupMenuItem(key: Key('contact-copy-$did'), value: 'copy', child: Text(s.copyAddress)),
                    PopupMenuItem(value: 'delete', child: Text(s.deleteAction)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
