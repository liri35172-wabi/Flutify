import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/md3e_shapes.dart';
import '../../../../l10n/l10n.dart';
import '../../../../providers/connect_provider.dart';
import '../../../../providers/playback_provider.dart';
import '../../../widgets/connect/connect_actions.dart';
import '../../../widgets/cover_image.dart';

/// 全屏播放器的大封面：左右拖动切歌（远程模式下发给远程设备）。
///
/// - 拖动时封面跟手平移并轻微旋转、变淡；
/// - 松手时位移超过封面宽度的 25% 或甩动速度 > 500 即切到下一首（左滑）/ 上一首（右滑），
///   否则回弹；
/// - 新封面淡入 + 轻微放大。
class SwipeableArtwork extends StatefulWidget {
  final String url;
  final double size;
  final String? trackKey;
  final Widget? child;

  const SwipeableArtwork({
    super.key,
    required this.url,
    required this.size,
    this.trackKey,
    this.child,
  });

  @override
  State<SwipeableArtwork> createState() => _SwipeableArtworkState();
}

class _SwipeableArtworkState extends State<SwipeableArtwork> {
  double _dx = 0;
  bool _dragging = false;
  bool _ignoreCurrentDrag = false;

  @override
  void didUpdateWidget(covariant SwipeableArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.trackKey != widget.trackKey) {
      _ignoreCurrentDrag = _dragging;
      _dx = 0;
      _dragging = false;
    }
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_ignoreCurrentDrag) return;
    setState(
      () => _dx = (_dx + details.delta.dx).clamp(-widget.size, widget.size),
    );
  }

  void _onEnd(DragEndDetails details) {
    if (_ignoreCurrentDrag) {
      _ignoreCurrentDrag = false;
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final threshold = widget.size * 0.25;
    final next = _dx < -threshold || velocity < -500;
    final previous = _dx > threshold || velocity > 500;

    if (ConnectActions.isRemoteNow(context)) {
      // 远程模式：切歌发给正在使用的远程设备
      final connect = context.read<ConnectProvider>();
      if (next) {
        ConnectActions.run(context, connect.skipNext);
      } else if (previous) {
        ConnectActions.run(context, connect.skipPrevious);
      }
    } else {
      final playback = context.read<PlaybackProvider>();
      if (next) {
        playback.nextTrack();
      } else if (previous) {
        playback.previousTrack();
      }
    }
    setState(() {
      _dragging = false;
      _dx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    if (!size.isFinite || size <= 0) return const SizedBox.shrink();
    return Semantics(
      hint: context.l10n.playerSwipeHint,
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() {
          _ignoreCurrentDrag = false;
          _dragging = true;
        }),
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        onHorizontalDragCancel: () => setState(() {
          _dragging = false;
          _dx = 0;
        }),
        child: TweenAnimationBuilder<double>(
          key: ValueKey((widget.trackKey, widget.url)),
          tween: Tween(end: _dx),
          // 拖动中直接跟手；松手后以回弹曲线归位
          duration: _dragging
              ? Duration.zero
              : const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (context, dx, child) {
            final progress = (dx.abs() / size).clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Transform.rotate(
                angle: dx / size * 0.06,
                child: Opacity(opacity: 1 - progress * 0.5, child: child),
              ),
            );
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: MD3EShapes.roundedExtraLarge,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child:
                  widget.child ??
                  CoverImage(
                    key: ValueKey(widget.url),
                    url: widget.url,
                    size: size,
                    borderRadius: MD3EShapes.roundedExtraLarge,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
