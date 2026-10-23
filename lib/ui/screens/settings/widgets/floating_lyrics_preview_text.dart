import 'package:flutter/material.dart';

class FloatingLyricsPreviewText extends StatelessWidget {
  const FloatingLyricsPreviewText({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.fontWeight,
    super.key,
  });

  final String text;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.22 * color.a),
            offset: const Offset(1, 1),
            blurRadius: 1,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }
}
