import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import 'calls.dart' show AudioRouteButton;
import 'video_tile.dart';

/// The call shown full screen, if one is: its card shows no picture meanwhile, so each tile has one texture at a time
/// (a tile shows on the texture attached last; the card's would be left without one when this one went).
final fullScreenCall = ValueNotifier<int?>(null);

/// Take the window (a PC's) or the screen (a phone's: the system's bars hidden) for a video call, or give it back. Tests
/// set it.
Future<void> Function(bool on) setFullScreen = _setFullScreen;

const _channel = MethodChannel('dsip/video');

Future<void> _setFullScreen(bool on) async {
  if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
    await SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    return;
  }
  try {
    await _channel.invokeMethod<void>('fullScreen', {'on': on});
  } on MissingPluginException {
    // the window stays as it is; the call still fills it
  }
}

/// Show video call [call] full screen, until the user leaves it or the call ends.
Future<void> showVideoFullScreen(BuildContext context, Controller controller, int call) async {
  fullScreenCall.value = call;
  unawaited(setFullScreen(true));
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => VideoFullScreen(controller: controller, call: call)),
    );
  } finally {
    fullScreenCall.value = null;
    unawaited(setFullScreen(false));
  }
}

/// A video call filling the screen: the far end's picture whole, on black; this side's camera in a corner; the call's
/// buttons along the bottom (mute, camera, where the audio goes on a phone, hang up) and a way back to the app. Esc
/// goes back too. It goes by itself when the call ends.
class VideoFullScreen extends StatefulWidget {
  const VideoFullScreen({super.key, required this.controller, required this.call});
  final Controller controller;
  final int call;

  @override
  State<VideoFullScreen> createState() => _VideoFullScreenState();
}

class _VideoFullScreenState extends State<VideoFullScreen> {
  double _self = 4 / 3;
  bool _left = false;

  static const _selfSide = 160.0;

  CallView? get _view =>
      widget.controller.state?.calls.where((c) => c.id == widget.call && !c.state.ended).firstOrNull;

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _leave},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final call = _view;
              if (call == null) {
                // over: back to the app
                WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
                return const SizedBox.expand();
              }
              void act(String command) => widget.controller.run({'command': command, 'call': call.id});
              final (selfWidth, selfHeight) =
                  _self >= 1 ? (_selfSide, _selfSide / _self) : (_selfSide * _self, _selfSide);
              final buttons = Theme.of(context).copyWith(
                iconButtonTheme: IconButtonThemeData(
                  style: IconButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white, iconSize: 28),
                ),
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onDoubleTap: _leave,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoTile(key: const Key('full-far'), stream: call.id),
                          // their camera off: dark, not the last picture that came
                          if (!call.farVideo) NoFarVideo(key: const Key('full-far-off'), label: s.callFarCameraOff),
                        ],
                      ),
                    ),
                  ),
                  if (call.camera)
                    Positioned(
                      right: 16,
                      top: 16,
                      width: selfWidth,
                      height: selfHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: VideoTile(
                          key: const Key('full-self'),
                          stream: null,
                          mirror: true,
                          onAspect: (a) => setState(() => _self = a),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: SafeArea(
                      child: Theme(
                        data: buttons,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            IconButton(
                              key: const Key('full-mute'),
                              tooltip: call.muted ? s.callUnmute : s.callMute,
                              onPressed: () => act(call.muted ? 'unmute' : 'mute'),
                              icon: Icon(call.muted ? Icons.mic_off : Icons.mic),
                            ),
                            IconButton(
                              key: const Key('full-camera'),
                              tooltip: call.camera ? s.callCameraOff : s.callCameraOn,
                              onPressed: () =>
                                  widget.controller.run({'command': 'camera', 'call': call.id, 'on': !call.camera}),
                              icon: Icon(call.camera ? Icons.videocam : Icons.videocam_off),
                            ),
                            if (widget.controller.system case final system?) AudioRouteButton(system: system),
                            IconButton(
                              key: const Key('full-hangup'),
                              tooltip: s.callHangUp,
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.error,
                                foregroundColor: Theme.of(context).colorScheme.onError,
                              ),
                              onPressed: () => act('hangup'),
                              icon: const Icon(Icons.call_end),
                            ),
                            IconButton(
                              key: const Key('full-leave'),
                              tooltip: s.callExitFullScreen,
                              onPressed: _leave,
                              icon: const Icon(Icons.fullscreen_exit),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
