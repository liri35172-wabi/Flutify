#include "floating_lyrics_window.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr wchar_t kHostClass[] = L"FlutifyFloatingLyricsHost";
constexpr wchar_t kOverlayClass[] = L"FlutifyFloatingLyricsOverlay";
constexpr UINT_PTR kTimerId = 1;
constexpr UINT kWakeMessage = WM_APP + 2;
constexpr int64_t kLeadMs = 300;
constexpr ULONGLONG kAnimationMs = 260;

void AddRoundRect(Gdiplus::GraphicsPath* path, const Gdiplus::RectF& rect, float radius) {
  const float diameter = radius * 2;
  path->AddArc(rect.X, rect.Y, diameter, diameter, 180, 90);
  path->AddArc(rect.X + rect.Width - diameter, rect.Y, diameter, diameter, 270, 90);
  path->AddArc(rect.X + rect.Width - diameter, rect.Y + rect.Height - diameter, diameter, diameter, 0, 90);
  path->AddArc(rect.X, rect.Y + rect.Height - diameter, diameter, diameter, 90, 90);
  path->CloseFigure();
}

bool RegisterWindowClass(const wchar_t* name, WNDPROC procedure, HINSTANCE instance, HCURSOR cursor = nullptr) {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = procedure;
  window_class.hInstance = instance;
  window_class.hCursor = cursor;
  window_class.lpszClassName = name;
  if (RegisterClassW(&window_class)) return true;
  return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

}  // namespace

FloatingLyricsWindow::FloatingLyricsWindow(HWND app_window, taskbar_lyrics::Shared* shared)
    : app_window_(app_window), shared_(shared) {
  HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  thread_ = std::thread([this, ready] { ThreadMain(ready); });
  WaitForSingleObject(ready, INFINITE);
  CloseHandle(ready);
}

FloatingLyricsWindow::~FloatingLyricsWindow() {
  if (HWND host = host_.load()) PostMessageW(host, WM_CLOSE, 0, 0);
  if (thread_.joinable()) thread_.join();
}

void FloatingLyricsWindow::Wake() {
  if (HWND host = host_.load()) PostMessageW(host, kWakeMessage, 0, 0);
}

void FloatingLyricsWindow::ThreadMain(HANDLE ready) {
  HINSTANCE instance = GetModuleHandleW(nullptr);
  const bool classes_ready = RegisterWindowClass(kHostClass, HostProc, instance) &&
                              RegisterWindowClass(kOverlayClass, OverlayProc, instance,
                                                  LoadCursorW(nullptr, IDC_SIZEALL));
  if (classes_ready) {
    painter_ = std::make_unique<TaskbarLyricsPainter>();
    HWND host = CreateWindowExW(WS_EX_TOOLWINDOW, kHostClass, L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr,
                                instance, this);
    host_ = host;
    SetEvent(ready);
    if (!host) {
      painter_.reset();
      return;
    }
    SetInterval(100);
    Tick();
    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  } else {
    SetEvent(ready);
  }

  if (overlay_) DestroyWindow(overlay_);
  overlay_ = nullptr;
  painter_.reset();
  if (surface_dc_) {
    SelectObject(surface_dc_, surface_old_);
    DeleteObject(surface_bitmap_);
    DeleteDC(surface_dc_);
    surface_dc_ = nullptr;
    surface_bitmap_ = nullptr;
  }
}

LRESULT CALLBACK FloatingLyricsWindow::HostProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* self = reinterpret_cast<FloatingLyricsWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) {
    switch (message) {
      case WM_TIMER:
      case kWakeMessage:
        self->Tick();
        return 0;
      case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
      case WM_DESTROY:
        KillTimer(hwnd, kTimerId);
        if (self->overlay_) DestroyWindow(self->overlay_);
        self->overlay_ = nullptr;
        self->host_ = nullptr;
        PostQuitMessage(0);
        return 0;
    }
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK FloatingLyricsWindow::OverlayProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* self = reinterpret_cast<FloatingLyricsWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) {
    if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message == WM_NCHITTEST) return HTCAPTION;
    if (message == WM_NCDESTROY) {
      if (self->overlay_ == hwnd) self->overlay_ = nullptr;
    }
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void FloatingLyricsWindow::SetInterval(UINT ms) {
  if (ms == interval_) return;
  interval_ = ms;
  if (HWND host = host_.load()) SetTimer(host, kTimerId, ms, nullptr);
}

void FloatingLyricsWindow::PlaceInitial() {
  const UINT dpi = GetDpiForWindow(app_window_);
  scale_ = dpi > 0 ? dpi / 96.0 : 1.0;
  HMONITOR monitor = MonitorFromWindow(app_window_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  RECT area{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
  if (GetMonitorInfoW(monitor, &info)) area = info.rcWork;
  const int area_width = area.right - area.left;
  height_ = static_cast<int>(104 * scale_);
  width_ = (std::min)(static_cast<int>(680 * scale_), area_width - static_cast<int>(24 * scale_));
  width_ = (std::max)(width_, (std::min)(static_cast<int>(260 * scale_), area_width));
  const int x = area.left + (area_width - width_) / 2;
  const int y = area.top + static_cast<int>(34 * scale_);
  SetWindowPos(overlay_, HWND_TOPMOST, x, y, width_, height_, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void FloatingLyricsWindow::Tick() {
  SyncState();
  if (!has_track_) {
    if (overlay_ && IsWindowVisible(overlay_)) ShowWindow(overlay_, SW_HIDE);
    SetInterval(250);
    return;
  }
  if (!overlay_) {
    overlay_ = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
                               kOverlayClass, L"Flutify Floating Lyrics", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr,
                               GetModuleHandleW(nullptr), this);
    if (!overlay_) {
      SetInterval(1000);
      return;
    }
    PlaceInitial();
  } else if (!IsWindowVisible(overlay_)) {
    ShowWindow(overlay_, SW_SHOWNOACTIVATE);
  }

  const UINT dpi = GetDpiForWindow(overlay_);
  const double new_scale = dpi > 0 ? dpi / 96.0 : 1.0;
  if (std::abs(new_scale - scale_) > 0.01) {
    scale_ = new_scale;
    height_ = static_cast<int>(104 * scale_);
    RECT bounds{};
    if (GetWindowRect(overlay_, &bounds)) {
      SetWindowPos(overlay_, HWND_TOPMOST, bounds.left, bounds.top, width_, height_, SWP_NOACTIVATE);
    }
  }

  Render();
  const ULONGLONG now = GetTickCount64();
  const bool animating = display_index_ != -2 && now - anim_start_ < kAnimationMs + 40;
  SetInterval(animating ? 16 : (playing_ && !lines_.empty() ? 100 : 250));
}

void FloatingLyricsWindow::SyncState() {
  std::lock_guard<std::mutex> lock(shared_->mutex);
  if (shared_->track_version != track_version_) {
    track_version_ = shared_->track_version;
    has_track_ = shared_->has_track;
    title_ = shared_->title;
    artist_ = shared_->artist;
    display_index_ = -2;
  }
  if (shared_->lyrics_version != lyrics_version_) {
    lyrics_version_ = shared_->lyrics_version;
    lines_ = shared_->lines;
    display_index_ = -2;
  }
  if (shared_->style_version != style_version_) {
    style_version_ = shared_->style_version;
    style_ = shared_->style;
  }
  playing_ = shared_->playing;
  anchor_ms_ = shared_->anchor_ms;
  anchor_tick_ = shared_->anchor_tick;
}

int64_t FloatingLyricsWindow::PositionMs() const {
  if (!playing_) return anchor_ms_;
  return anchor_ms_ + static_cast<int64_t>(GetTickCount64() - anchor_tick_);
}

bool FloatingLyricsWindow::UsesLightBackground() const {
  using taskbar_lyrics::ColorMode;
  if (style_.mode == ColorMode::kBlack) return true;
  if (style_.mode != ColorMode::kCustom) return false;
  const uint32_t color = style_.custom;
  const uint32_t red = (color >> 16) & 0xFF;
  const uint32_t green = (color >> 8) & 0xFF;
  const uint32_t blue = color & 0xFF;
  return red * 299 + green * 587 + blue * 114 < 128000;
}

Gdiplus::Color FloatingLyricsWindow::TextColor() const {
  using taskbar_lyrics::ColorMode;
  constexpr Gdiplus::ARGB kDark = 0xFF141414;
  constexpr Gdiplus::ARGB kWhite = 0xFFFFFFFF;
  switch (style_.mode) {
    case ColorMode::kWhite:
      return Gdiplus::Color(kWhite);
    case ColorMode::kBlack:
      return Gdiplus::Color(kDark);
    case ColorMode::kAccent:
      return Gdiplus::Color(style_.accent_on_dark);
    case ColorMode::kCustom:
      return Gdiplus::Color(style_.custom);
    case ColorMode::kAuto:
    default:
      return Gdiplus::Color(kWhite);
  }
}

void FloatingLyricsWindow::Render() {
  if (!overlay_ || width_ <= 0 || height_ <= 0) return;
  std::wstring previous, current, next, translation;
  int index = -1;
  if (!lines_.empty()) {
    int low = 0;
    int high = static_cast<int>(lines_.size()) - 1;
    while (low <= high) {
      const int mid = (low + high) / 2;
      if (lines_[mid].start_ms <= PositionMs() + kLeadMs) {
        index = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
  }

  const ULONGLONG now = GetTickCount64();
  if (index != display_index_) {
    anim_start_ = display_index_ == -2 ? 0 : now;
    display_index_ = index;
  }
  const float progress = display_index_ == -2
                             ? 1.0f
                             : (std::min)(1.0f, static_cast<float>(now - anim_start_) /
                                                    static_cast<float>(kAnimationMs));
  const float eased = 1.0f - std::pow(1.0f - progress, 3.0f);
  if (lines_.empty() || index < 0) {
    current = L"\u266A " + title_ + (artist_.empty() ? L"" : L" \u2014 " + artist_);
  } else {
    current = lines_[index].text.empty() ? L"\u266A \u266A \u266A" : lines_[index].text;
    translation = lines_[index].translation;
    if (index > 0) previous = lines_[index - 1].text;
    if (index + 1 < static_cast<int>(lines_.size())) next = lines_[index + 1].text;
  }

  if (!EnsureSurface(width_, height_)) return;
  Gdiplus::Bitmap bitmap(width_, height_, width_ * 4, PixelFormat32bppPARGB, static_cast<BYTE*>(surface_bits_));
  Gdiplus::Graphics graphics(&bitmap);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);

  const float margin = static_cast<float>(4 * scale_);
  const Gdiplus::RectF pill(margin, margin, width_ - 2 * margin, height_ - 2 * margin);
  Gdiplus::GraphicsPath path;
  AddRoundRect(&path, pill, static_cast<float>(22 * scale_));
  const bool light_background = UsesLightBackground();
  Gdiplus::SolidBrush background(light_background ? Gdiplus::Color(224, 245, 246, 250)
                                                 : Gdiplus::Color(204, 20, 23, 30));
  graphics.FillPath(&background, &path);
  Gdiplus::Pen border(light_background ? Gdiplus::Color(80, 35, 38, 48)
                                       : Gdiplus::Color(64, 255, 255, 255),
                      static_cast<float>(scale_));
  graphics.DrawPath(&border, &path);

  const auto color = TextColor();
  const TaskbarLyricsPainter::Canvas canvas{&graphics, width_, height_, scale_, color, style_.opacity,
                                            style_.font_scale / 100.0, true};
  painter_->PaintLyrics(canvas, previous, current, next, translation, eased);
  graphics.Flush(Gdiplus::FlushIntentionSync);
  Push();
}

bool FloatingLyricsWindow::EnsureSurface(int width, int height) {
  if (surface_dc_ && width == surface_width_ && height == surface_height_) return true;
  if (surface_dc_) {
    SelectObject(surface_dc_, surface_old_);
    DeleteObject(surface_bitmap_);
    DeleteDC(surface_dc_);
    surface_dc_ = nullptr;
    surface_bitmap_ = nullptr;
  }
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  HDC screen = GetDC(nullptr);
  surface_bitmap_ = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &surface_bits_, nullptr, 0);
  surface_dc_ = surface_bitmap_ ? CreateCompatibleDC(screen) : nullptr;
  ReleaseDC(nullptr, screen);
  if (!surface_dc_) {
    if (surface_bitmap_) DeleteObject(surface_bitmap_);
    surface_bitmap_ = nullptr;
    return false;
  }
  surface_old_ = SelectObject(surface_dc_, surface_bitmap_);
  surface_width_ = width;
  surface_height_ = height;
  return true;
}

void FloatingLyricsWindow::Push() {
  if (!overlay_ || !surface_dc_) return;
  HDC screen = GetDC(nullptr);
  SIZE size{surface_width_, surface_height_};
  POINT source{0, 0};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  UpdateLayeredWindow(overlay_, screen, nullptr, &size, surface_dc_, &source, 0, &blend, ULW_ALPHA);
  ReleaseDC(nullptr, screen);
}
