import 'package:flutter/material.dart';

/// A PNG icon drawn as a tinted glyph: [color] replaces the file's own
/// colours. Callers inside tight constraints wrap it in a Center.
class AppPngIcon extends StatelessWidget {
  const AppPngIcon({
    super.key,
    required this.asset,
    required this.size,
    required this.color,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.asset(
      asset,
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
      cacheWidth: pixels,
      cacheHeight: pixels,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
    );
  }
}
