import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class SettingsLayout {
  SettingsLayout._();

  static ThemeData brandedTheme(BuildContext context) {
    final base = Theme.of(context);
    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    final colorScheme = base.colorScheme.copyWith(
      surface: AppColors.cardBackground,
      surfaceVariant: AppColors.background,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outlineVariant: AppColors.borderSoft,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: colorScheme,
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.cardBackground,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: AppColors.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.borderSoft),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: AppColors.textPrimary,
        iconColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: AppColors.cardBackground,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: AppColors.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.borderSoft),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: const BorderSide(color: Colors.black, width: 1.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

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
