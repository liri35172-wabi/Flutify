#ifndef RUNNER_TASKBAR_LYRICS_H_
#define RUNNER_TASKBAR_LYRICS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

#include "taskbar_lyrics_state.h"

class TaskbarLyricsWindow;
class FloatingLyricsWindow;

// 任务栏歌词（原「任务栏歌词」项目合并进 Flutify 后的原生部分）。
//
// MethodChannel `flutify/taskbar_lyrics`（Dart 端见 lib/services/taskbar_lyrics/taskbar_lyrics_channel.dart）：
//   Dart → 原生：setEnabled(bool)、
//               setStyle({mode, custom, accentOnDark, accentOnLight, opacity, labels{open, refetch, disable}})、
//               setTrack({title, artist} | null)、setArt(Uint8List | null)、
//               setLyrics({times: Int32List 毫秒, texts: [String]} | null)、setPlayback({playing, positionMs})
//   原生 → Dart：event("previous" | "toggle" | "next" | "open" | "refetch" | "disable")
//
// 关闭时不创建任何窗口与线程；开启后由 TaskbarLyricsWindow 在独立线程上驱动任务栏窗口。
class TaskbarLyrics {
 public:
  TaskbarLyrics(HWND window, flutter::BinaryMessenger* messenger);
  ~TaskbarLyrics();

  TaskbarLyrics(const TaskbarLyrics&) = delete;
  TaskbarLyrics& operator=(const TaskbarLyrics&) = delete;

  // 顶层窗口消息；处理了任务栏窗口投递的事件时返回 true。
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void OnMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetEnabled(bool enabled);
  void SetOverlayEnabled(bool enabled);
  bool EnsureGdiplus();
  void ShutdownGdiplusIfIdle();

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  ULONG_PTR gdiplus_token_ = 0;
  taskbar_lyrics::Shared shared_;
  std::unique_ptr<TaskbarLyricsWindow> lyrics_window_;
  std::unique_ptr<FloatingLyricsWindow> overlay_window_;
};

#endif  // RUNNER_TASKBAR_LYRICS_H_
