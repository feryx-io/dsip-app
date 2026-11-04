import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A dialog of text fields, answered with their values (trimmed) once every one is filled; null when cancelled.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.fields,
    this.hints = const [],
    this.action,
    this.lines = 1,
  });
  final String title;
  final List<String> fields;
  final List<String?> hints;
  final String? action;
  final int lines;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  late final _controllers = [for (final _ in widget.fields) TextEditingController()];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final values = [for (final c in _controllers) c.text.trim()];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.fields.length; i++)
              TextField(
                key: Key('field-$i'),
                controller: _controllers[i],
                minLines: i == 0 ? widget.lines : 1,
                maxLines: i == 0 ? widget.lines : 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.fields[i],
                  helperText: i < widget.hints.length ? widget.hints[i] : null,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
          onPressed: values.every((v) => v.isNotEmpty) ? () => Navigator.pop(context, values) : null,
          child: Text(widget.action ?? widget.title),
        ),
      ],
    );
  }
}
