#ifndef RUNNER_VIDEO_TEXTURE_H_
#define RUNNER_VIDEO_TEXTURE_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/texture_registrar.h>

#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>

struct VideoTexture;

// Textures for video tiles, over `dsip/video` (app/rust/src/api/video.rs);
// and a video call shown full screen: `window` over its whole monitor,
// without its frame, and back.
class VideoTextures {
 public:
  VideoTextures(flutter::FlutterEngine* engine, HWND window);
  ~VideoTextures();

 private:
  void SetFullScreen(bool on);

  HWND window_;
  bool full_screen_ = false;
  // The window's style and place before it went full screen.
  LONG_PTR style_ = 0;
  WINDOWPLACEMENT placement_ = {sizeof(WINDOWPLACEMENT)};

  flutter::TextureRegistrar* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  // The textures made, by id, until disposed of.
  std::map<int64_t, std::shared_ptr<VideoTexture>> textures_;
};

#endif  // RUNNER_VIDEO_TEXTURE_H_
