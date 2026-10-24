import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/lyrics_source.dart';
import 'package:flutify_app/ui/widgets/control_tooltip.dart';

/// 歌词来源优先级：整行列表，拖动右侧手柄调整顺序（越靠前越优先）。
///
/// 辅助功能由 [ReorderableListView] 自带的「上移 / 下移」语义操作提供。
class LyricsSourceOrderTile extends StatelessWidget {
  final List<LyricsSource> order;

  /// 「补全歌词」关闭时 LRCLIB 不参与查询，行内置灰并说明原因。
  final bool lrclibEnabled;
  final ValueChanged<List<LyricsSource>> onChanged;

  const LyricsSourceOrderTile({
    super.key,
    required this.order,
    required this.lrclibEnabled,
    required this.onChanged,
  });

  static String _name(BuildContext context, LyricsSource source) {
    final l10n = context.l10n;
    return switch (source) {
      LyricsSource.spotify => l10n.settingsLyricsSourceSpotify,
      LyricsSource.qqMusic => l10n.settingsLyricsSourceQqMusic,
      LyricsSource.netease => l10n.settingsLyricsSourceNetease,
      LyricsSource.lrclib => l10n.settingsLyricsSourceLrclib,
    };
  }

  static String _role(BuildContext context, LyricsSource source) {
    final l10n = context.l10n;
    return switch (source) {
      LyricsSource.spotify => l10n.settingsLyricsSourceRoleSpotify,
      LyricsSource.lrclib => l10n.settingsLyricsSourceRoleLrclib,
      _ => l10n.settingsLyricsSourceRoleCommunity,
    };
  }

  /// onReorderItem 已按「先移除旧项」修正过 newIndex，这里直接插入。
  void _move(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final next = [...order];
    next.insert(newIndex, next.removeAt(oldIndex));
    onChanged(List.unmodifiable(next));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsLyricsSourceOrder,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.settingsLyricsSourceOrderSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: order.length,
            onReorderItem: _move,
            proxyDecorator: (child, index, animation) => Material(
              color: theme.colorScheme.surfaceContainerHighest,
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
            itemBuilder: (context, index) {
              final source = order[index];
              final off = source == LyricsSource.lrclib && !lrclibEnabled;
              final color = off
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                  : theme.colorScheme.onSurface;
              return ConstrainedBox(
                key: ValueKey(source),
                constraints: const BoxConstraints(minHeight: 52),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name(context, source),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            off
                                ? l10n.settingsLyricsSourceDisabled
                                : _role(context, source),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: ControlTooltip(
                          message: l10n.settingsLyricsSourceDrag,
                          placement: ControlTooltipPlacement.above,
                          hitboxSize: 48,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
