const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const floating = readFileSync(join(__dirname, '../windows/runner/floating_lyrics_window.cpp'), 'utf8');
const painter = readFileSync(join(__dirname, '../windows/runner/taskbar_lyrics_painter.cpp'), 'utf8');
const taskbar = readFileSync(join(__dirname, '../windows/runner/taskbar_lyrics_window.cpp'), 'utf8');

test('floating desktop lyrics use taskbar typography and animation timing', () => {
  assert.match(floating, /kAnimationMs = 300/);
  assert.match(floating, /kAnimationMs \+ 60/);
  assert.match(floating, /style_\.font_scale \/ 100\.0, true, !high_contrast, high_contrast/);
  assert.match(painter, /constexpr double kOverlayBigPt = 18\.0/);
  assert.match(painter, /constexpr double kOverlaySmallPt = 12\.6/);
  assert.match(painter, /canvas\.floating_overlay \? kOverlayBigPt : kBigPt/);
  assert.match(floating, /next_translation, false, eased\)/);
  assert.match(painter, /if \(canvas\.dual_contrast_outline && !canvas\.high_contrast\)/);
});


test('floating Auto lyrics retain a local dual outline without screen sampling', () => {
  assert.match(floating, /case ColorMode::kAuto:[\s\S]*?return IsHighContrastAuto\(\) \? PairedSystemColor\(COLOR_WINDOWTEXT\) : Gdiplus::Color\(kWhite\);/);
  assert.match(floating, /true, !high_contrast, high_contrast/);
  assert.match(painter, /if \(canvas\.dual_contrast_outline && !canvas\.high_contrast\)/);
  assert.match(painter, /draw_outline\(255, 255, 255, 2\.2f, 220\)/);
  assert.match(painter, /draw_outline\(0, 0, 0, 1\.25f, 245\)/);
  assert.match(taskbar, /if \(style_\.mode == ColorMode::kAuto \|\| style_\.mode == ColorMode::kAccent\) SampleBackground\(\)/);
  assert.match(taskbar, /case ColorMode::kAuto:[\s\S]*?dark_text_ \? kDark : kWhite/);
  assert.doesNotMatch(taskbar, /dual_contrast_outline/);
  assert.doesNotMatch(floating, /BitBlt|PrintWindow|Windows.Graphics.Capture|CreateCaptureSession/);
});

test('Windows high-contrast Auto uses system foreground/background and opaque rendering', () => {
  assert.match(floating, /SystemParametersInfoW\(SPI_GETHIGHCONTRAST/);
  assert.match(floating, /GetSysColor\(index\)/);
  assert.match(floating, /PairedSystemColor\(COLOR_WINDOWTEXT\)/);
  assert.match(floating, /PairedSystemColor\(COLOR_WINDOW\)/);
  assert.match(floating, /graphics\.Clear\(high_contrast \? HighContrastBackgroundColor\(\)/);
  assert.match(floating, /if \(high_contrast\) \{[\s\S]*?paired system background must remain solid/);
  assert.match(painter, /alpha = canvas\.high_contrast \? 255/);
});
