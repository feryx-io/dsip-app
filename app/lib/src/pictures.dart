import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// The pictures the user gave contacts: one image file a contact in the app's own folder (`pictures/`), on this device
/// only. They are not sent to anyone, not shared with the user's other devices, and not in the identity's backup.
class Pictures {
  Pictures(this.dir);

  /// `pictures/` in the app's folder.
  final Directory dir;

  /// The identities with a picture ([load]).
  final _have = <String>{};

  /// The width pictures are decoded at: a list's small circle, on a dense screen.
  static const _decodeWidth = 128;

  File _file(String did) => File('${dir.path}${Platform.pathSeparator}${Uri.encodeComponent(did)}');

  /// Find the pictures kept.
  Future<void> load() async {
    _have.clear();
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && !name.endsWith('.tmp')) _have.add(Uri.decodeComponent(name));
    }
  }

  bool has(String did) => _have.contains(did);

  /// [did]'s picture, decoded small; null without one.
  ImageProvider? of(String did) => has(did) ? ResizeImage(FileImage(_file(did)), width: _decodeWidth) : null;

  /// Keep [bytes], an image file's, as [did]'s picture, in place of the one it had.
  Future<void> set(String did, Uint8List bytes) async {
    await dir.create(recursive: true);
    final file = _file(did);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(file.path);
    _have.add(did);
    // the last one is not shown from the cache
    await of(did)?.evict();
  }

  /// Forget [did]'s picture.
  Future<void> remove(String did) async {
    if (!_have.remove(did)) return;
    final file = _file(did);
    await ResizeImage(FileImage(file), width: _decodeWidth).evict();
    if (await file.exists()) await file.delete();
  }
}
