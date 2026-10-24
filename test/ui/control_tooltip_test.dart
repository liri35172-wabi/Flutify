import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/widgets/control_tooltip.dart';

void main() {
  group('desktopControlTooltipPosition', () {
    const overlay = Size(600, 400);
    const tooltip = Size(120, 32);

    test('bottom-region controls keep the tooltip 8px above', () {
      const context = TooltipPositionContext(
        target: Offset(300, 250),
        targetSize: Size(40, 40),
        tooltipSize: tooltip,
        verticalOffset: 8,
        overlaySize: overlay,
      );

      final result = desktopControlTooltipPosition(context);
      expect(result, const Offset(240, 190));
      expect(
        context.target.dy -
            context.targetSize.height / 2 -
            result.dy -
            tooltip.height,
        8,
      );
    });

    test('top-region controls keep the tooltip 8px below', () {
      const context = TooltipPositionContext(
        target: Offset(300, 70),
        targetSize: Size(40, 40),
        tooltipSize: tooltip,
        verticalOffset: 8,
        overlaySize: overlay,
      );

      final result = desktopControlTooltipPosition(
        context,
        placement: ControlTooltipPlacement.below,
      );
      expect(result, const Offset(240, 98));
      expect(
        result.dy - (context.target.dy + context.targetSize.height / 2),
        8,
      );
    });

    test('above placement preserves its side and 8px gap at the top edge', () {
      const context = TooltipPositionContext(
        target: Offset(300, 12),
        targetSize: Size(32, 32),
        tooltipSize: Size(120, 30),
        verticalOffset: 8,
        overlaySize: Size(600, 400),
      );

      final result = desktopControlTooltipPosition(context);
      expect(result.dy, -42);
      expect(
        context.target.dy -
            context.targetSize.height / 2 -
            result.dy -
            context.tooltipSize.height,
        8,
      );
      expect(
        result.dy + context.tooltipSize.height,
        lessThan(context.target.dy),
      );
    });

    test(
      'below placement preserves its side and 8px gap at the bottom edge',
      () {
        const context = TooltipPositionContext(
          target: Offset(300, 392),
          targetSize: Size(32, 32),
          tooltipSize: Size(120, 30),
          verticalOffset: 8,
          overlaySize: Size(600, 400),
        );

        final result = desktopControlTooltipPosition(
          context,
          placement: ControlTooltipPlacement.below,
        );
        expect(result.dy, 416);
        expect(
          result.dy - (context.target.dy + context.targetSize.height / 2),
          8,
        );
        expect(result.dy, greaterThan(context.target.dy));
      },
    );

    test('clamps the whole tooltip inside both horizontal edges', () {
      const left = TooltipPositionContext(
        target: Offset(10, 150),
        targetSize: Size(20, 20),
        tooltipSize: Size(100, 30),
        verticalOffset: 8,
        overlaySize: Size(600, 400),
      );
      const right = TooltipPositionContext(
        target: Offset(590, 150),
        targetSize: Size(20, 20),
        tooltipSize: Size(100, 30),
        verticalOffset: 8,
        overlaySize: Size(600, 400),
      );

      expect(desktopControlTooltipPosition(left).dx, 8);
      expect(desktopControlTooltipPosition(right).dx, 492);
    });
  });

  testWidgets('minimum trigger size does not shrink a larger control', (
    tester,
  ) async {
    const childKey = Key('large-tooltip-child');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ControlTooltip(
              message: 'Open',
              hitboxSize: 32,
              child: SizedBox(
                key: childKey,
                width: 48,
                height: 48,
                child: Icon(Icons.open_in_new),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(Tooltip)), const Size(48, 48));
    expect(tester.getSize(find.byKey(childKey)), const Size(48, 48));
  });

  test('touch platforms keep the wrapper message for native long press', () {
    final previous = foundation.debugDefaultTargetPlatformOverride;
    foundation.debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => foundation.debugDefaultTargetPlatformOverride = previous);

    final widget = ControlTooltip(
      message: 'Translate',
      child: const Icon(Icons.translate),
    );
    expect(ControlTooltip.nativeTooltip('Translate'), isNull);
    final tooltip = widget.build(_TestBuildContext()) as Tooltip;
    expect(tooltip.message, 'Translate');
    expect(tooltip.preferBelow, isNull);
    expect(tooltip.positionDelegate, isNull);
  });

  test('desktop platform gets region-specific placement delegate', () {
    final previous = foundation.debugDefaultTargetPlatformOverride;
    foundation.debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => foundation.debugDefaultTargetPlatformOverride = previous);

    final widget = ControlTooltip(
      message: 'Back',
      placement: ControlTooltipPlacement.below,
      child: const Icon(Icons.arrow_back),
    );
    final tooltip = widget.build(_TestBuildContext()) as Tooltip;
    expect(tooltip.preferBelow, isTrue);
    expect(tooltip.verticalOffset, ControlTooltip.gap);
    expect(tooltip.positionDelegate, isNotNull);
  });
}

/// A minimal context for checking the wrapper's public Tooltip configuration.
class _TestBuildContext extends Fake implements BuildContext {}
