import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Shared Apple-style timing for the Android player's coordinated transitions.
abstract final class PlayerLyricsMotion {
  // Responsive takeoff with a long, gentle landing on entry.
  static const curve = Cubic(0.22, 0.8, 0.22, 1);
  // A restrained overshoot gives the return flight a spring-like settle rather
  // than making the controls disappear sooner on an otherwise linear path.
  static const artworkReturnCurve = Cubic(0.34, 1.38, 0.64, 1);
  static const duration = Duration(milliseconds: 640);
  static const artworkReturnDuration = Duration(milliseconds: 560);
  static const chromeDuration = Duration(milliseconds: 300);
  static const foldCurve = Cubic(0.32, 0.72, 0, 1);
  static const foldDuration = Duration(milliseconds: 420);
  static const idleDelay = Duration(milliseconds: 3500);
}

/// Apple Music 6.5.3's content transition timing, adapted to one shared flight.
abstract final class PlayerQueueMotion {
  static const curve = Cubic(0.25, 0.1, 0.25, 1);
  static const duration = Duration(milliseconds: 500);
  static const rise = 24.0;
}

/// UI-only motion and inactivity state; playback ticks must not call [activity].
class PlayerLyricsController extends ChangeNotifier {
  PlayerLyricsController({required TickerProvider vsync})
    : transition = AnimationController(vsync: vsync),
      queueTransition = AnimationController(vsync: vsync),
      chrome = AnimationController(vsync: vsync, value: 1) {
    transition.addListener(notifyListeners);
    queueTransition.addListener(notifyListeners);
    chrome.addListener(notifyListeners);
  }

  final AnimationController transition;
  final AnimationController queueTransition;
  final AnimationController chrome;
  final Map<int, Offset> _pointers = {};
  Timer? _timer;
  bool _lyrics = false;
  bool _queue = false;
  bool _foldQueueAfterEntry = false;
  bool _gestureStartedFolded = false;
  bool _idle = false;
  bool _active = true;
  bool _reduceMotion = false;
  bool _accessibleNavigation = false;
  bool _interactionSuspended = false;
  bool _pinned = false;
  bool _disposed = false;
  double? _artworkReturnStartValue;
  double? _artworkReturnStartProgress;
  double? _layoutRetargetStartValue;
  double? _layoutRetargetStartProgress;
  double? _layoutRetargetTarget;

  bool get controlsVisible => !_idle;
  double get lyricsProgress =>
      (transition.value - queueTransition.value).clamp(0.0, 1.0);

  double get _rawArtworkReturnProgress {
    final startValue = _artworkReturnStartValue;
    final startProgress = _artworkReturnStartProgress;
    if (startValue == null || startProgress == null || startValue <= 0) {
      return transition.value;
    }
    final t = ((startValue - transition.value) / startValue).clamp(0.0, 1.0);
    return startProgress *
        (1 - PlayerLyricsMotion.artworkReturnCurve.transform(t));
  }

  /// Geometry stays bounded while pane weights remain on the shared controller.
  /// A retarget maps the controller's remaining travel onto the visible layout
  /// so interrupting the spring does not introduce a handoff jump.
  double get layoutProgress {
    final startValue = _layoutRetargetStartValue;
    final startProgress = _layoutRetargetStartProgress;
    final target = _layoutRetargetTarget;
    if (startValue != null && startProgress != null && target != null) {
      final span = target - startValue;
      if (span.abs() < 0.000001) return target.clamp(0.0, 1.0);
      final t = ((transition.value - startValue) / span).clamp(0.0, 1.0);
      return (startProgress + (target - startProgress) * t).clamp(0.0, 1.0);
    }
    return _rawArtworkReturnProgress.clamp(0.0, 1.0);
  }

  /// Normalized amount of the return spring's overshoot, for a subtle visual
  /// settle that cannot create negative sizes or opacity values.
  double get artworkReturnBounce {
    if (_artworkReturnStartValue == null) return 0;
    return (-_rawArtworkReturnProgress / 0.05).clamp(0.0, 1.0);
  }

  double get layoutLyricsProgress =>
      (layoutProgress - queueTransition.value).clamp(0.0, 1.0);

  void configure({
    required bool reduceMotion,
    required bool accessibleNavigation,
  }) {
    if (_reduceMotion == reduceMotion &&
        _accessibleNavigation == accessibleNavigation) {
      return;
    }
    _reduceMotion = reduceMotion;
    _accessibleNavigation = accessibleNavigation;
    _gestureStartedFolded = false;
    if (reduceMotion) {
      _artworkReturnStartValue = null;
      _artworkReturnStartProgress = null;
      _layoutRetargetStartValue = null;
      _layoutRetargetStartProgress = null;
      _layoutRetargetTarget = null;
      transition.value = _lyrics || _queue ? 1 : 0;
      queueTransition.value = _queue ? 1 : 0;
      chrome.value = _idle ? 0 : 1;
    }
    if (accessibleNavigation) {
      activity();
    } else {
      _scheduleIdle();
    }
  }

  void setLyrics(bool value) => setView(lyrics: value, queue: false);

  void setView({required bool lyrics, required bool queue}) {
    assert(!lyrics || !queue);
    if (_lyrics == lyrics && _queue == queue) return;
    final queueFlight = queue || _queue;
    final returningToArtwork = _lyrics && !lyrics && !queue;
    final targetLayoutProgress = lyrics || queue ? 1.0 : 0.0;
    final visibleProgress = layoutProgress;
    if (returningToArtwork) {
      _layoutRetargetStartValue = null;
      _layoutRetargetStartProgress = null;
      _layoutRetargetTarget = null;
      _artworkReturnStartValue = transition.value;
      _artworkReturnStartProgress = visibleProgress;
    } else if (_artworkReturnStartValue != null ||
        _layoutRetargetStartValue != null) {
      // Keep the actual pane-weight controller untouched. Retarget just the
      // geometry from its current visible point toward the new destination.
      _artworkReturnStartValue = null;
      _artworkReturnStartProgress = null;
      _layoutRetargetStartValue = transition.value;
      _layoutRetargetStartProgress = visibleProgress;
      _layoutRetargetTarget = targetLayoutProgress;
    } else {
      _artworkReturnStartValue = null;
      _artworkReturnStartProgress = null;
      _layoutRetargetStartValue = null;
      _layoutRetargetStartProgress = null;
      _layoutRetargetTarget = null;
    }
    // Keep the pane-weight controller bounded and linear on return; only the
    // shared layout receives a restrained overshoot before settling at artwork.
    // A footer onTap changes views after pointer-down. Retain
    // that gesture's origin even with reduced motion, where chrome snaps to 1.
    // Another held finger cannot reopen the queue card either.
    final keepFolded =
        queue &&
        !_accessibleNavigation &&
        !_interactionSuspended &&
        (_idle || _gestureStartedFolded);
    _gestureStartedFolded = false;
    _lyrics = lyrics;
    _queue = queue;
    // An already-folded lyrics card stays folded when entering the queue.
    // Otherwise finish the shared-element flight before retracting the card.
    _foldQueueAfterEntry =
        queue &&
        !keepFolded &&
        _active &&
        !_accessibleNavigation &&
        !_interactionSuspended;
    _timer?.cancel();
    if (keepFolded) {
      _fold();
    } else {
      _reveal();
    }
    final duration = _reduceMotion
        ? Duration.zero
        : queueFlight
        ? PlayerQueueMotion.duration
        : returningToArtwork
        ? PlayerLyricsMotion.artworkReturnDuration
        : PlayerLyricsMotion.duration;
    final curve = queueFlight
        ? PlayerQueueMotion.curve
        : returningToArtwork
        ? Curves.linear
        : PlayerLyricsMotion.curve;
    // Easing the controller itself starts every reversal at its current value.
    // Switching between forward/reverse CurvedAnimations can otherwise jump.
    transition
        .animateTo(lyrics || queue ? 1 : 0, duration: duration, curve: curve)
        .whenCompleteOrCancel(() {
          if (!_disposed) _scheduleIdle();
        });
    // Retarget from both current values, even on a three-way interruption.
    // Equal timing keeps queue <= shared progress; the remainder is lyrics.
    queueTransition
        .animateTo(queue ? 1 : 0, duration: duration, curve: curve)
        .whenCompleteOrCancel(() {
          if (!_disposed) _scheduleIdle();
        });
    notifyListeners();
  }

  void _reveal() {
    if (!_idle) return;
    _idle = false;
    chrome.animateTo(
      1,
      duration: _reduceMotion
          ? Duration.zero
          : PlayerLyricsMotion.chromeDuration,
      curve: PlayerLyricsMotion.curve,
    );
    notifyListeners();
  }

  void activity() {
    _timer?.cancel();
    // Explicit interaction during entry takes precedence over automatic folding.
    _foldQueueAfterEntry = false;
    if (!_active) return;
    _reveal();
    _scheduleIdle();
  }

  /// Hover and wheel input; like touches, it cannot reopen a folded queue.
  void passiveActivity() => _queue ? _scheduleIdle() : activity();

  void pointerDown(int pointer) {
    if (_pointers.isEmpty) _gestureStartedFolded = _idle;
    _pointers[pointer] = Offset.zero;
    _touch();
  }

  void pointerMove(int pointer, Offset delta) {
    final previous = _pointers[pointer];
    if (previous == null) return;
    final reversing =
        (previous.dy < 0 && delta.dy > 0) || (previous.dy > 0 && delta.dy < 0);
    final movement = reversing ? delta : previous + delta;
    _pointers[pointer] = movement;
    if (_lyrics &&
        movement.dy.abs() > kTouchSlop &&
        movement.dy.abs() > movement.dx.abs()) {
      if (movement.dy < 0) {
        if (_active && !_accessibleNavigation && !_interactionSuspended) {
          _fold();
        }
      } else {
        activity();
      }
      return;
    }
    _touch();
  }

  void pointerUp(int pointer) {
    // Global release/cancel recovery also observes unrelated pointers.
    if (_pointers.remove(pointer) == null) return;
    _touch();
  }

  void _touch() {
    // Queue touches and scrolls only keep a visible card awake; a card tap
    // ([activity]) is the sole way to reopen it, and they do not cancel the
    // default fold after entry, which runs once every finger is released.
    if (_queue) {
      _scheduleIdle();
    } else if (!_lyrics || !_idle) {
      activity();
    }
  }

  /// 固定控制区：不再因静止或上滑而收起成底部小条。
  void setPinned(bool pinned) {
    if (_pinned == pinned) return;
    _pinned = pinned;
    if (pinned) {
      _timer?.cancel();
      _reveal();
    } else {
      _scheduleIdle();
    }
  }

  void setInteractionSuspended(bool suspended) {
    if (_interactionSuspended == suspended) return;
    _interactionSuspended = suspended;
    _gestureStartedFolded = false;
    activity();
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _timer?.cancel();
    _pointers.clear();
    _gestureStartedFolded = false;
    if (!active) return;
    // Returning to the queue keeps a folded card folded.
    if (_queue) {
      _scheduleIdle();
    } else {
      activity();
    }
  }

  void _scheduleIdle() {
    _timer?.cancel();
    if (!_active ||
        _pinned ||
        (!_lyrics && !_queue) ||
        _idle ||
        _accessibleNavigation ||
        _interactionSuspended ||
        _pointers.isNotEmpty ||
        transition.isAnimating ||
        queueTransition.isAnimating ||
        transition.value != 1 ||
        queueTransition.value != (_queue ? 1 : 0)) {
      return;
    }
    if (_foldQueueAfterEntry) {
      _foldQueueAfterEntry = false;
      _fold();
    } else {
      _timer = Timer(PlayerLyricsMotion.idleDelay, _fold);
    }
  }

  void _fold() {
    if (_idle || _pinned) return;
    _timer?.cancel();
    _idle = true;
    chrome.animateTo(
      0,
      duration: _reduceMotion ? Duration.zero : PlayerLyricsMotion.foldDuration,
      curve: PlayerLyricsMotion.foldCurve,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    transition.dispose();
    queueTransition.dispose();
    chrome.dispose();
    super.dispose();
  }
}
