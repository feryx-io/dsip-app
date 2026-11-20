import 'package:flutter/material.dart';

import '../controller.dart';

/// The letters shown for [name] without a picture: the first of its first word and of its last, in capitals; empty
/// without a name.
String initialsOf(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  String first(String w) => String.fromCharCode(w.runes.first).toUpperCase();
  return words.length == 1 ? first(words.first) : first(words.first) + first(words.last);
}

/// Someone as a small circle: the picture the user gave them, or their initials, or (with no name either) a person.
/// Beside their name, so it says nothing of its own to a screen reader.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.controller, required this.did, this.name, this.radius = 20});
  final Controller controller;
  final String did;

  /// The name the initials are of: the one the user gave, or the one a caller gave.
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = initialsOf(name);
    final Widget fallback = initials.isEmpty
        ? Icon(Icons.person_outline, size: radius * 1.2, color: scheme.onSecondaryContainer)
        : Text(
            initials,
            textScaler: TextScaler.noScaling,
            style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600, fontSize: radius * 0.8),
          );
    final picture = controller.pictures.of(did);
    return ExcludeSemantics(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.secondaryContainer),
        child: picture == null
            ? fallback
            : Image(
                key: Key('avatar-picture-$did'),
                image: picture,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                // a file that is no image after all: the initials
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
