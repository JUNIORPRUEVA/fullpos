import 'package:flutter/material.dart';

import '../theme/color_utils.dart';

class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.surface;
    final fg = ColorUtils.ensureReadableColor(scheme.onSurface, bg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: fg)),
        backgroundColor: bg,
      ),
    );
  }
}
