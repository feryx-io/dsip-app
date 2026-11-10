import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A dialog of text fields, answered with their values (trimmed) once every one is filled (or at once, when [optional]);
/// null when cancelled.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.fields,
    this.hints = const [],
    this.action,
    this.lines = 1,
    this.initial = const [],
    this.optional = false,
    this.optionalFields = const {},
  });
  final String title;
  final List<String> fields;
  final List<String?> hints;
  final String? action;
  final int lines;

  /// What the fields start with.
  final List<String> initial;

  /// Whether a field may be left empty.
  final bool optional;

  /// The fields (by index) that may be left empty when the others may not.
  final Set<int> optionalFields;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  late final _controllers = [
    for (var i = 0; i < widget.fields.length; i++) TextEditingController(text: i < widget.initial.length ? widget.initial[i] : null),
  ];

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
          // the fields as they are when pressed, not as they were drawn
          onPressed: widget.optional || [for (var i = 0; i < values.length; i++) if (!widget.optionalFields.contains(i)) values[i]].every((v) => v.isNotEmpty)
              ? () => Navigator.pop(context, [for (final c in _controllers) c.text.trim()])
              : null,
          child: Text(widget.action ?? widget.title),
        ),
      ],
    );
  }
}
