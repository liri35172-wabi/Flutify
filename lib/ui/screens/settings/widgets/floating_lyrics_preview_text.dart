import 'package:flutter/material.dart';

/// Picks one crisp keyline opposite the lyric color's luminance.
///
/// A single edge keeps thin glyphs readable on both light and dark surfaces
/// without the heavy double outline that can make custom colors look blurred.
Color floatingLyricsOutlineColor(Color lyricColor) =>
    lyricColor.computeLuminance() >= 0.42
    ? const Color(0xFF15181F)
    : const Color(0xFFF7F8FC);

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
    final outline = TextStyle(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1
        ..color = floatingLyricsOutlineColor(color),
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
    final fill = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: Text(
            text,
            style: outline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        Text(
          text,
          style: fill,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
