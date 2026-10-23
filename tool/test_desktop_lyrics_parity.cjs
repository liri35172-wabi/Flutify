const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const floating = readFileSync(join(__dirname, '../windows/runner/floating_lyrics_window.cpp'), 'utf8');
const painter = readFileSync(join(__dirname, '../windows/runner/taskbar_lyrics_painter.cpp'), 'utf8');

test('floating desktop lyrics use taskbar typography and animation timing', () => {
  assert.match(floating, /kAnimationMs = 300/);
  assert.match(floating, /kAnimationMs \+ 60/);
  assert.match(floating, /style_\.font_scale \/ 100\.0, false, true\}/);
  assert.match(floating, /next_translation, false, eased\)/);
  assert.match(painter, /if \(canvas\.dual_contrast_outline\)/);
});
