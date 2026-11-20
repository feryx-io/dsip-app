#ifndef RUNNER_TRAY_H_
#define RUNNER_TRAY_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <windows.h>

#include <memory>
#include <optional>
#include <string>

// The message a second DSIP posts to the one already running, which shows
// its window (main.cpp, tray.cpp).
constexpr const wchar_t kShowRunningMessage[] = L"com.feryx.dsip.show";

// The app in the notification area. Closing the window hides it there, so
// calls still ring; the icon opens it again, and its menu's Quit is what
// ends the app.
class Tray {
 public:
  Tray(flutter::FlutterEngine* engine, HWND window);
  ~Tray();

  // The window's messages, before Flutter sees them: a result when the
  // message was the tray's.
  std::optional<LRESULT> Handle(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam);

 private:
  void Add();
  void Hide();
  void Restore();
  void Menu();

  HWND window_;
  // Quit was chosen: the next close closes.
  bool quitting_ = false;
  // The user was told once, this run, that the app goes on.
  bool told_ = false;
  UINT taskbar_created_;
  UINT show_running_;
  // The menu's entries and the notice, in the app's language once it said
  // ("labels" on dsip/tray).
  std::wstring open_ = L"Open DSIP";
  std::wstring quit_ = L"Quit DSIP";
  std::wstring running_ = L"DSIP is still running and rings for calls.";
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_TRAY_H_
