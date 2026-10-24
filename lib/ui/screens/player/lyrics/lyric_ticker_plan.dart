import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// A one-pass ticker schedule constrained by the active lyric's remaining cue.
///
/// A readable opening and an unhurried, smooth pass take priority over exposing
/// every last pixel. Any time left after the pass is a deliberate end rest.
class LyricTickerPlan {
  const LyricTickerPlan({
    required this.leadIn,
    required this.motion,
    required this.distance,
    required this.endRest,
    this.lateAcceleration = false,
  });

  final Duration leadIn;
  final Duration motion;
  final double distance;
  final Duration endRest;
  final bool lateAcceleration;

  /// Match the Android overlay's late-biased curve only for long overflow.
  Curve get motionCurve =>
      lateAcceleration ? longLyricMotionCurve : Curves.easeInOutSine;

  bool get moves => distance > 1 && motion > Duration.zero;

  /// Maximum average logical-pixel speed for time-bounded lyric movement.
  /// The sine easing has a gentler start/stop than a linear ticker.
  static const double maxAverageSpeed = 82;
  static const int minimumLeadInMs = 300;
  static const int maximumLeadInMs = 650;
  static const int minimumEndRestMs = 240;
  static const int maximumEndRestMs = 600;
  static const int minimumMotionBudgetMs = 200;
  static const double minimumDistance = 16;
  static const double lateAccelerationThreshold = 260;
  // A right-biased, non-rebounding cubic lets long lyrics spend more of the
  // latter half revealing text, then eases to a zero-velocity stop.
  static const Curve longLyricMotionCurve = Cubic(0.55, 0, 0.85, 1);

  static LyricTickerPlan create({
    required double overflow,
    required Duration? remainingCue,
    Duration unboundedLeadIn = const Duration(milliseconds: 500),
  }) {
    if (remainingCue == null) {
      final distance = math.max(0.0, overflow);
      final motion = distance <= 1
          ? Duration.zero
          : Duration(milliseconds: (distance / 64 * 1000).round());
      return LyricTickerPlan(
        leadIn: unboundedLeadIn,
        motion: motion,
        distance: distance,
        endRest: Duration.zero,
        lateAcceleration: distance >= lateAccelerationThreshold,
      );
    }

    final cueMs = math.max(0, remainingCue.inMilliseconds);
    final leadMs = (cueMs * .24).round().clamp(
      minimumLeadInMs,
      maximumLeadInMs,
    );
    final endMs = (cueMs * .18).round().clamp(
      minimumEndRestMs,
      maximumEndRestMs,
    );
    final motionBudgetMs = cueMs - leadMs - endMs;
    if (motionBudgetMs < minimumMotionBudgetMs) {
      final actualLeadMs = math.min(leadMs, cueMs);
      return LyricTickerPlan(
        leadIn: Duration(milliseconds: actualLeadMs),
        motion: Duration.zero,
        distance: 0,
        endRest: Duration(milliseconds: cueMs - actualLeadMs),
        lateAcceleration: overflow >= lateAccelerationThreshold,
      );
    }

    final maxDistance = maxAverageSpeed * motionBudgetMs / 1000;
    final distance = math.min(math.max(0.0, overflow), maxDistance);
    if (distance < minimumDistance) {
      return LyricTickerPlan(
        leadIn: Duration(milliseconds: leadMs),
        motion: Duration.zero,
        distance: 0,
        endRest: Duration(milliseconds: cueMs - leadMs),
        lateAcceleration: overflow >= lateAccelerationThreshold,
      );
    }
    final motionMs = (distance / maxAverageSpeed * 1000).ceil();
    return LyricTickerPlan(
      leadIn: Duration(milliseconds: leadMs),
      motion: Duration(milliseconds: motionMs),
      distance: distance,
      endRest: Duration(milliseconds: math.max(0, cueMs - leadMs - motionMs)),
      lateAcceleration: overflow >= lateAccelerationThreshold,
    );
  }
}
