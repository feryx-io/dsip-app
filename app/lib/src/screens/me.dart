import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../card_picture.dart';
import '../client/models.dart';
import '../controller.dart';
import 'address.dart';
import 'avatar.dart';

/// An image file's bytes as a picture a card can carry, or null when it is no image: off the screen's thread. Tests
/// set it.
Future<Uint8List?> Function(Uint8List) shrinkPicture = shrinkCardPictureInBackground;

/// Who this app is: the identity others call, this device, its relay and mailbox; and its profile card, the name and
/// picture it may send to the people it introduces itself to or accepts (core §19.4), which goes nowhere until the
/// user turns that on.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key, required this.state, required this.controller});
  final AppState state;
  final Controller controller;

  /// Pick an image and make it, shrunk to what a card carries, this identity's picture.
  Future<void> _choosePicture(BuildContext context) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await pickPicture();
    if (bytes == null) return;
    final small = await shrinkPicture(bytes);
    if (small == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.cardPictureUnreadable)));
      return;
    }
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}dsip-card-picture-$pid.jpg');
    await file.writeAsBytes(small);
    await controller.run({'command': 'set_picture', 'path': file.path});
    if (await file.exists()) await file.delete();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final m = state.messaging;
    final p = state.profile;
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
        // first contact goes through the mailbox: without one there is nobody to send a card to
        if (m.mailbox != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(s.cardTitle, style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: _OwnPicture(path: p.picture, name: state.me.displayName),
            title: Text(state.me.displayName),
            subtitle: Text(s.cardIntro),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('card-picture-choose'),
                  onPressed: () => _choosePicture(context),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(s.contactPicture),
                ),
                if (p.picture != null)
                  TextButton(
                    key: const Key('card-picture-remove'),
                    onPressed: () => controller.run({'command': 'set_picture'}),
                    child: Text(s.contactPictureRemove),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            key: const Key('card-with-introductions'),
            title: Text(s.cardWithIntroductions),
            subtitle: Text(s.cardWithIntroductionsHint),
            value: p.withIntroductions,
            onChanged: (on) => controller.run({'command': 'share_profile', 'introductions': on}),
          ),
          SwitchListTile(
            key: const Key('card-with-grants'),
            title: Text(s.cardWithGrants),
            subtitle: Text(s.cardWithGrantsHint),
            value: p.withGrants,
            onChanged: (on) => controller.run({'command': 'share_profile', 'grants': on}),
          ),
        ],
      ],
    );
  }
}

/// This identity's own picture as a circle, or its initials.
class _OwnPicture extends StatelessWidget {
  const _OwnPicture({required this.path, required this.name});
  final String? path;
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget initials = Text(
      initialsOf(name),
      textScaler: TextScaler.noScaling,
      style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600, fontSize: 19),
    );
    return ExcludeSemantics(
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.secondaryContainer),
        child: path == null
            ? initials
            : Image.file(
                File(path!),
                key: const Key('card-picture'),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => initials,
              ),
      ),
    );
  }
}
