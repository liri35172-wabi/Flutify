import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/screens/player/lyrics/lyrics_backdrop.dart';
import 'package:flutify_app/ui/shell/desktop/desktop_window.dart';
import 'package:flutify_app/ui/widgets/liquid_artwork_background.dart';

void main() {
  testWidgets('desktop artwork pauses during window transitions and resumes', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    final previousTransition = DesktopWindow.fullscreenTransition.value;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    DesktopWindow.fullscreenTransition.value = false;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: LyricsBackdrop(imageUrl: '')),
      );
      expect(
        tester
            .widget<LiquidArtworkBackground>(
              find.byType(LiquidArtworkBackground),
            )
            .animate,
        isTrue,
      );

      DesktopWindow.fullscreenTransition.value = true;
      await tester.pump();
      expect(
        tester
            .widget<LiquidArtworkBackground>(
              find.byType(LiquidArtworkBackground),
            )
            .animate,
        isFalse,
      );

      DesktopWindow.fullscreenTransition.value = false;
      await tester.pump();
      expect(
        tester
            .widget<LiquidArtworkBackground>(
              find.byType(LiquidArtworkBackground),
            )
            .animate,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    } finally {
      DesktopWindow.fullscreenTransition.value = previousTransition;
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
