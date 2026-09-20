#include "utils.h"

#include <flutter.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

std::vector<std::string> GetCommandLineArguments() {
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return std::vector<std::string>();

  std::vector<std::string> command_line_arguments;
  for (int i = 0; i < argc; i++) {
    std::wstring ws(argv[i]);
    command_line_arguments.push_back(std::string(ws.begin(), ws.end()));
  }

  ::LocalFree(argv);
  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) return std::string();
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr);
  if (target_length == 0) return std::string();

  std::string utf8_string;
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) return std::string();

  return utf8_string;
}
