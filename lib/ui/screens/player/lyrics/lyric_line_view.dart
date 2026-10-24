import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/debug_toggles.dart';
import '../../../../core/theme/flutify_tokens.dart';
import 'apple_music_motion.dart';
import 'lyric_ticker_plan.dart';

/// 单行歌词（Apple Music iOS 风格）。
///
/// 视觉规则由 [distance]（与当前行的行距，负数为已唱过）决定：
/// - 当前行：纯白、不模糊、原始大小；
/// - 其余行：透明度逐行降低，模糊半径逐行增大（上限 [_maxBlur]），略微缩小；
/// - [focusAll] 为 true（用户正在手动浏览 / 非同步歌词）时全部清晰，方便阅读。
///
/// 所有参数通过 TweenAnimationBuilder 平滑过渡，行切换时呈现"对焦"动画。
class LyricLineView extends StatelessWidget {
  final String text;

  /// 译文（双语歌词）：非空时以小字显示在原文下方。
  final String? translation;
  final double translationProgress;
  final int distance;
  final bool focusAll;
  final VoidCallback? onTap;

  /// 可跳转时显示的鼠标指针；沉浸式歌词传 [MouseCursor.defer]，交给外层控制隐藏光标。
  final MouseCursor cursor;

  /// 字号；行距随字号等比放大。
  final double fontSize;

  /// 居中对齐时文字居中、缩放以中心为基准；默认左对齐（Apple Music）。
  final bool centered;

  final bool appleMusicStyle;

  /// Moves only the focused phone lyric left once when it exceeds the available width.
  /// The full-view vertical lyric list and other rows remain unchanged.
  final bool horizontalTicker;

  /// For synchronized lyrics, the line's remaining display window. The active
  /// ticker uses this to reveal the tail before the next timestamp arrives.
  final Duration? tickerDuration;

  const LyricLineView({
    super.key,
    required this.text,
    this.translation,
    this.translationProgress = 1,
    required this.distance,
    this.focusAll = false,
    this.onTap,
    this.cursor = MouseCursor.defer,
    this.fontSize = 30,
    this.centered = false,
    this.appleMusicStyle = false,
    this.horizontalTicker = false,
    this.tickerDuration,
  });

  static const double _maxBlur = 3.5;
  static const Duration _duration = Duration(milliseconds: 520);

  @override
  Widget build(BuildContext context) {
    final d = distance.abs();
    final isActive = distance == 0;

    // 相邻句 1.0、隔一句 2.0 …… 上限 3.5：近处可辨认，远处退为氛围
    final blur = appleMusicStyle || focusAll || isActive
        ? 0.0
        : d.toDouble().clamp(0.0, _maxBlur);
    final opacity = appleMusicStyle
        ? (focusAll || isActive ? .94 : .18)
        : focusAll
        ? (isActive ? 1.0 : 0.62)
        : isActive
        ? 1.0
        : (0.52 - d * 0.06).clamp(0.2, 0.46);
    final scale = isActive || (appleMusicStyle && focusAll)
        ? 1.0
        : appleMusicStyle
        ? .98
        : .965;
    final duration = appleMusicStyle
        ? Duration(milliseconds: isActive ? 500 : 600)
        : _duration;

    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: appleMusicStyle
              ? const EdgeInsets.only(top: 2, bottom: 30)
              : EdgeInsets.symmetric(vertical: fontSize * 0.4),
          child: TweenAnimationBuilder<_LineVisual>(
            tween: _LineVisualTween(end: _LineVisual(blur, opacity, scale)),
            duration:
                DebugToggles.of(context).isOff(DebugToggle.lyricsLineMotion)
                ? Duration.zero
                : context.motion(duration),
            curve: appleMusicStyle
                ? Interval(
                    250 / duration.inMilliseconds,
                    1,
                    curve: AppleMusicMotion.focusCurve,
                  )
                : const Cubic(0.22, 1.0, 0.36, 1.0),
            builder: (context, v, _) {
              // 透明度直接写进文字颜色，省去 Opacity 的离屏图层
              Widget result = _LineText(
                text: text,
                translation: translation,
                translationProgress: translationProgress,
                opacity: v.opacity,
                fontSize: fontSize,
                centered: centered,
                horizontalTicker: horizontalTicker && isActive,
                tickerDuration: tickerDuration,
                tickerMotionEnabled:
                    !MediaQuery.disableAnimationsOf(context) &&
                    !DebugToggles.of(
                      context,
                    ).isOff(DebugToggle.lyricsLineMotion),
              );
              // ImageFiltered 始终留在树里，sigma 过小时只关掉 enabled（同样不产生离屏层）。
              // 之前按阈值增删这一层，每次对焦动画收尾都会让整行文字卸载重建、
              // 并在「离屏渲染 ↔ 直接绘制」之间跳变一帧，肉眼就是歌词闪一下。
              if (!appleMusicStyle) {
                result = ImageFiltered(
                  enabled: v.blur > 0.05,
                  imageFilter: ImageFilter.blur(sigmaX: v.blur, sigmaY: v.blur),
                  child: result,
                );
              }
              return RepaintBoundary(
                child: Transform.scale(
                  scale: v.scale,
                  alignment: centered
                      ? Alignment.center
                      : appleMusicStyle
                      ? (Directionality.of(context) == TextDirection.rtl
                            ? Alignment.bottomRight
                            : Alignment.bottomLeft)
                      : Alignment.centerLeft,
                  child: result,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 歌词文字；空行（间奏）显示三个圆点。译文（[translation] 非空且不是间奏时）
/// 以约六成字号附在原文下方，随原文一起模糊 / 淡出。
class _LineText extends StatelessWidget {
  final String text;
  final String? translation;
  final double translationProgress;
  final double opacity;
  final double fontSize;
  final bool centered;
  final bool horizontalTicker;
  final Duration? tickerDuration;
  final bool tickerMotionEnabled;

  const _LineText({
    required this.text,
    this.translation,
    required this.translationProgress,
    required this.opacity,
    required this.fontSize,
    required this.centered,
    required this.horizontalTicker,
    required this.tickerDuration,
    required this.tickerMotionEnabled,
  });

  static const Color _translationGray = Color(0xFFC4CAD4);

  @override
  Widget build(BuildContext context) {
    final isInterlude = text.trim().isEmpty || text.trim() == '♪';
    final trans = isInterlude ? null : translation?.trim();
    final progress = trans == null || trans.isEmpty
        ? 0.0
        : translationProgress.clamp(0.0, 1.0);
    Widget mainText() => Builder(
      builder: (context) {
        final style = TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: opacity),
          // 中文歌词：字距只轻微收紧，行高放宽并上下均分，多行时汉字不挤、不裁切
          letterSpacing: -0.2,
          height: 1.3,
          leadingDistribution: TextLeadingDistribution.even,
        );
        final displayedText = isInterlude ? '•  •  •' : text;
        if (horizontalTicker && !isInterlude) {
          return OnePassLyricTicker(
            text: displayedText,
            style: style,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            motionEnabled: tickerMotionEnabled,
            duration: tickerDuration,
          );
        }
        return Text(
          displayedText,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: style,
        );
      },
    );
    return Transform.translate(
      offset: Offset(0, -fontSize * 0.3 * progress),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (horizontalTicker && constraints.maxHeight.isFinite)
                Flexible(fit: FlexFit.loose, child: mainText())
              else
                mainText(),
              if (progress > 0)
                Align(
                  alignment: centered ? Alignment.topCenter : Alignment.topLeft,
                  heightFactor: progress,
                  child: Padding(
                    padding: EdgeInsets.only(top: fontSize * 0.18),
                    child: Transform.translate(
                      offset: Offset(0, fontSize * 0.18 * (1 - progress)),
                      child: Text(
                        trans!,
                        textAlign: centered
                            ? TextAlign.center
                            : TextAlign.start,
                        style: TextStyle(
                          fontSize: fontSize * 0.56,
                          fontWeight: FontWeight.w600,
                          // 译文偏灰：冷灰色 + 更低透明度，与纯白原文拉开层次
                          color: _translationGray.withValues(
                            alpha: opacity * 0.62 * progress,
                          ),
                          letterSpacing: -0.1,
                          height: 1.25,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single leftward pass for the active phone lyric; it never loops or reverses.
///
/// The native Flyme notification ticker is a separate OS-owned surface and is untouched.
class OnePassLyricTicker extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final bool motionEnabled;
  final Duration? duration;
  final Duration startDelay;

  const OnePassLyricTicker({
    super.key,
    required this.text,
    required this.style,
    required this.textAlign,
    this.motionEnabled = true,
    this.duration,
    this.startDelay = const Duration(milliseconds: 350),
  });

  @override
  State<OnePassLyricTicker> createState() => _OnePassLyricTickerState();
}

class _OnePassLyricTickerState extends State<OnePassLyricTicker> {
  final ScrollController _scroll = ScrollController();
  Timer? _delay;
  bool _started = false;
  double? _scheduledExtent;

  @override
  void didUpdateWidget(covariant OnePassLyricTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        !_sameTextMetrics(oldWidget.style, widget.style) ||
        oldWidget.motionEnabled != widget.motionEnabled) {
      _resetPass();
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _resetPass() {
    _delay?.cancel();
    _started = false;
    _scheduledExtent = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  bool _sameTextMetrics(TextStyle a, TextStyle b) =>
      a.fontFamily == b.fontFamily &&
      a.fontFamilyFallback == b.fontFamilyFallback &&
      a.fontSize == b.fontSize &&
      a.fontWeight == b.fontWeight &&
      a.fontStyle == b.fontStyle &&
      a.letterSpacing == b.letterSpacing &&
      a.wordSpacing == b.wordSpacing &&
      a.textBaseline == b.textBaseline &&
      a.height == b.height &&
      a.leadingDistribution == b.leadingDistribution &&
      a.fontFeatures == b.fontFeatures &&
      a.fontVariations == b.fontVariations;

  bool _onMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.horizontal || metrics.maxScrollExtent <= 1) {
      _scheduledExtent = null;
      return false;
    }
    final extent = metrics.maxScrollExtent;
    if (!widget.motionEnabled || _started || _scheduledExtent == extent) {
      return false;
    }
    _scheduledExtent = extent;
    _delay?.cancel();
    final plan = LyricTickerPlan.create(
      overflow: extent,
      remainingCue: widget.duration,
      unboundedLeadIn: widget.startDelay,
    );
    if (!plan.moves) {
      _started = true;
      return false;
    }
    _delay = Timer(plan.leadIn, () {
      if (!mounted || !_scroll.hasClients) return;
      final maxExtent = _scroll.position.maxScrollExtent;
      final distance = math.min(plan.distance, maxExtent);
      if (distance <= 1) return;
      _started = true;
      _scroll.animateTo(
        distance.toDouble(),
        duration: plan.motion,
        curve: Curves.easeInOutSine,
      );
    });
    return false;
  }

  bool? _lastNeedsTicker;

  void _noteOverflowState(bool needsTicker) {
    if (_lastNeedsTicker != null && _lastNeedsTicker != needsTicker) {
      _delay?.cancel();
      _started = false;
      _scheduledExtent = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    _lastNeedsTicker = needsTicker;
  }

  Widget _lineText() => Text(
    widget.text,
    maxLines: 1,
    softWrap: false,
    textAlign: widget.textAlign,
    overflow: TextOverflow.clip,
    style: widget.style,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final effectiveStyle = DefaultTextStyle.of(
        context,
      ).style.merge(widget.style);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: effectiveStyle),
        textAlign: widget.textAlign,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final needsTicker =
          constraints.maxWidth.isFinite &&
          painter.width > constraints.maxWidth + 0.5;
      painter.dispose();
      _noteOverflowState(needsTicker);
      if (!needsTicker) {
        _delay?.cancel();
        _scheduledExtent = null;
        return _lineText();
      }
      final wrappedPainter =
          TextPainter(
            text: TextSpan(text: widget.text, style: effectiveStyle),
            textAlign: widget.textAlign,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout(
            maxWidth: constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : painter.width,
          );
      final preservedHeight = wrappedPainter.height;
      wrappedPainter.dispose();
      return SizedBox(
        width: double.infinity,
        height: preservedHeight,
        child: Align(
          alignment: widget.textAlign == TextAlign.center
              ? Alignment.topCenter
              : AlignmentDirectional.topStart,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              clipBehavior: Clip.hardEdge,
              child: _lineText(),
            ),
          ),
        ),
      );
    },
  );
}

/// 动画插值所需的三元组。
@immutable
class _LineVisual {
  final double blur;
  final double opacity;
  final double scale;

  const _LineVisual(this.blur, this.opacity, this.scale);

  // 已经到达模糊/透明度上限的远处歌词无需每次切行重启动画。
  @override
  bool operator ==(Object other) =>
      other is _LineVisual &&
      other.blur == blur &&
      other.opacity == opacity &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(blur, opacity, scale);
}

class _LineVisualTween extends Tween<_LineVisual> {
  _LineVisualTween({required _LineVisual end}) : super(begin: end, end: end);

  @override
  _LineVisual lerp(double t) {
    final a = begin!, b = end!;
    return _LineVisual(
      lerpDouble(a.blur, b.blur, t)!,
      lerpDouble(a.opacity, b.opacity, t)!,
      lerpDouble(a.scale, b.scale, t)!,
    );
  }
}
