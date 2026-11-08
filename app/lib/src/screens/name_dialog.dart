import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import 'form_dialog.dart';

/// Ask the user what to call [did], starting from the name they gave it, and keep it on this device (`set_name`); an
/// empty name takes it away.
Future<void> editName(BuildContext context, Controller controller, AppState state, String did) async {
  final s = Strings.of(context);
  final v = await showDialog<List<String>>(
    context: context,
    builder: (_) => FormDialog(
      title: s.nameTitle(shortDid(did)),
      fields: [s.nameField],
      hints: [s.nameHint],
      initial: [state.names[did] ?? ''],
      action: s.nameSave,
      optional: true,
    ),
  );
  if (v == null) return;
  await controller.run({'command': 'set_name', 'identity': did, if (v[0].isNotEmpty) 'name': v[0]});
}
