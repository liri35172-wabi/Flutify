import 'package:flutify_app/ui/screens/player/lyrics/lyric_ticker_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'short cues keep a readable lead-in instead of a rushed micro-scroll',
    () {
      final plan = LyricTickerPlan.create(
        overflow: 400,
        remainingCue: const Duration(milliseconds: 600),
      );

      expect(plan.moves, isFalse);
      expect(plan.leadIn, const Duration(milliseconds: 300));
      expect(plan.motion, Duration.zero);
      expect(plan.endRest, const Duration(milliseconds: 300));
    },
  );

  test('short-but-usable cue gets a slow bounded reveal and end rest', () {
    final plan = LyricTickerPlan.create(
      overflow: 400,
      remainingCue: const Duration(milliseconds: 800),
    );

    expect(plan.moves, isTrue);
    expect(plan.leadIn, const Duration(milliseconds: 300));
    expect(plan.motion, const Duration(milliseconds: 260));
    expect(plan.distance, closeTo(82 * .260, .01));
    expect(plan.endRest, const Duration(milliseconds: 240));
    expect(
      plan.leadIn + plan.motion + plan.endRest,
      const Duration(milliseconds: 800),
    );
  });

  test('long cue allows a longer reveal but preserves both resting beats', () {
    final plan = LyricTickerPlan.create(
      overflow: 900,
      remainingCue: const Duration(milliseconds: 3200),
    );

    expect(plan.moves, isTrue);
    expect(plan.leadIn, const Duration(milliseconds: 650));
    expect(
      plan.endRest,
      greaterThanOrEqualTo(const Duration(milliseconds: 576)),
    );
    expect(plan.motion, lessThan(const Duration(milliseconds: 2000)));
    expect(plan.distance, lessThan(900));
    expect(
      plan.distance / plan.motion.inMilliseconds * 1000,
      lessThanOrEqualTo(LyricTickerPlan.maxAverageSpeed + .1),
    );
    expect(
      plan.leadIn + plan.motion + plan.endRest,
      const Duration(milliseconds: 3200),
    );
  });

  test(
    'unbounded preview keeps its slower one-pass pace and opening pause',
    () {
      final plan = LyricTickerPlan.create(overflow: 320, remainingCue: null);

      expect(plan.leadIn, const Duration(milliseconds: 500));
      expect(plan.distance, 320);
      expect(plan.motion, const Duration(milliseconds: 5000));
      expect(plan.endRest, Duration.zero);
    },
  );

  test('no overflow creates no ticker motion', () {
    final plan = LyricTickerPlan.create(
      overflow: 0,
      remainingCue: const Duration(seconds: 3),
    );

    expect(plan.moves, isFalse);
    expect(plan.distance, 0);
    expect(plan.motion, Duration.zero);
  });
}
