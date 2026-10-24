import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/widgets/control_tooltip.dart';

void main() {
  group('desktopControlTooltipPosition', () {
    test('prefers above the pointer with a clear gap', () {
      const context = TooltipPositionContext(
        target: Offset(300, 250),
        targetSize: Size(48, 48),
        tooltipSize: Size(120, 32),
        verticalOffset: 30,
        overlaySize: Size(600, 400),
      );

      expect(desktopControlTooltipPosition(context), const Offset(240, 164));
    });

    test('flips below only when the tooltip cannot fit above', () {
      const context = TooltipPositionContext(
        target: Offset(200, 70),
        targetSize: Size(48, 48),
        tooltipSize: Size(120, 32),
        verticalOffset: 30,
        overlaySize: Size(600, 400),
      );

      expect(desktopControlTooltipPosition(context).dy, 124);
    });

    test('clamps the full tooltip inside the horizontal edges', () {
      const context = TooltipPositionContext(
        target: Offset(10, 150),
        targetSize: Size(20, 20),
        tooltipSize: Size(100, 30),
        verticalOffset: 30,
        overlaySize: Size(600, 400),
      );

      expect(desktopControlTooltipPosition(context).dx, 8);
    });
  });

  test('touch platforms keep the native button tooltip', () {
    final previous = foundation.debugDefaultTargetPlatformOverride;
    foundation.debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => foundation.debugDefaultTargetPlatformOverride = previous);

    expect(ControlTooltip.nativeTooltip('Translate'), 'Translate');
  });

  test(
    'desktop platforms delegate tooltip placement to the custom overlay',
    () {
      final previous = foundation.debugDefaultTargetPlatformOverride;
      foundation.debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(
        () => foundation.debugDefaultTargetPlatformOverride = previous,
      );

      expect(ControlTooltip.nativeTooltip('Translate'), isNull);
    },
  );
}
