#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_view_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_view_->engine() || !flutter_view_->engine()->run()) {
    return false;
  }
  RegisterPlugins(flutter_view_->engine());
  SetChildContent(flutter_view_->GetNativeWindow());

  flutter_view_->ForceSoftwareRasterization();
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_view_) {
    flutter_view_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_view_) {
    std::optional<LRESULT> result =
        flutter_view_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE: {
      if (flutter_view_) {
        flutter_view_->engine()->ReloadSystemFonts();
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
