import 'package:flutter/material.dart';

class SettingsLayout {
  SettingsLayout._();

  static const double _minContentWidth = 800;
  static const double _maxContentWidth = 1000;

  static ThemeData brandedTheme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = base.colorScheme;
    final outline = scheme.outlineVariant;
    final textTheme = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return base.copyWith(
      scaffoldBackgroundColor: base.scaffoldBackgroundColor,
      colorScheme: scheme,
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        shape: Border(bottom: BorderSide(color: outline, width: 1)),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: outline.withOpacity(0.55),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: scheme.surface.withOpacity(0.84),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline.withOpacity(0.65)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline.withOpacity(0.65)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary.withOpacity(0.45)),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: outline, width: 1.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  static EdgeInsets contentPadding(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (width < 640) {
      return const EdgeInsets.all(12);
    }
    return const EdgeInsets.all(16);
  }

  static BoxConstraints maxWidth(
    BoxConstraints constraints, {
    double max = _maxContentWidth,
  }) {
    final width = constraints.maxWidth;
    final resolvedUpper = max < _maxContentWidth ? max : _maxContentWidth;
    final resolvedLower = resolvedUpper < _minContentWidth
        ? resolvedUpper
        : _minContentWidth;
    final preferred = width * 0.6;
    final resolved = preferred.clamp(resolvedLower, resolvedUpper).toDouble();
    return BoxConstraints(maxWidth: width < resolved ? width : resolved);
  }

  static Widget pageFrame(
    BoxConstraints constraints, {
    required Widget child,
    double max = _maxContentWidth,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: maxWidth(constraints, max: max),
        child: Padding(
          padding: contentPadding(constraints),
          child: child,
        ),
      ),
    );
  }

  static Widget sectionHeading(
    BuildContext context, {
    required String title,
    String? subtitle,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static double sectionGap(BoxConstraints constraints) {
    return constraints.maxWidth < 640 ? 12 : 16;
  }

  static double itemGap(BoxConstraints constraints) {
    return constraints.maxWidth < 640 ? 8 : 12;
  }
}
