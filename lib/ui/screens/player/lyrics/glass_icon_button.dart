import 'package:flutter/material.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../widgets/control_tooltip.dart';
import '../../../widgets/liquid_glass.dart';

/// 圆形液态玻璃图标按钮：歌词界面上的「全屏 / 关闭 / 退出」等浮动操作。
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool glass;
  final bool? selected;
  final BorderRadius? borderRadius;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.glass = true,
    this.selected,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size / 2);
    final enabled = onPressed != null;
    final fg = selected == true
        ? Colors.black87
        : (enabled ? Colors.white : Colors.white54);
    final button = Semantics(
      toggled: selected,
      child: AnimatedContainer(
        duration: context.motion(const Duration(milliseconds: 220)),
        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected == true ? Colors.white : Colors.transparent,
          borderRadius: radius,
        ),
        child: IconButton(
          icon: Icon(icon, size: size * 0.45, color: fg),
          tooltip: null,
          color: fg,
          disabledColor: Colors.white54,

          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: fg,
            disabledForegroundColor: Colors.white54,
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
          isSelected: selected,
          onPressed: onPressed,
        ),
      ),
    );
    return ControlTooltip(
      message: tooltip,
      child: glass ? LiquidGlass(borderRadius: radius, child: button) : button,
    );
  }
}
