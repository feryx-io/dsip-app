// Textures for video tiles (app/rust/src/api/video.rs): pictures never
// cross into Dart. Dart asks `dsip/video` to `create` a texture and gets
// its id, the address of `DsipVideoPresent` and the texture's own address;
// it hands the last two to Rust, whose video threads call
// `DsipVideoPresent` with each picture as RGBA. Dart detaches it from Rust
// before it asks to `dispose` of the texture, so the function is never
// called on a texture that has gone. `fullScreen` {on} takes the window
// over its monitor for a video call, and gives it back.

#include "video_texture.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <mutex>
#include <utility>
#include <vector>

struct VideoTexture {
  flutter::TextureRegistrar* registrar = nullptr;
  int64_t id = 0;
  std::unique_ptr<flutter::TextureVariant> variant;

  std::mutex lock;
  // The picture last presented, and whether the screen has taken it; only
  // the render thread touches `shown`, swapping it with `pending`.
  std::vector<uint8_t> pending;
  std::vector<uint8_t> shown;
  size_t pending_width = 0, pending_height = 0;
  bool fresh = false;
  FlutterDesktopPixelBuffer out = {};

  const FlutterDesktopPixelBuffer* Copy() {
    {
      std::lock_guard<std::mutex> guard(lock);
      if (fresh) {
        std::swap(pending, shown);
        out.width = pending_width;
        out.height = pending_height;
        fresh = false;
      }
    }
    if (shown.empty()) {
      return nullptr;
    }
    out.buffer = shown.data();
    return &out;
  }
};

// Called by Rust on a video thread with a picture to show now.
extern "C" void DsipVideoPresent(void* handle, const uint8_t* rgba,
                                  uint32_t width, uint32_t height) {
  auto* texture = static_cast<VideoTexture*>(handle);
  const size_t size = static_cast<size_t>(width) * height * 4;
  {
    std::lock_guard<std::mutex> guard(texture->lock);
    texture->pending.assign(rgba, rgba + size);
    texture->pending_width = width;
    texture->pending_height = height;
    texture->fresh = true;
  }
  texture->registrar->MarkTextureFrameAvailable(texture->id);
}

VideoTextures::VideoTextures(flutter::FlutterEngine* engine, HWND window)
    : window_(window) {
  auto* registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(
              engine->GetRegistrarForPlugin("DsipVideo"));
  registrar_ = registrar->texture_registrar();
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "dsip/video",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "create") {
          auto texture = std::make_shared<VideoTexture>();
          VideoTexture* raw = texture.get();
          texture->registrar = registrar_;
          texture->variant = std::make_unique<flutter::TextureVariant>(
              flutter::PixelBufferTexture(
                  [raw](size_t, size_t) { return raw->Copy(); }));
          texture->id = registrar_->RegisterTexture(texture->variant.get());
          textures_[texture->id] = texture;
          flutter::EncodableMap made;
          made[flutter::EncodableValue("texture")] =
              flutter::EncodableValue(texture->id);
          made[flutter::EncodableValue("present")] = flutter::EncodableValue(
              static_cast<int64_t>(reinterpret_cast<intptr_t>(&DsipVideoPresent)));
          made[flutter::EncodableValue("handle")] = flutter::EncodableValue(
              static_cast<int64_t>(reinterpret_cast<intptr_t>(raw)));
          result->Success(flutter::EncodableValue(made));
        } else if (call.method_name() == "dispose") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          int64_t id = 0;
          if (args) {
            auto found = args->find(flutter::EncodableValue("texture"));
            if (found != args->end()) {
              id = found->second.LongValue();
            }
          }
          auto texture = textures_.find(id);
          if (texture != textures_.end()) {
            // Kept until the engine has let go of it.
            std::shared_ptr<VideoTexture> kept = texture->second;
            textures_.erase(texture);
            registrar_->UnregisterTexture(id, [kept]() {});
          }
          result->Success();
        } else if (call.method_name() == "fullScreen") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool on = false;
          if (args) {
            auto found = args->find(flutter::EncodableValue("on"));
            if (found != args->end()) {
              if (const auto* b = std::get_if<bool>(&found->second)) {
                on = *b;
              }
            }
          }
          SetFullScreen(on);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

// The window without its frame over the whole of its monitor; back, its
// frame and place as they were.
void VideoTextures::SetFullScreen(bool on) {
  if (!window_ || on == full_screen_) {
    return;
  }
  if (on) {
    MONITORINFO monitor = {sizeof(MONITORINFO)};
    if (!GetWindowPlacement(window_, &placement_) ||
        !GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                        &monitor)) {
      return;
    }
    style_ = GetWindowLongPtr(window_, GWL_STYLE);
    SetWindowLongPtr(window_, GWL_STYLE, style_ & ~WS_OVERLAPPEDWINDOW);
    const RECT& r = monitor.rcMonitor;
    SetWindowPos(window_, HWND_TOP, r.left, r.top, r.right - r.left,
                 r.bottom - r.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    SetWindowLongPtr(window_, GWL_STYLE, style_);
    SetWindowPlacement(window_, &placement_);
    SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  }
  full_screen_ = on;
}

VideoTextures::~VideoTextures() {
  for (auto& [id, texture] : textures_) {
    std::shared_ptr<VideoTexture> kept = texture;
    registrar_->UnregisterTexture(id, [kept]() {});
  }
}
