// The app in Windows' notification area (device-test finding 17): closing
// the window hides it, the app goes on and rings for calls; the icon shows
// the window again; Quit in the icon's menu ends the app.

#include "tray.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include "resource.h"

namespace {

// The icon's own message, and its id.
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr UINT kOpenCommand = 1;
constexpr UINT kQuitCommand = 2;

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(static_cast<size_t>(length > 0 ? length : 0), L'\0');
  if (length > 0) {
    ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                          static_cast<int>(utf8.size()), wide.data(), length);
  }
  return wide;
}

NOTIFYICONDATAW Icon(HWND window) {
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = kTrayId;
  return data;
}

}  // namespace

Tray::Tray(flutter::FlutterEngine* engine, HWND window)
    : window_(window),
      taskbar_created_(::RegisterWindowMessageW(L"TaskbarCreated")),
      show_running_(::RegisterWindowMessageW(kShowRunningMessage)) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "dsip/tray",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "labels") {
          result->NotImplemented();
          return;
        }
        if (const auto* labels =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto text = [labels](const char* key, std::wstring* into) {
            auto found = labels->find(flutter::EncodableValue(key));
            if (found == labels->end()) {
              return;
            }
            if (const auto* s = std::get_if<std::string>(&found->second)) {
              if (!s->empty()) {
                *into = Wide(*s);
              }
            }
          };
          text("open", &open_);
          text("quit", &quit_);
          text("running", &running_);
        }
        result->Success();
      });
  Add();
}

Tray::~Tray() {
  NOTIFYICONDATAW data = Icon(window_);
  ::Shell_NotifyIconW(NIM_DELETE, &data);
}

void Tray::Add() {
  NOTIFYICONDATAW data = Icon(window_);
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = static_cast<HICON>(::LoadImageW(
      ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR | LR_SHARED));
  wcsncpy_s(data.szTip, L"DSIP", _TRUNCATE);
  ::Shell_NotifyIconW(NIM_ADD, &data);
}

void Tray::Hide() {
  ::ShowWindow(window_, SW_HIDE);
  if (told_) {
    return;
  }
  // Once a run: where the app went, and that it goes on.
  told_ = true;
  NOTIFYICONDATAW data = Icon(window_);
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO;
  wcsncpy_s(data.szInfoTitle, L"DSIP", _TRUNCATE);
  wcsncpy_s(data.szInfo, running_.c_str(), _TRUNCATE);
  ::Shell_NotifyIconW(NIM_MODIFY, &data);
}

void Tray::Restore() {
  ::ShowWindow(window_, ::IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(window_);
}

void Tray::Menu() {
  HMENU menu = ::CreatePopupMenu();
  if (!menu) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, kOpenCommand, open_.c_str());
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kQuitCommand, quit_.c_str());
  POINT at;
  ::GetCursorPos(&at);
  // The menu closes when the user clicks elsewhere only if its window is
  // in front.
  ::SetForegroundWindow(window_);
  UINT chosen = static_cast<UINT>(::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, at.x, at.y, 0,
      window_, nullptr));
  ::DestroyMenu(menu);
  ::PostMessageW(window_, WM_NULL, 0, 0);
  if (chosen == kOpenCommand) {
    Restore();
  } else if (chosen == kQuitCommand) {
    // Posted, not destroyed here: this object goes with the window.
    quitting_ = true;
    ::PostMessageW(window_, WM_CLOSE, 0, 0);
  }
}

std::optional<LRESULT> Tray::Handle(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam) {
  if (message == WM_CLOSE) {
    if (quitting_) {
      return std::nullopt;
    }
    Hide();
    return 0;
  }
  // Windows ending the session, or a setup closing the app to replace it
  // (the Restart Manager asks the same way): then a close closes.
  if (message == WM_QUERYENDSESSION) {
    quitting_ = true;
    return std::nullopt;
  }
  if (message == WM_ENDSESSION) {
    quitting_ = wparam != 0;
    if (quitting_) {
      ::PostMessageW(window, WM_CLOSE, 0, 0);
    }
    return std::nullopt;
  }
  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        Restore();
        break;
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU:
        Menu();
        break;
    }
    return 0;
  }
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    // Explorer started again: its icons are gone.
    Add();
    return 0;
  }
  if (message == show_running_ && show_running_ != 0) {
    // DSIP was started while it runs: this one comes forward.
    Restore();
    return 0;
  }
  return std::nullopt;
}
