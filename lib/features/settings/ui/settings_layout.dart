import 'package:flutter/material.dart';

class SettingsLayout {
  SettingsLayout._();

  static EdgeInsets contentPadding(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final horizontal = (width * 0.04).clamp(12.0, 32.0);
    final vertical = (width * 0.02).clamp(10.0, 24.0);
    return EdgeInsets.fromLTRB(horizontal, vertical, horizontal, vertical);
  }

  static BoxConstraints maxWidth(BoxConstraints constraints, {double max = 1200}) {
    final width = constraints.maxWidth;
    final resolved = width < max ? width : max;
    return BoxConstraints(maxWidth: resolved);
  }

  static double sectionGap(BoxConstraints constraints) {
    return (constraints.maxWidth * 0.016).clamp(12.0, 20.0);
  }

  static double itemGap(BoxConstraints constraints) {
    return (constraints.maxWidth * 0.012).clamp(8.0, 16.0);
  }
}
