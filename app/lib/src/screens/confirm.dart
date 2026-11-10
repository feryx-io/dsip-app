import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Ask [question] before doing something that cannot be undone; whether the user chose [action].
Future<bool> confirm(BuildContext context, String question, String action) async {
  final s = Strings.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
        FilledButton(key: const Key('confirm'), onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return yes == true;
}
