import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/home_feed.dart';
import '../../../widgets/control_tooltip.dart';
import '../../../widgets/filter_pill.dart';
import '../../../widgets/hover_builder.dart';
import '../../../widgets/text_metrics.dart';

/// 主页顶部筛选标签栏（滚动时吸顶，与官方一致）。
///
/// 标签来自服务端 homeChips：
/// - 未选中任何标签：「全部」+ 各一级标签；
/// - 选中某个一级标签（或其二级标签）：「×」清除 + 该一级标签 + 它的二级标签。
/// [leading] 为手机端左侧的头像（点按打开设置）。
class HomeChipBar extends StatelessWidget {
  final List<HomeChip> chips;

  /// 当前 facet（空 = 全部）。
  final String selected;
  final ValueChanged<String> onSelected;
  final Widget? leading;
  final Widget? trailing;

  /// 与页面背景同位置的渐变切片，吸顶时遮住下方滚动内容。
  final Widget background;

  const HomeChipBar({
    super.key,
    required this.chips,
    required this.selected,
    required this.onSelected,
    required this.background,
    this.leading,
    this.trailing,
  });

  static const double _verticalPadding = 8;
  static const double _leadingSize = 32;

  /// 胶囊高度：与音乐库侧栏的筛选胶囊一致（侧栏行高 44 − 上下留白 12 = 32）。
  ///
  /// 必须显式给定：FilterPill 的容器带 alignment，父级高度有界时会撑满父级 ——
  /// 标签栏整行高约 48px，不限高胶囊就会比侧栏的大一圈。
  static const double pillHeight = 32;

  /// 标签行高度：胶囊（上下共 10 内边距 + 实测一行文字）与头像取大者，再加上下留白。
  static double extentOf(BuildContext context) {
    final pill =
        TextMetrics.lineHeight(
          context,
          Theme.of(context).textTheme.labelMedium,
        ) +
        10;
    return math.max(pill, _leadingSize) + _verticalPadding * 2;
  }

  /// 选中的 facet 属于哪个一级标签（一级本身或其二级标签）。
  HomeChip? get _parent {
    if (selected.isEmpty) return null;
    for (final chip in chips) {
      if (chip.id == selected || chip.subChips.any((s) => s.id == selected))
        return chip;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final parent = _parent;

    final pills = <Widget>[
      if (parent == null) ...[
        FilterPill(
          label: l10n.filterAll,
          isSelected: true,
          onTap: () => onSelected(''),
        ),
        for (final chip in chips)
          FilterPill(
            label: chip.label,
            isSelected: false,
            onTap: () => onSelected(chip.id),
          ),
      ] else ...[
        _ClearPill(tooltip: l10n.homeClearFilter, onTap: () => onSelected('')),
        FilterPill(
          label: parent.label,
          isSelected: selected == parent.id,
          onTap: () => onSelected(parent.id),
        ),
        for (final sub in parent.subChips)
          FilterPill(
            label: sub.label,
            isSelected: selected == sub.id,
            onTap: () => onSelected(sub.id),
          ),
      ],
    ];

    return SliverPersistentHeader(
      pinned: true,
      delegate: _ChipBarDelegate(
        extent: extentOf(context),
        background: background,
        child: Row(
          children: [
            if (leading != null)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: leading!,
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(
                  leading == null ? 16 : 10,
                  0,
                  16,
                  0,
                ),
                child: Row(
                  children: [
                    for (final pill in pills)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(height: pillHeight, child: pill),
                      ),
                  ],
                ),
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}

class _ChipBarDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget background;
  final Widget child;

  _ChipBarDelegate({
    required this.extent,
    required this.background,
    required this.child,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      // 必须撑满 extent：吸顶 sliver 以子组件高度作为绘制高度
      SizedBox.expand(
        child: Stack(fit: StackFit.expand, children: [background, child]),
      );

  @override
  bool shouldRebuild(_ChipBarDelegate old) =>
      old.extent != extent ||
      old.background != background ||
      old.child != child;
}

/// 「×」清除筛选（与胶囊同高的圆形按钮）。
class _ClearPill extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const _ClearPill({required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 与胶囊同高（见 HomeChipBar.pillHeight）
    const size = HomeChipBar.pillHeight;
    return ControlTooltip(
      message: tooltip,
      placement: ControlTooltipPlacement.above,
      hitboxSize: size,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 200)),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: hovered
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
