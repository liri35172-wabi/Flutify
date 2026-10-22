import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/screens/settings/widgets/floating_lyrics_preview_text.dart';

void main() {
  group('floatingLyricsOutlineColor', () {
    test('uses a dark keyline for bright and accent lyric colors', () {
      expect(floatingLyricsOutlineColor(Colors.white), const Color(0xFF15181F));
      expect(
        floatingLyricsOutlineColor(const Color(0xFF21D76B)),
        const Color(0xFF15181F),
      );
    });

    test('uses a light keyline for dark lyric colors', () {
      expect(
        floatingLyricsOutlineColor(const Color(0xFF111111)),
        const Color(0xFFF7F8FC),
      );
    });
  });
}
