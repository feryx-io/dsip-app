import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The identity's backup as a file (A6b): saved where the person chooses from the backup's settings, and opened on the
/// first run to restore from. The file is the backup's text, the same text "Copy with names" copies: the recovery code,
/// and the names and identities followed sealed under its passphrase. Nothing else reads or keeps it.

/// The largest backup file read: a real one is a few kilobytes, so anything larger is not one.
const backupFileMax = 64 * 1024;

/// The name a backup file is offered under, for the day [now].
String backupFileName(DateTime now) =>
    'dsip-backup-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.txt';

/// Save [text] as a file, offered as [name], where the person chooses; whether it was saved (false when they go back).
/// Tests set it.
Future<bool> Function(String name, String text) saveBackupFile = (name, text) async =>
    await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(text)), mimeType: 'text/plain') !=
    null;

/// The text of a file the person chooses; null when they go back. Throws a [FormatException] when it is too large to be
/// a backup, or not text. Tests set it.
Future<String?> Function() openBackupFile = () async {
  final file = await FilePicker.pickFile();
  if (file == null) return null;
  final length = file.lengthSync() ?? await file.length();
  if (length != null && length > backupFileMax) throw const FormatException('too large to be a backup');
  return backupText(await file.readAsBytes());
};

/// [bytes] as a backup file's text. Throws a [FormatException] when they are too many to be a backup, or not UTF-8.
String backupText(List<int> bytes) {
  if (bytes.length > backupFileMax) throw const FormatException('too large to be a backup');
  return utf8.decode(bytes);
}
