import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/debug_toggles.dart';
import '../../../../core/theme/flutify_tokens.dart';
import '../../../shell/desktop/desktop_window.dart';
import '../../../widgets/liquid_artwork_background.dart';
import '../../../widgets/apple_music_background.dart';

/// 所有歌词界面共用的液态背景：封面流动模糊 + 压暗层。
///
/// 全屏歌词、全屏播放器的歌词视图、桌面右栏歌词、沉浸式歌词都使用它，观感一致。
/// 与 Android 原生背景一致：暂停时背景仍缓慢流动；仅在「减弱动效」或省电模式下停止流动。
class LyricsBackdrop extends StatelessWidget {
  final String imageUrl;
  final bool reducedEffects;

  const LyricsBackdrop({
    super.key,
    required this.imageUrl,
    this.reducedEffects = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AppleMusicBackground(
        imageUrl: imageUrl,
        reducedEffects: reducedEffects,
      );
    }
    // 非歌词视图（封面/队列）只显示静态模糊封面，与 Android 的 reducedEffects 一致，
    // 切到歌词时再恢复流动，避免在 Windows 上整个播放器持续重绘。
    final animate =
        !context.reduceMotion &&
        !context.tokens.powerSaving &&
        !reducedEffects &&
        !DebugToggles.of(context).isOff(DebugToggle.flowingBackground);
    // 与 Android 原生背景同一配方：黑底、同样的旋转/饱和度/压暗/模糊。
    // Windows 调整原生窗口尺寸期间暂停 30fps 封面相位更新，避免把连续背景重绘
    // 叠加到系统全屏过渡上；窗口稳定后由原有相位继续，不改系统窗口切换顺序。
    final dark = Theme.of(context).brightness == Brightness.dark;
    final desktop =
        !kIsWeb &&
        switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux => true,
          _ => false,
        };
    if (!desktop) {
      return LiquidArtworkBackground(
        imageUrl: imageUrl,
        animate: animate,
        dark: dark,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopWindow.fullscreenTransition,
      builder: (context, transitioning, _) => LiquidArtworkBackground(
        imageUrl: imageUrl,
        animate: animate && !transitioning,
        dark: dark,
      ),
    );
  }
}
