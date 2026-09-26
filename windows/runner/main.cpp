#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

// Autostart at login (HKCU — no admin rights needed) so the app (and its
// tunnel ownership / IP display) comes up with the session after reboot.
static void RegisterAutostart() {
  wchar_t exePath[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, exePath, MAX_PATH) == 0) {
    return;
  }
  HKEY key = nullptr;
  if (::RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
          0, nullptr, 0, KEY_SET_VALUE, nullptr, &key,
          nullptr) != ERROR_SUCCESS) {
    return;
  }
  const std::wstring value = L"\"" + std::wstring(exePath) + L"\"";
  ::RegSetValueExW(key, L"SecuredView VPN", 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(value.c_str()),
                   static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(key);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  RegisterAutostart();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SecuredView VPN", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
