import 'package:flutify_app/core/theme/flutify_tokens.dart';
import 'package:flutify_app/models/appearance.dart';
import 'package:flutify_app/ui/screens/player/lyrics/lyric_line_view.dart';
import 'package:flutify_app/ui/widgets/liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppearanceSettings performance fields', () {
    test('default to full effects and following the display', () {
      const d = AppearanceSettings.defaults;
      expect(d.powerSaving, isFalse);
      expect(d.frameRateLimit, 0);
    });

    test('round-trip through JSON', () {
      const s = AppearanceSettings(powerSaving: true, frameRateLimit: 97);
      final back = AppearanceSettings.fromJson(s.toJson());
      expect(back, s);
    });

    test('clamp out-of-range frame rates and ignore bad types', () {
      expect(AppearanceSettings.fromJson({'frameRateLimit': 5}).frameRateLimit, AppearanceSettings.minFrameRateLimit);
      expect(AppearanceSettings.fromJson({'frameRateLimit': 999}).frameRateLimit, AppearanceSettings.maxFrameRateLimit);
      expect(AppearanceSettings.fromJson({'frameRateLimit': '60'}).frameRateLimit, 0);
      expect(AppearanceSettings.fromJson({'powerSaving': 1}).powerSaving, isFalse);
    });
  });

  testWidgets('power saving glass skips the backdrop blur but keeps its shape', (tester) async {
    final tokens = FlutifyTokens.from(const AppearanceSettings(powerSaving: true), const Color(0xFF1ED760));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [tokens]),
        home: const Center(
          child: LiquidGlass(child: SizedBox(width: 120, height: 48)),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.getSize(find.byType(LiquidGlass)), const Size(120, 48));
  });
  testWidgets('power saving lyric lines skip the per-line blur', (
    tester,
  ) async {
    final tokens = FlutifyTokens.from(
      const AppearanceSettings(powerSaving: true),
      const Color(0xFF1ED760),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [tokens]),
        home: const Scaffold(
          body: LyricLineView(text: 'A nearby line', distance: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final filter = tester.widget<ImageFiltered>(find.byType(ImageFiltered));
    expect(filter.enabled, isFalse);
  });

}
