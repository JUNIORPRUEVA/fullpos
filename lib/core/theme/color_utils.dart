import 'package:flutter/material.dart';

class ColorUtils {
  ColorUtils._();

  /// Returns the best foreground color (dark or light) for the provided [background].
  static Color foregroundFor(
    Color background, {
    Color dark = Colors.black,
    Color light = Colors.white,
  }) {
    return background.computeLuminance() > 0.5 ? dark : light;
  }

  /// Returns whether the provided color is considered "light" for contrast decisions.
  static bool isLight(Color color) => color.computeLuminance() > 0.5;

  static double _contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance() + 0.05;
    final l2 = b.computeLuminance() + 0.05;
    return l1 > l2 ? l1 / l2 : l2 / l1;
  }

  static Color ensureReadableColor(
    Color fg,
    Color bg, {
    double minRatio = 4.5,
  }) {
    if (_contrastRatio(fg, bg) >= minRatio) return fg;
    return foregroundFor(bg);
  }

  static Color readableTextColor(Color bg) => foregroundFor(bg);
}
