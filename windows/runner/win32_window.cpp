#include "win32_window.h"

#include <dwmapi.h>
#include <flutter.h>
#include <windows.h>

namespace {

constexpr const wchar_t kWindowClassName[] = L"WARP_VPN_WINDOW_CLASS";

Win32Window* GetThisFromHandle(HWND window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept {
  if (message == WM_CREATE) {
    auto const cs = reinterpret_cast<CREATESTRUCT const*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    auto that = GetThisFromHandle(window);
    that->window_handle_ = window;
    return that->MessageHandler(window, message, wparam, lparam);
  }

  auto that = GetThisFromHandle(window);
  if (that != nullptr) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

}  // namespace

Win32Window::Win32Window() {}

Win32Window::~Win32Window() {
  Destroy();
}

bool Win32Window::Create(const std::wstring& title, Point origin, Size size) {
  Destroy();

  const wchar_t* window_class = kWindowClassName;

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      static_cast<int>(origin.x * scale_factor),
      static_cast<int>(origin.y * scale_factor),
      static_cast<int>(size.width * scale_factor),
      static_cast<int>(size.height * scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateWindow(window);
  SetFocus(window);

  return OnCreate();
}

bool Win32Window::OnCreate() {
  return true;
}

void Win32Window::OnDestroy() {
  if (quit_on_close_) {
    PostQuitMessage(0);
  }
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

RECT Win32Window::GetViewBounds() {
  return GetClientArea();
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();
  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);
  SetFocus(child_content_);
}

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept {
  switch (message) {
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, rect.left, rect.top,
                   rect.right - rect.left, rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE: {
      return 0;
    }

    case WM_DESTROY: {
      window_handle_ = nullptr;
      Destroy();
      return 0;
    }
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

BOOL Win32Window::Destroy() {
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  return TRUE;
}

void Win32Window::CreateClient(HWND window) {
  RECT frame;
  GetClientRect(window, &frame);
}
