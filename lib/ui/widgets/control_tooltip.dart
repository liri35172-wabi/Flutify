import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The UI region determines which side of its trigger a desktop tooltip uses.
enum ControlTooltipPlacement { above, below }

/// Shared placement and spacing for application tooltips.
///
/// Desktop tooltips stay on the requested side with an 8 logical-pixel gap.
/// Horizontal alignment is clamped to the overlay; if a vertical edge leaves
/// too little room, the tooltip keeps its side and gap rather than crossing
/// the trigger. Touch platforms retain Flutter's native long-press behavior.
class ControlTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  final ControlTooltipPlacement placement;
  final Duration? waitDuration;

  /// Minimum side length of the centered trigger; never shrinks [child].
  final double? hitboxSize;

  const ControlTooltip({
    super.key,
    required this.message,
    required this.child,
    this.placement = ControlTooltipPlacement.above,
    this.waitDuration,
    this.hitboxSize,
  });

  static const double gap = 8;

  static bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  /// Prevents nested button-owned tooltips when this wrapper owns the tooltip.
  static String? nativeTooltip(String? message) => null;

  @override
  Widget build(BuildContext context) {
    final target = hitboxSize == null
        ? child
        : ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: hitboxSize!,
              minHeight: hitboxSize!,
            ),
            child: Center(widthFactor: 1, heightFactor: 1, child: child),
          );
    return Tooltip(
      message: message,
      waitDuration: waitDuration,
      preferBelow: _desktop ? placement == ControlTooltipPlacement.below : null,
      verticalOffset: _desktop ? gap : null,
      positionDelegate: _desktop
          ? (position) =>
                desktopControlTooltipPosition(position, placement: placement)
          : null,
      child: target,
    );
  }
}

/// Position a desktop tooltip on its designated side of the full trigger bounds.
///
/// Horizontal alignment is centered and clamped to the overlay. Vertical
/// placement always preserves the requested side and gap. If there is not
/// enough vertical room, part of the tooltip may extend beyond the overlay
/// rather than overlapping or crossing the trigger.
Offset desktopControlTooltipPosition(
  TooltipPositionContext context, {
  ControlTooltipPlacement placement = ControlTooltipPlacement.above,
}) {
  const edgeInset = 8.0;
  const gap = ControlTooltip.gap;
  final overlay = context.overlaySize;
  final tooltip = context.tooltipSize;
  final target = Rect.fromCenter(
    center: context.target,
    width: context.targetSize.width,
    height: context.targetSize.height,
  );

  final width = overlay.width.isFinite && overlay.width > 0
      ? overlay.width
      : math.max(context.target.dx + tooltip.width / 2, tooltip.width);
  final maxX = math.max(edgeInset, width - tooltip.width - edgeInset);
  final x = (context.target.dx - tooltip.width / 2).clamp(edgeInset, maxX);

  final desiredY = switch (placement) {
    ControlTooltipPlacement.above => target.top - gap - tooltip.height,
    ControlTooltipPlacement.below => target.bottom + gap,
  };
  return Offset(x.toDouble(), desiredY.toDouble());
}
