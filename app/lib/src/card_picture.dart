import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The most a profile card's picture may be, in bytes (core §19.4).
const cardPictureMaxBytes = 4096;

/// The image file in [bytes] as a picture a profile card can carry: its middle square, small, as a JPEG of at most
/// [cardPictureMaxBytes]; null when [bytes] is no image this app reads.
///
/// A card is sealed into an introduction, which is small by design, so the picture is a thumbnail: 128 pixels across
/// when that fits, smaller or coarser until it does.
Uint8List? shrinkCardPicture(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  // as the camera held it, not as the file stores it
  final upright = img.bakeOrientation(decoded);
  final side = upright.width < upright.height ? upright.width : upright.height;
  final square = img.copyCrop(
    upright,
    x: (upright.width - side) ~/ 2,
    y: (upright.height - side) ~/ 2,
    width: side,
    height: side,
  );
  for (final size in const [128, 96, 64, 48, 32]) {
    final small = side <= size
        ? square
        : img.copyResize(square, width: size, height: size, interpolation: img.Interpolation.average);
    for (final quality in const [80, 65, 50, 35]) {
      final jpeg = img.encodeJpg(small, quality: quality);
      if (jpeg.length <= cardPictureMaxBytes) return jpeg;
    }
  }
  return null;
}

/// [shrinkCardPicture], off the screen's thread: a large photo takes a moment.
Future<Uint8List?> shrinkCardPictureInBackground(Uint8List bytes) => compute(shrinkCardPicture, bytes);
