import 'dart:async';

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

/// The size of the picture on call [stream]'s tile (or the self-view's, `null`), once it has one. Tests set it.
Size? Function(int? stream) tileShape = _shape;

Size? _shape(int? stream) {
  try {
    final info = rust.tileInfo(stream: stream);
    if (info == null || info.width == 0 || info.height == 0) return null;
    return Size(info.width.toDouble(), info.height.toDouble());
  } catch (_) {
    return null;
  }
}

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

/// A call's picture ([stream], its id) or this side's camera (`null`), in its box, the picture's own shape kept (a
/// phone held upright sends a tall one): fitted whole, dark around it; a dark box until a picture comes, or where the
/// app cannot show one.
class VideoTile extends StatefulWidget {
  const VideoTile({super.key, required this.stream, this.mirror = false, this.onAspect});
  final int? stream;

  /// Shown as in a mirror: the self-view.
  final bool mirror;

  /// Told the picture's width over its height, when it is first known and whenever it changes (a phone turned).
  final ValueChanged<double>? onAspect;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  VideoTexture? _texture;
  bool _gone = false;
  Size? _size;

  /// The picture's size asked for twice a second, while there is a texture: it changes when the far end turns.
  Timer? _shape;

  @override
  void initState() {
    super.initState();
    showTile(widget.stream).then((t) {
      if (_gone) {
        t?.close();
      } else if (t != null) {
        setState(() => _texture = t);
        _measure();
        _shape = Timer.periodic(const Duration(milliseconds: 500), (_) => _measure());
      }
    });
  }

  void _measure() {
    final size = tileShape(widget.stream);
    if (size == null || size == _size || !mounted) return;
    setState(() => _size = size);
    widget.onAspect?.call(size.width / size.height);
  }

  @override
  void dispose() {
    _gone = true;
    _shape?.cancel();
    _texture?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texture = _texture;
    final size = _size;
    Widget picture = texture == null ? const SizedBox.expand() : Texture(textureId: texture.textureId);
    if (texture != null && size != null) {
      picture = Center(child: AspectRatio(aspectRatio: size.width / size.height, child: picture));
    }
    if (widget.mirror) picture = Transform.flip(flipX: true, child: picture);
    return ColoredBox(color: Colors.black, child: picture);
  }
}

/// What a video call shows in place of the far end's picture while none comes (their camera is off): dark, and a
/// camera struck through. Over the tile, which keeps its texture for when their pictures come again.
class NoFarVideo extends StatelessWidget {
  const NoFarVideo({super.key, required this.label});

  /// What it is, for a screen reader.
  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 40, semanticLabel: label)),
  );
}
