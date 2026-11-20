import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../controller.dart';

/// Copy [did], someone's identity, to the clipboard and say so: to paste where a call is placed, or to share.
Future<void> copyAddress(BuildContext context, String did) async {
  final s = Strings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: did));
  messenger.showSnackBar(SnackBar(content: Text(s.meCopied)));
}

/// An image file the user picks for a contact's picture: its bytes; null when they go back. Tests set it.
Future<Uint8List?> Function() pickPicture = () async {
  final file = await FilePicker.pickFile(type: FileType.image);
  return file?.readAsBytes();
};

/// Call [to], with video when [video] (asking for the camera first on a phone). The command's response.
Future<Map<String, dynamic>> placeCall(Controller controller, String to, {bool video = false}) async {
  if (video) await controller.mobile?.requestCamera();
  return controller.run({'command': 'call', 'to': to, if (video) 'video': true});
}

/// Whether the window has room for a video button beside the call button in a list's row; a phone's width keeps it
/// in the row's menu.
bool roomForVideoButton(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;
