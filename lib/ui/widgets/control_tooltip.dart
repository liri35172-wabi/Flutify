import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared tooltip placement for player controls.
///
/// Desktop tooltips use a small, consistent gap above the trigger. Near the top
/// edge they flip below, with extra cursor clearance; touch platforms keep
/// Material's usual placement.
class ControlTooltip extends StatelessWidget {
  final String message;
  final Widget child;

  const ControlTooltip({super.key, required this.message, required this.child});

  static bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  /// Keep Material tooltips on touch platforms; desktop uses the offset overlay.
  static String? nativeTooltip(String? message) => _desktop ? null : message;

  @override
  Widget build(BuildContext context) {
    if (!_desktop) return child;
    return Tooltip(
      message: message,
      preferBelow: false,
      verticalOffset: 8,
      positionDelegate: desktopControlTooltipPosition,
      child: child,
    );
  }
}

/// Position a desktop tooltip relative to its full trigger bounds.
///
/// A short gap keeps labels close to the trigger without placing them under the
/// pointer hotspot. Near the top edge, the fallback leaves more room for the
/// hand cursor below its hotspot. Clamping keeps labels inside the overlay.
Offset desktopControlTooltipPosition(TooltipPositionContext context) {
  const edgeInset = 8.0;
  const aboveGap = 8.0;
  const belowCursorGap = 20.0;
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
  final height = overlay.height.isFinite && overlay.height > 0
      ? overlay.height
      : double.infinity;
  final maxX = math.max(edgeInset, width - tooltip.width - edgeInset);
  final x = (context.target.dx - tooltip.width / 2).clamp(edgeInset, maxX);

  final above = target.top - aboveGap - tooltip.height;
  final below = target.bottom + belowCursorGap;
  final fitsAbove = above >= edgeInset;
  final fitsBelow = below + tooltip.height <= height - edgeInset;
  final double y;
  if (fitsAbove) {
    y = above;
  } else if (fitsBelow) {
    y = below;
  } else if (target.top - edgeInset >= height - target.bottom - edgeInset) {
    y = (target.top - aboveGap - tooltip.height).clamp(
      edgeInset,
      math.max(edgeInset, height - tooltip.height - edgeInset),
    );
  } else {
    y = (target.bottom + belowCursorGap).clamp(
      edgeInset,
      math.max(edgeInset, height - tooltip.height - edgeInset),
    );
  }
  return Offset(x.toDouble(), y.toDouble());
}
