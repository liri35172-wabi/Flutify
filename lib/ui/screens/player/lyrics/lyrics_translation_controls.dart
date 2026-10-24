import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../providers/spotify_provider.dart';
import '../../../../services/lyrics/lyrics_translation.dart';
import '../../../widgets/control_tooltip.dart';
import 'glass_icon_button.dart';

/// A lyrics surface and its toolbar share one lookup and cancellation state.
class LyricsTranslationScope extends StatelessWidget {
  final Widget child;

  const LyricsTranslationScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<LyricsTranslationController>(
        create: (context) => LyricsTranslationController(
          lookup: context.read<SpotifyProvider>().fetchLyricsTranslation,
        ),
        child: child,
      );
}

class LyricsTranslationButton extends StatelessWidget {
  final double size;
  final bool glass;

  const LyricsTranslationButton({super.key, this.size = 48, this.glass = true});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LyricsTranslationController>();
    final l10n = context.l10n;
    final active = controller.lines != null || controller.busy;
    final label = controller.busy
        ? l10n.lyricsTranslating
        : controller.lines != null
        ? l10n.lyricsCancelTranslation
        : controller.failed
        ? l10n.lyricsTranslationFailed
        : controller.unavailable
        ? l10n.lyricsTranslationUnavailable
        : l10n.lyricsTranslate;
    return GlassIconButton(
      icon: Icons.translate_rounded,
      tooltip: label,
      size: size,
      glass: glass,
      selected: active,
      onPressed: !controller.available
          ? null
          : active
          ? controller.cancel
          : controller.translate,
    );
  }
}

/// 与播放器底栏的「歌词 / 队列」切换同一风格的翻译开关（图标 + 激活小圆点），
/// 用在控制卡片的底栏里，不再是浮在歌词旁的白色圆形按钮。
class LyricsTranslationToggle extends StatelessWidget {
  const LyricsTranslationToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LyricsTranslationController>();
    final l10n = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;
    final active = controller.lines != null || controller.busy;
    final label = controller.busy
        ? l10n.lyricsTranslating
        : controller.lines != null
        ? l10n.lyricsCancelTranslation
        : controller.failed
        ? l10n.lyricsTranslationFailed
        : controller.unavailable
        ? l10n.lyricsTranslationUnavailable
        : l10n.lyricsTranslate;
    return ControlTooltip(
      message: label,
      child: IconButton(
        tooltip: ControlTooltip.nativeTooltip(label),
        isSelected: active,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        onPressed: !controller.available
            ? null
            : active
            ? controller.cancel
            : controller.translate,
        // State is communicated by accent colour alone; no dot beneath the icon.
        icon: Icon(
          Icons.translate_rounded,
          color: active
              ? primary
              : controller.available
              ? Colors.white70
              : Colors.white24,
          size: 22,
        ),
      ),
    );
  }
}
