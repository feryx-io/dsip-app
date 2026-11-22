import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';

/// The letters shown for [name] without a picture: the first of its first word and of its last, in capitals; empty
/// without a name.
String initialsOf(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  String first(String w) => String.fromCharCode(w.runes.first).toUpperCase();
  return words.length == 1 ? first(words.first) : first(words.first) + first(words.last);
}

/// What a screen says beside a profile card someone sent: what it claims, and that nobody checked it.
String cardClaim(Strings s, ProfileCard card) => switch ((card.name, card.picture)) {
  (final String name, null) => s.cardClaimName(name),
  (final String name, _) => s.cardClaimNameAndPicture(name),
  _ => s.cardClaimPicture,
};

/// Someone as a small circle: the picture the user gave them, or the one their profile card carries ([cardPicture]),
/// or their initials, or (with no name either) a person. Beside their name, so it says nothing of its own to a screen
/// reader.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.controller,
    required this.did,
    this.name,
    this.radius = 20,
    this.cardPicture,
    this.claimBeside = false,
  });
  final Controller controller;
  final String did;

  /// The picture file of the profile card they sent: their own claim (core §19.4). The picture the user chose for them
  /// is shown before it.
  final String? cardPicture;

  /// Whether the screen says in words beside this that the card is not verified ([cardClaim]). Where it does not, a
  /// card's picture carries a mark on its corner that says so when pointed at or held, and to a screen reader.
  final bool claimBeside;

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
    final chosen = controller.pictures.of(did);
    final picture = chosen ?? (cardPicture == null ? null : ResizeImage(FileImage(File(cardPicture!)), width: 128));
    final circle = ExcludeSemantics(
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
    if (chosen != null || cardPicture == null || claimBeside) return circle;
    // their own claim, with no words beside it here: marked, and the mark says what it is
    final mark = radius * 0.8;
    return Tooltip(
      key: Key('avatar-claim-$did'),
      message: Strings.of(context).cardClaimPicture,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          PositionedDirectional(
            start: -2,
            top: -2,
            child: ExcludeSemantics(
              child: Container(
                width: mark,
                height: mark,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface,
                  border: Border.all(color: scheme.outline),
                ),
                child: Icon(Icons.question_mark, size: mark * 0.65, color: scheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
