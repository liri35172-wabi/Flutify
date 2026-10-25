import 'package:flutify_app/ui/screens/settings/sections/floating_lyrics_section.dart';
import 'package:flutify_app/ui/screens/settings/widgets/floating_lyrics_preview_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android floating lyrics always preview without a backing plate', () {
    expect(
      FloatingLyricsPresentation.previewBackground(
        isAndroid: true,
        transparentBackground: false,
      ),
      Colors.transparent,
    );
    expect(
      FloatingLyricsPresentation.previewBackground(
        isAndroid: true,
        transparentBackground: true,
      ),
      Colors.transparent,
    );
    expect(
      FloatingLyricsPresentation.showBackgroundControl(
        isAndroid: true,
        isWindows: false,
      ),
      isFalse,
    );
  });

  test('Windows floating lyrics keeps its user-controlled backing', () {
    expect(
      FloatingLyricsPresentation.previewBackground(
        isAndroid: false,
        transparentBackground: false,
      ),
      const Color(0x99212630),
    );
    expect(
      FloatingLyricsPresentation.previewBackground(
        isAndroid: false,
        transparentBackground: true,
      ),
      Colors.transparent,
    );
    expect(
      FloatingLyricsPresentation.showBackgroundControl(
        isAndroid: false,
        isWindows: true,
      ),
      isTrue,
    );
  });

  testWidgets(
    'preview uses filled text with a lightweight shadow, not a stroke',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FloatingLyricsPreviewText(
              text: 'preview lyric',
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

      final lyric = tester.widget<Text>(find.text('preview lyric'));
      expect(lyric.style?.color, Colors.white);
      expect(lyric.style?.foreground, isNull);
      expect(lyric.style?.shadows, hasLength(1));
      expect(lyric.style!.shadows!.single.blurRadius, 1);
      expect(lyric.style!.shadows!.single.offset, const Offset(1, 1));
    },
  );
}
