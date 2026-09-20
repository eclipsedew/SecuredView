#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <chrono>
#include <filesystem>
#include <memory>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  ::HeapSetInformation(NULL, HeapEnableTerminationOnCorruption, NULL, 0);

  if (!SUCCEEDED(::CoInitializeEx(NULL, COINIT_APARTMENTTHREADED))) {
    return 1;
  }

  ::CreateMutex(NULL, TRUE, L"WarpVPN");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    return 1;
  }

  project::RunLoop run_loop;

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(420, 800);
  if (!window.Create(L"WarpVPN", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, NULL, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
