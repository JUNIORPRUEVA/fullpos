import 'package:flutter/material.dart';

import '../core/theme/app_gradient_theme.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData fullposSaas() {
    final colorScheme = const ColorScheme.light(
      primary: AppColors.primaryBlue,
      onPrimary: Colors.white,
      secondary: AppColors.darkBlue,
      onSecondary: Colors.white,
      surface: AppColors.cardBackground,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.borderSoft,
      surfaceContainerHighest: AppColors.cardBackgroundAlt,
      onSurfaceVariant: AppColors.textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppTypography.fontFamily,
      colorScheme: colorScheme,
      textTheme: AppTypography.textTheme(),
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      hoverColor: AppColors.primaryBlue.withOpacity(0.045),
      splashColor: AppColors.primaryBlue.withOpacity(0.08),
      disabledColor: AppColors.inactive,
      unselectedWidgetColor: AppColors.inactive,
      highlightColor: Colors.transparent,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 1,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.radius16,
          side: const BorderSide(color: AppColors.borderSoft),
        ),
        shadowColor: Colors.black.withOpacity(0.06),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.topbarBackground,
        foregroundColor: AppColors.chromeText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.chromeText),
        actionsIconTheme: IconThemeData(color: AppColors.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: AppSpacing.radius12,
          ),
          minimumSize: const Size(0, 46),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: AppSpacing.radius12,
          ),
          minimumSize: const Size(0, 46),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderSoft),
          shape: const RoundedRectangleBorder(
            borderRadius: AppSpacing.radius12,
          ),
          minimumSize: const Size(0, 46),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardBackground,
        prefixIconColor: AppColors.inactive,
        suffixIconColor: AppColors.inactive,
        border: const OutlineInputBorder(
          borderRadius: AppSpacing.radius12,
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppSpacing.radius12,
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppSpacing.radius12,
          borderSide: BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppSpacing.radius12,
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppSpacing.radius12,
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: AppSpacing.radius12,
          side: BorderSide(color: AppColors.borderSoft),
        ),
        shadowColor: Colors.black12,
        textStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSoft,
        thickness: 1,
      ),
      extensions: const [
        AppGradientTheme(
          start: Color(0xFFFFFFFF),
          mid: Color(0xFFF8FAFC),
          end: Color(0xFFE5E7EB),
        ),
      ],
    );
  }
}
