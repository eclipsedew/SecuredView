#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
    Point() : x(0), y(0) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
    Size() : width(0), height(0) {}
  };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring& title, Point origin, Size size);

  HWND GetHandle();

  void SetQuitOnClose(bool quit_on_close);

  RECT GetClientArea();

  RECT GetViewBounds();

  void SetChildContent(HWND content);

 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();
  virtual LRESULT MessageHandler(HWND hwnd, UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

 private:
  friend LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  bool CreateClient();
  void CreateClient(HWND window);
  BOOL Destroy();

  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
  bool quit_on_close_ = false;
};

#endif  // RUNNER_WIN32_WINDOW_H_
