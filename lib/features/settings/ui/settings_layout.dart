import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsLayout {
  SettingsLayout._();

  // Más centrado, limpio y ejecutivo.
  static const double _minContentWidth = 680;
  static const double _maxContentWidth = 820;

  // Cambia esta ruta si tu pantalla de ventas usa otro path.
  // Ejemplos comunes: '/sales', '/ventas', '/pos', '/'
  static const String salesRoute = '/sales';

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
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
          height: 1.05,
        ),
        shape: Border(
          bottom: BorderSide(
            color: outline.withOpacity(0.45),
            width: 1,
          ),
        ),
      ),

      cardTheme: base.cardTheme.copyWith(
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),

      listTileTheme: base.listTileTheme.copyWith(
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
        dense: true,
        minVerticalPadding: 0,
        horizontalTitleGap: 8,
        contentPadding: EdgeInsets.zero,
      ),

      dividerTheme: DividerThemeData(
        color: outline.withOpacity(0.30),
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: scheme.surface.withOpacity(0.92),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        hintStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant.withOpacity(0.62),
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        prefixIconColor: scheme.onSurfaceVariant.withOpacity(0.68),
        suffixIconColor: scheme.onSurfaceVariant.withOpacity(0.68),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: outline.withOpacity(0.38),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: outline.withOpacity(0.38),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.primary.withOpacity(0.42),
            width: 1.1,
          ),
        ),
      ),

      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: outline.withOpacity(0.55),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(
            color: outline.withOpacity(0.55),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
          textStyle: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  static EdgeInsets contentPadding(BoxConstraints constraints) {
    final width = constraints.maxWidth;

    if (width < 640) {
      return const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      );
    }

    if (width < 1100) {
      return const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 16,
      );
    }

    return const EdgeInsets.symmetric(
      horizontal: 22,
      vertical: 20,
    );
  }

  static BoxConstraints maxWidth(
    BoxConstraints constraints, {
    double max = _maxContentWidth,
  }) {
    final screenWidth = constraints.maxWidth;
    final resolvedMax = max.clamp(_minContentWidth, _maxContentWidth).toDouble();

    if (screenWidth < 740) {
      return BoxConstraints(maxWidth: screenWidth);
    }

    return BoxConstraints(maxWidth: resolvedMax);
  }

  static Widget pageFrame(
    BoxConstraints constraints, {
    required Widget child,
    double max = _maxContentWidth,
    bool showSalesButton = true,
    String salesPath = salesRoute,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: maxWidth(constraints, max: max),
        child: Padding(
          padding: contentPadding(constraints),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showSalesButton) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: goToSalesButton(
                    constraints: constraints,
                    salesPath: salesPath,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  static Widget goToSalesButton({
    required BoxConstraints constraints,
    String salesPath = salesRoute,
  }) {
    final isCompact = constraints.maxWidth < 560;

    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final textTheme = theme.textTheme;

        return Tooltip(
          message: 'Ir a ventas',
          waitDuration: const Duration(milliseconds: 450),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _goToSales(context, salesPath),
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                height: 38,
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 10 : 13,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.primary.withOpacity(0.22),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.point_of_sale_rounded,
                      size: 17,
                      color: scheme.primary,
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Ir a ventas',
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static void _goToSales(BuildContext context, String salesPath) {
    // Si hay un Navigator stack (settings abierto encima de ventas), pop limpio.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    // Con GoRouter (MaterialApp.router), usar go() en lugar de pushReplacementNamed.
    GoRouter.of(context).go(salesPath);
  }

  static Widget sectionHeading(
    BuildContext context, {
    required String title,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.15,
            height: 1.05,
            fontSize: 13,
          ),
        ),
        if (subtitle != null &&
            subtitle.trim().isNotEmpty &&
            subtitle.trim().length <= 34) ...[
          const SizedBox(height: 2),
          Text(
            subtitle.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withOpacity(0.68),
              height: 1.05,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  static double sectionGap(BoxConstraints constraints) {
    return constraints.maxWidth < 640 ? 10 : 16;
  }

  static double itemGap(BoxConstraints constraints) {
    return constraints.maxWidth < 640 ? 6 : 10;
  }
}