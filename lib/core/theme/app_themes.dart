import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';

/// Enum para los temas disponibles
enum AppThemeEnum {
  original,
  azulBlancoNegro,
  proPos,
}

extension AppThemeExtension on AppThemeEnum {
  String get label {
    switch (this) {
      case AppThemeEnum.original:
        return 'Tema Original';
      case AppThemeEnum.azulBlancoNegro:
        return 'Azul / Blanco / Negro';
      case AppThemeEnum.proPos:
        return 'Profesional POS';
    }
  }

  String get key {
    return toString().split('.').last;
  }
}

/// Clase centralizada para manejar todos los temas de la aplicaciÃ³n
class AppThemes {
  AppThemes._();

  // ============================================================================
  // TEMA 1: FULLPOS (Azul + Turquesa)
  // ============================================================================
  static ThemeData get original => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Poppins',

        // Color scheme
        colorScheme: const ColorScheme.light(
          primary: AppColors.teal700,
          onPrimary: AppColors.textLight,
          secondary: AppColors.gold,
          onSecondary: AppColors.textDark,
          surface: AppColors.surfaceLight,
          onSurface: AppColors.textDark,
          error: AppColors.error,
          onError: AppColors.textLight,
          surfaceContainerHighest: AppColors.surfaceLightVariant,
        ),

        scaffoldBackgroundColor: AppColors.bgLight,

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.teal800,
          foregroundColor: AppColors.textLight,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textLight,
          ),
          iconTheme: IconThemeData(color: AppColors.textLight),
        ),

        // Cards
        cardTheme: CardThemeData(
          color: AppColors.surfaceLight,
          elevation: 1,
          shadowColor: Colors.black.withAlpha(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
            side: const BorderSide(
              color: AppColors.surfaceLightBorder,
              width: 1,
            ),
          ),
        ),

        // Input decoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(
              color: AppColors.surfaceLightBorder,
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(
              color: AppColors.surfaceLightBorder,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(color: AppColors.teal500, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingM,
            vertical: AppSizes.paddingM,
          ),
        ),

        // Elevated Button
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.textDark,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            elevation: 2,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),

        // Outlined Button
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.teal700,
            side: const BorderSide(color: AppColors.teal700, width: 1.5),
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
          ),
        ),

        // Text Button
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.teal700,
            minimumSize: const Size(0, 48),
          ),
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: AppColors.surfaceLightBorder,
          thickness: 1,
          space: 1,
        ),

        // Text theme
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: AppColors.textDark,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          displayMedium: TextStyle(
            color: AppColors.textDark,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          displaySmall: TextStyle(
            color: AppColors.textDark,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          titleLarge: TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          titleMedium: TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          titleSmall: TextStyle(
            color: AppColors.textDark,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          bodyLarge: TextStyle(
            color: AppColors.textDark,
            fontSize: 16,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          bodyMedium: TextStyle(
            color: AppColors.textDark,
            fontSize: 14,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          bodySmall: TextStyle(
            color: AppColors.textDarkSecondary,
            fontSize: 12,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          labelLarge: TextStyle(
            color: AppColors.textDarkSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
          labelMedium: TextStyle(
            color: AppColors.textDarkSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
          labelSmall: TextStyle(
            color: AppColors.textDarkMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
        ),
      );

  // ============================================================================
  // TEMA 2: AZUL / BLANCO / NEGRO
  // ============================================================================
  static ThemeData get azulBlancoNegro => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Poppins',

        // Color scheme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0052CC), // Azul primario
          primary: const Color(0xFF0052CC),
          secondary: const Color(0xFF00B8D9), // Turquesa/Cian
          surface: const Color(0xFFFFFFFF),
          background: const Color(0xFFF5F7FB),
          error: const Color(0xFFD32F2F),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onBackground: const Color(0xFF111827),
          onSurface: const Color(0xFF111827),
        ),

        scaffoldBackgroundColor: const Color(0xFFF5F7FB),

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF003366), // Azul muy oscuro
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),

        // Cards
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withAlpha(15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
            side: BorderSide(
              color: Colors.grey.withAlpha(50),
              width: 1,
            ),
          ),
        ),

        // Input decoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: BorderSide(
              color: Colors.grey.withAlpha(100),
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: BorderSide(
              color: Colors.grey.withAlpha(100),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(
              color: Color(0xFF0052CC),
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(
              color: Color(0xFFD32F2F),
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingM,
            vertical: AppSizes.paddingM,
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontFamily: 'Poppins',
          ),
        ),

        // Elevated Button
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0052CC),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            elevation: 2,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              fontFamily: 'Poppins',
            ),
          ),
        ),

        // Outlined Button
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0052CC),
            side: const BorderSide(
              color: Color(0xFF0052CC),
              width: 1.5,
            ),
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
          ),
        ),

        // Text Button
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0052CC),
            minimumSize: const Size(0, 48),
          ),
        ),

        // Divider
        dividerTheme: DividerThemeData(
          color: Colors.grey.withAlpha(50),
          thickness: 1,
        ),

        // Text theme
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: Color(0xFF111827),
            fontSize: 32,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          displayMedium: TextStyle(
            color: Color(0xFF111827),
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          displaySmall: TextStyle(
            color: Color(0xFF111827),
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          titleLarge: TextStyle(
            color: Color(0xFF111827),
            fontSize: 22,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          titleMedium: TextStyle(
            color: Color(0xFF111827),
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          titleSmall: TextStyle(
            color: Color(0xFF111827),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF111827),
            fontSize: 16,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF111827),
            fontSize: 14,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          bodySmall: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          labelLarge: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
          labelMedium: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
          labelSmall: TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 10,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
        ),
      );

  // ============================================================================
  // TEMA 3: PROFESIONAL POS (Azul oscuro + negro + blanco ejecutivo)
  // ============================================================================
  static ThemeData get proPos => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Poppins',

        // Color scheme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D84FF), // Azul elÃ©ctrico premium
          primary: const Color(0xFF0D84FF),
          secondary: const Color(0xFF101820), // neutro ejecutivo
          surface: const Color(0xFF0F1B2C),
          background: const Color(0xFF050915),
          error: const Color(0xFFDC2626),
          onPrimary: Colors.white,
          onSecondary: const Color(0xFFE8EEF7),
          onBackground: const Color(0xFFE8EEF7),
          onSurface: const Color(0xFFE0E8F4),
        ),

        scaffoldBackgroundColor: const Color(0xFF050915),

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B2038),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),

        // Cards
        cardTheme: CardThemeData(
          color: const Color(0xFF0F1B2C),
          elevation: 1,
          shadowColor: Colors.black.withAlpha(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
            side: BorderSide(
              color: const Color(0xFF233044).withAlpha(40),
              width: 1,
            ),
          ),
        ),

        // Input decoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF13253A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: BorderSide(
              color: const Color(0xFF3B4A61).withAlpha(60),
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: BorderSide(
              color: const Color(0xFF3B4A61).withAlpha(60),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(
              color: Color(0xFF0D84FF),
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            borderSide: const BorderSide(
              color: Color(0xFFDC2626),
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingM,
            vertical: AppSizes.paddingM,
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontFamily: 'Poppins',
          ),
        ),

        // Elevated Button (principal azul)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E5A88),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            elevation: 1,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              fontFamily: 'Poppins',
            ),
          ),
        ),

        // Outlined Button
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0D84FF),
            side: const BorderSide(
              color: Color(0xFF0D84FF),
              width: 1.5,
            ),
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
          ),
        ),

        // Text Button
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF1E5A88),
            minimumSize: const Size(0, 48),
          ),
        ),

        // Divider
        dividerTheme: DividerThemeData(
          color: const Color(0xFF233044).withAlpha(60),
          thickness: 1,
        ),

        // Text theme
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: Color(0xFFE8EEF7),
            fontSize: 32,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          displayMedium: TextStyle(
            color: Color(0xFFE0E8F4),
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          displaySmall: TextStyle(
            color: Color(0xFFE0E8F4),
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
          titleLarge: TextStyle(
            color: Color(0xFFE0E8F4),
            fontSize: 22,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          titleMedium: TextStyle(
            color: Color(0xFFD0D9E8),
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          titleSmall: TextStyle(
            color: Color(0xFFD0D9E8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          bodyLarge: TextStyle(
            color: Color(0xFFCFD7E4),
            fontSize: 16,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          bodyMedium: TextStyle(
            color: Color(0xFFC3CCDB),
            fontSize: 14,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          bodySmall: TextStyle(
            color: Color(0xFFAAB6C9),
            fontSize: 12,
            fontWeight: FontWeight.normal,
            fontFamily: 'Poppins',
          ),
          labelLarge: TextStyle(
            color: Color(0xFFCFD7E4),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
          labelMedium: TextStyle(
            color: Color(0xFF9FB0C8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
          labelSmall: TextStyle(
            color: Color(0xFF7E8FA7),
            fontSize: 10,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
        ),
      );

  /// Obtener un tema por su enum
  static ThemeData getTheme(AppThemeEnum theme) {
    switch (theme) {
      case AppThemeEnum.azulBlancoNegro:
        return azulBlancoNegro;
      case AppThemeEnum.proPos:
        return proPos;
      case AppThemeEnum.original:
        return original;
    }
  }

  /// Obtener un tema por su clave de string
  static ThemeData getThemeByKey(String key) {
    switch (key) {
      case 'azulBlancoNegro':
        return azulBlancoNegro;
      case 'proPos':
        return proPos;
      case 'original':
      default:
        return proPos;
    }
  }

  /// Obtener AppThemeEnum de una clave de string
  static AppThemeEnum getThemeEnumByKey(String key) {
    switch (key) {
      case 'azulBlancoNegro':
        return AppThemeEnum.azulBlancoNegro;
      case 'proPos':
        return AppThemeEnum.proPos;
      case 'original':
      default:
        return AppThemeEnum.proPos;
    }
  }
}
