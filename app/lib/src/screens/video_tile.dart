import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/api/video.dart' as rust;

/// A video call's pictures, as Anvil's app shows them: the runner's texture plugin (`dsip/video`; Windows'
/// `video_texture.cpp`, Android's `VideoTextures.kt`) makes a texture and hands back its id, the C function that fills
/// it and the texture's own address; those two go to Rust (`app/rust/src/api/video.rs`), whose video threads put each
/// picture on it. Pictures never cross into Dart. Where the runner has no plugin, nothing is shown.

/// A texture a tile is shown on, until closed.
abstract class VideoTexture {
  int get textureId;
  Future<void> close();
}

/// Show call [stream]'s picture (the app's call id), or this side's camera (`null`), on a new texture; `null` where
/// there is no texture plugin. Tests set it.
Future<VideoTexture?> Function(int? stream) showTile = _show;

const _channel = MethodChannel('dsip/video');

Future<VideoTexture?> _show(int? stream) async {
  final Map<Object?, Object?>? made;
  try {
    made = await _channel.invokeMapMethod<Object?, Object?>('create');
  } on MissingPluginException {
    return null;
  }
  final id = made?['texture'];
  final present = made?['present'];
  final handle = made?['handle'];
  if (id is! int || present is! int || handle is! int) return null;
  try {
    final attachment = rust.attachTile(stream: stream, present: BigInt.from(present), texture: BigInt.from(handle));
    return _Texture(id, attachment);
  } catch (_) {
    await _channel.invokeMethod<void>('dispose', {'texture': id});
    return null;
  }
}

class _Texture implements VideoTexture {
  _Texture(this.textureId, this._attachment);

  @override
  final int textureId;
  final BigInt _attachment;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Rust lets go of it first: no picture is put on it after this
    rust.detachTile(attachment: _attachment);
    await _channel.invokeMethod<void>('dispose', {'texture': textureId});
  }
}

/// A call's picture ([stream], its id) or this side's camera (`null`), filling its box, the picture's own shape kept;
/// a dark box until a picture comes, or where the app cannot show one.
class VideoTile extends StatefulWidget {
  const VideoTile({super.key, required this.stream, this.mirror = false});
  final int? stream;

  /// Shown as in a mirror: the self-view.
  final bool mirror;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  VideoTexture? _texture;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    showTile(widget.stream).then((t) {
      if (_gone) {
        t?.close();
      } else if (t != null) {
        setState(() => _texture = t);
      }
    });
  }

  @override
  void dispose() {
    _gone = true;
    _texture?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texture = _texture;
    Widget picture = texture == null ? const SizedBox.expand() : Texture(textureId: texture.textureId);
    if (widget.mirror) picture = Transform.flip(flipX: true, child: picture);
    return ColoredBox(color: Colors.black, child: picture);
  }
}
