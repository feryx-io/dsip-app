import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';

/// Attachments (M§8.2, M§8.4): a file the user picks to send, and an image or file in a conversation, shown, opened
/// with the system's app for it, or saved where the user chooses.

/// A file the user picks to send: its path on this device, which the app reads, and its name. A picked file with no
/// path of its own (an Android content URI) is copied to the app's temporary folder first. Null when they go back.
/// Tests set it.
Future<(String, String)?> Function() pickToSend = () async {
  final file = await FilePicker.pickFile();
  if (file == null) return null;
  final path = file.path;
  if (path != null) return (path, file.name);
  final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}dsip-send');
  await dir.create(recursive: true);
  final copy = File('${dir.path}${Platform.pathSeparator}${file.name.replaceAll(RegExp(r'[\\/]'), '_')}');
  await copy.writeAsBytes(await file.readAsBytes());
  return (copy.path, file.name);
};

/// Open [path] with the system's app for it; whether it did. Tests set it.
Future<bool> Function(String path) openAttachment = (path) => launchUrl(Uri.file(path));

/// Save the file at [path] where the user chooses, offered as [name]; whether it was saved. Tests set it.
Future<bool> Function(String name, String path) saveAttachment = (name, path) async =>
    await FilePicker.saveFile(fileName: name, bytes: await File(path).readAsBytes()) != null;

/// [bytes] for people: `512 B`, `48 KB`, `1.2 MB`.
String sizeText(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).round()} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};

/// An attachment in a message: an image shown once it is here, else a card with its name and size, to open or save.
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.message, required this.color});
  final MessageView message;

  /// The text colour of the bubble it is in.
  final Color color;

  Future<void> _open(BuildContext context, String path) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    bool opened;
    try {
      opened = await openAttachment(path);
    } catch (_) {
      opened = false;
    }
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(s.attachmentNotOpened)));
  }

  Future<void> _save(BuildContext context, String name, String path) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await saveAttachment(name, path)) messenger.showSnackBar(SnackBar(content: Text(s.attachmentSaved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.commandFailed('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final m = message;
    final name = m.name ?? m.kind;
    final path = m.path;
    final style = TextStyle(color: color);
    final image = m.kind == 'image' || (m.contentType?.startsWith('image/') ?? false);
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(image ? Icons.image_outlined : Icons.insert_drive_file_outlined, color: color),
            const SizedBox(width: 8),
            Flexible(child: Text(name, style: style, overflow: TextOverflow.ellipsis, maxLines: 2)),
          ],
        ),
        Text(path == null ? s.attachmentFetching : (m.size == null ? '' : sizeText(m.size!)), style: style.copyWith(fontSize: 12)),
        if (path != null)
          Wrap(
            spacing: 4,
            children: [
              TextButton(key: Key('open-${m.id}'), onPressed: () => _open(context, path), child: Text(s.attachmentOpen)),
              TextButton(key: Key('save-${m.id}'), onPressed: () => _save(context, name, path), child: Text(s.attachmentSave)),
            ],
          ),
      ],
    );
    if (!image || path == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _open(context, path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: Image.file(
                File(path),
                key: Key('image-${m.id}'),
                fit: BoxFit.contain,
                semanticLabel: name,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        card,
      ],
    );
  }
}
