#ifndef RUNNER_FLOATING_LYRICS_WINDOW_H_
#define RUNNER_FLOATING_LYRICS_WINDOW_H_

#include <windows.h>

#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "gdiplus_include.h"
#include "taskbar_lyrics_painter.h"
#include "taskbar_lyrics_state.h"

// 独立的 Windows 置顶歌词窗：播放时悬浮在其他应用上方，可拖动，不获取键盘焦点。
class FloatingLyricsWindow {
 public:
  FloatingLyricsWindow(HWND app_window, taskbar_lyrics::Shared* shared);
  ~FloatingLyricsWindow();

  FloatingLyricsWindow(const FloatingLyricsWindow&) = delete;
  FloatingLyricsWindow& operator=(const FloatingLyricsWindow&) = delete;

  void Wake();

 private:
  void ThreadMain(HANDLE ready);
  static LRESULT CALLBACK HostProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK OverlayProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  void Tick();
  void SyncState();
  void Render();
  bool EnsureSurface(int width, int height);
  void Push();
  void SetInterval(UINT ms);
  void PlaceInitial();
  Gdiplus::Color TextColor() const;
  bool UsesLightBackground() const;
  int64_t PositionMs() const;

  HWND app_window_;
  taskbar_lyrics::Shared* shared_;
  std::thread thread_;
  std::atomic<HWND> host_{nullptr};
  HWND overlay_ = nullptr;
  std::unique_ptr<TaskbarLyricsPainter> painter_;

  uint64_t track_version_ = ~0ull;
  uint64_t lyrics_version_ = ~0ull;
  uint64_t style_version_ = ~0ull;
  bool has_track_ = false;
  std::wstring title_;
  std::wstring artist_;
  std::vector<taskbar_lyrics::LyricLine> lines_;
  bool playing_ = false;
  int64_t anchor_ms_ = 0;
  ULONGLONG anchor_tick_ = 0;
  taskbar_lyrics::Style style_;

  double scale_ = 1.0;
  int width_ = 680;
  int height_ = 100;
  int display_index_ = -2;
  ULONGLONG anim_start_ = 0;
  UINT interval_ = 0;

  HDC surface_dc_ = nullptr;
  HBITMAP surface_bitmap_ = nullptr;
  HGDIOBJ surface_old_ = nullptr;
  void* surface_bits_ = nullptr;
  int surface_width_ = 0;
  int surface_height_ = 0;
};

#endif  // RUNNER_FLOATING_LYRICS_WINDOW_H_
