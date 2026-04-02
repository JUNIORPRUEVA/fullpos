import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import 'app_tokens.dart';
import '../../theme/app_theme.dart';

/// Enum para los temas disponibles
enum AppThemeEnum { original, azulBlancoNegro, proPos }

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

  static const AppTokens _originalTokens = AppTokens.defaultTokens;

  static const AppTokens _azulTokens = AppTokens(
    topbarBackground: Color(0xFF001E40),
    topbarText: Color(0xFFFFFFFF),
    footerBackground: Color(0xFF001E40),
    footerText: Color(0xFFFFFFFF),
    panelBackground: Color(0xFFF5F7FB),
    panelBorder: Color(0xFFE0E4EB),
    cardBackground: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFD1D7E1),
    sidebarBackground: Color(0xFF001E40),
    sidebarBorder: Color(0xFF0A3A67),
    sidebarText: Color(0xFFFFFFFF),
    sidebarActive: Color(0xFF0052CC),
    controlBarBackground: Color(0xFF00336A),
    controlBarBorder: Color(0xFF0052CC),
    controlBarText: Color(0xFFFFFFFF),
    buttonPrimary: Color(0xFF0052CC),
    buttonSecondary: Color(0xFF003366),
    buttonDanger: Color(0xFFD32F2F),
    searchFieldBackground: Color(0xFFFFFFFF),
    searchFieldText: Color(0xFF111827),
    searchFieldIcon: Color(0xFF111827),
    tileHover: Color(0xFFE5EEFF),
    outline: Color(0xFFCDD6E4),
  );

  static const AppTokens _proPosTokens = AppTokens(
    topbarBackground: Color(0xFFFFFFFF),
    topbarText: Color(0xFF111827),
    footerBackground: Color(0xFFF8FAFC),
    footerText: Color(0xFF111827),
    panelBackground: Color(0xFFE5E7EB),
    panelBorder: Color(0xFFD1D5DB),
    cardBackground: Color(0xFFF8FAFC),
    cardBorder: Color(0xFFD1D5DB),
    sidebarBackground: Color(0xFFF8FAFC),
    sidebarBorder: Color(0xFFD1D5DB),
    sidebarText: Color(0xFF111827),
    sidebarActive: Color(0xFF2563EB),
    controlBarBackground: Color(0xFFE5E7EB),
    controlBarBorder: Color(0xFFD1D5DB),
    controlBarText: Color(0xFF111827),
    buttonPrimary: Color(0xFF2563EB),
    buttonSecondary: Color(0xFF1D4ED8),
    buttonDanger: Color(0xFFEF4444),
    searchFieldBackground: Color(0xFFF8FAFC),
    searchFieldText: Color(0xFF111827),
    searchFieldIcon: Color(0xFFABA9A9),
    tileHover: Color(0xFFEFF6FF),
    outline: Color(0xFFD1D5DB),
  );

  // ============================================================================
  // TEMA 1: FULLPOS (Azul + Turquesa)
  // ============================================================================
  static ThemeData get original => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Poppins',

    colorScheme: ColorScheme.light(
      primary: AppColors.brandBlueLight,
      onPrimary: AppColors.textLight,
      secondary: AppColors.brandBlue,
      onSecondary: AppColors.textLight,
      background: AppColors.bgLight,
      onBackground: AppColors.textLight,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.textDark,
      error: AppColors.error,
      onError: AppColors.textLight,
    ).copyWith(surfaceContainerHighest: AppColors.surfaceLightVariant),

    scaffoldBackgroundColor: AppColors.bgLight,

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceDark,
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
        side: const BorderSide(color: AppColors.surfaceLightBorder, width: 1),
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
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
    extensions: const [_originalTokens],
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
        side: BorderSide(color: Colors.grey.withAlpha(50), width: 1),
      ),
    ),

    // Input decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: Colors.grey.withAlpha(100), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: Colors.grey.withAlpha(100), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: const BorderSide(color: Color(0xFF0052CC), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 2),
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
        side: const BorderSide(color: Color(0xFF0052CC), width: 1.5),
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
    extensions: const [_azulTokens],
  );

  // ============================================================================
  // TEMA 3: PROFESIONAL POS (Azul oscuro + negro + blanco ejecutivo)
  // ============================================================================
  static ThemeData get proPos =>
      AppTheme.fullposSaas().copyWith(extensions: const [_proPosTokens]);

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
