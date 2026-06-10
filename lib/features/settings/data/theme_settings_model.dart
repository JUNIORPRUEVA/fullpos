import 'package:flutter/material.dart';

class PremiumThemeColors {
  PremiumThemeColors._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceAlt = Color(0xFFE5E7EB);
  static const Color sidebarBackground = Color(0xFFF8FAFC);
  static const Color sidebarHover = Color(0xFFEFF6FF);
  static const Color sidebarActive = Color(0xFF2563EB);
  static const Color sidebarText = Color(0xFF111827);
  static const Color chromeBackground = Color(0xFFFFFFFF);
  static const Color chromeText = Color(0xFF111827);
  static const Color appBarBorder = Color(0xFFD1D5DB);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color inactive = Color(0xFFABA9A9);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color gradientStart = Color(0xFFFFFFFF);
  static const Color gradientMid = Color(0xFFF8FAFC);
  static const Color gradientEnd = Color(0xFFE5E7EB);
  static const Color selectionSurface = Color(0xFFEFF6FF);
  static const Color darkBackground = Color(0xFF020617);
  static const Color darkSurface = Color(0xFF0F172A);
  static const Color darkSurfaceAlt = Color(0xFF111827);
  static const Color darkText = Color(0xFFE2E8F0);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color salesSidebarBackground = Color(0xFFF2F6F9);
  static const Color salesFooterBackground = Color(0xFFFFFFFF);
  static const Color salesDetailBackground = Color(0x1E1976D2);
  static const Color salesDetailLegacyGradientStart = Color(0xFF7B1FA2);
  static const Color salesDetailLegacyGradientMid = Color(0xFF2E7D32);
  static const Color salesDetailLegacyGradientEnd = Color(0xFF2E7D32);
  static const Color salesControlSurface = Color(0xFFFFFFFF);
  static const Color salesControlText = Color(0xFF1F2937);
  static const Color salesFooterButtonsBorder = Color(0x1E1976D2);
}

@immutable
class AppThemeConfig {
  final Color primaryColor;
  final Color sidebarColor;
  final Color appbarColor;
  final Color footerColor;
  final Color cardColor;
  final Color gridBackgroundColor;
  final Color salesDetailColor;
  final Color textPrimary;
  final Color textSecondary;
  final bool applyChromeToEntireLayout;

  const AppThemeConfig({
    required this.primaryColor,
    required this.sidebarColor,
    required this.appbarColor,
    required this.footerColor,
    required this.cardColor,
    required this.gridBackgroundColor,
    required this.salesDetailColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.applyChromeToEntireLayout,
  });
}

/// Modelo para la configuraciÃ³n del tema personalizado
class ThemeSettings {
  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color textColor;
  final Color hoverColor;

  /// AppBar normal (AppBar de pantallas: `Scaffold(appBar: AppBar(...))`)
  final Color appBarColor;
  final Color appBarTextColor;

  /// AppBar principal del layout (Topbar custom en `AppShell`)
  final Color topbarColor;
  final Color topbarTextColor;

  final Color cardColor;
  final Color buttonColor;
  final Color successColor;
  final Color errorColor;
  final Color warningColor;
  // Nuevos colores para sidebar y footer
  final Color sidebarColor;
  final Color sidebarTextColor;
  final Color sidebarActiveColor;
  final Color footerColor;
  final Color footerTextColor;
  final Color backgroundGradientStart;
  final Color backgroundGradientMid;
  final Color backgroundGradientEnd;
  final Color salesDetailBackgroundColor;
  final Color salesDetailGradientStart;
  final Color salesDetailGradientMid;
  final Color salesDetailGradientEnd;
  final Color salesDetailTextColor;

  // Pagina de ventas (grid/tarjetas de productos)
  final Color salesGridBackgroundColor;
  final Color salesProductCardBackgroundColor;
  final Color salesProductCardBorderColor;
  final Color salesProductCardTextColor;
  final Color salesProductCardAltBackgroundColor;
  final Color salesProductCardAltBorderColor;
  final Color salesProductCardAltTextColor;
  final Color salesProductPriceColor;

  // Pagina de ventas (barra superior/botones inferiores)
  final Color salesControlBarBackgroundColor;
  final Color salesControlBarContentBackgroundColor;
  final Color salesControlBarBorderColor;
  final Color salesControlBarTextColor;
  final Color salesControlBarDropdownBackgroundColor;
  final Color salesControlBarDropdownBorderColor;
  final Color salesControlBarDropdownTextColor;
  final Color salesControlBarPopupBackgroundColor;
  final Color salesControlBarPopupTextColor;
  final Color salesControlBarPopupSelectedBackgroundColor;
  final Color salesControlBarPopupSelectedTextColor;
  final Color salesFooterButtonsBackgroundColor;
  final Color salesFooterButtonsTextColor;
  final Color salesFooterButtonsBorderColor;
  final double fontSize;
  final String fontFamily;
  final bool applyChromeToEntireLayout;
  final bool isDarkMode;

  const ThemeSettings({
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.hoverColor,
    required this.appBarColor,
    required this.appBarTextColor,
    required this.topbarColor,
    required this.topbarTextColor,
    required this.cardColor,
    required this.buttonColor,
    required this.successColor,
    required this.errorColor,
    required this.warningColor,
    required this.sidebarColor,
    required this.sidebarTextColor,
    required this.sidebarActiveColor,
    required this.footerColor,
    required this.footerTextColor,
    required this.backgroundGradientStart,
    required this.backgroundGradientMid,
    required this.backgroundGradientEnd,
    required this.salesDetailBackgroundColor,
    required this.salesDetailGradientStart,
    required this.salesDetailGradientMid,
    required this.salesDetailGradientEnd,
    required this.salesDetailTextColor,
    required this.salesGridBackgroundColor,
    required this.salesProductCardBackgroundColor,
    required this.salesProductCardBorderColor,
    required this.salesProductCardTextColor,
    required this.salesProductCardAltBackgroundColor,
    required this.salesProductCardAltBorderColor,
    required this.salesProductCardAltTextColor,
    required this.salesProductPriceColor,
    required this.salesControlBarBackgroundColor,
    required this.salesControlBarContentBackgroundColor,
    required this.salesControlBarBorderColor,
    required this.salesControlBarTextColor,
    required this.salesControlBarDropdownBackgroundColor,
    required this.salesControlBarDropdownBorderColor,
    required this.salesControlBarDropdownTextColor,
    required this.salesControlBarPopupBackgroundColor,
    required this.salesControlBarPopupTextColor,
    required this.salesControlBarPopupSelectedBackgroundColor,
    required this.salesControlBarPopupSelectedTextColor,
    required this.salesFooterButtonsBackgroundColor,
    required this.salesFooterButtonsTextColor,
    required this.salesFooterButtonsBorderColor,
    required this.fontSize,
    required this.fontFamily,
    required this.applyChromeToEntireLayout,
    required this.isDarkMode,
  });

  /// Valores por defecto del sistema premium SaaS.
  static const ThemeSettings defaultSettings = ThemeSettings(
    primaryColor: PremiumThemeColors.primary,
    accentColor: PremiumThemeColors.primaryDark,
    backgroundColor: PremiumThemeColors.background,
    surfaceColor: PremiumThemeColors.surface,
    textColor: PremiumThemeColors.textPrimary,
    hoverColor: PremiumThemeColors.sidebarHover,
    appBarColor: PremiumThemeColors.chromeBackground,
    appBarTextColor: PremiumThemeColors.chromeText,
    topbarColor: Color(0xFFFFFFFF),
    topbarTextColor: PremiumThemeColors.chromeText,
    cardColor: PremiumThemeColors.surface,
    buttonColor: PremiumThemeColors.primary,
    successColor: PremiumThemeColors.success,
    errorColor: PremiumThemeColors.error,
    warningColor: PremiumThemeColors.warning,
    sidebarColor: PremiumThemeColors.salesSidebarBackground,
    sidebarTextColor: PremiumThemeColors.sidebarText,
    sidebarActiveColor: PremiumThemeColors.primary,
    footerColor: PremiumThemeColors.salesFooterBackground,
    footerTextColor: PremiumThemeColors.textPrimary,
    backgroundGradientStart: PremiumThemeColors.gradientStart,
    backgroundGradientMid: PremiumThemeColors.gradientMid,
    backgroundGradientEnd: PremiumThemeColors.gradientEnd,
    salesDetailBackgroundColor: PremiumThemeColors.salesDetailBackground,
    salesDetailGradientStart:
      PremiumThemeColors.salesDetailLegacyGradientStart,
    salesDetailGradientMid: PremiumThemeColors.salesDetailLegacyGradientMid,
    salesDetailGradientEnd: PremiumThemeColors.salesDetailLegacyGradientEnd,
    salesDetailTextColor: PremiumThemeColors.textPrimary,
    salesGridBackgroundColor: PremiumThemeColors.background,
    salesProductCardBackgroundColor: PremiumThemeColors.salesControlSurface,
    salesProductCardBorderColor: PremiumThemeColors.salesControlSurface,
    salesProductCardTextColor: PremiumThemeColors.textPrimary,
    salesProductCardAltBackgroundColor: PremiumThemeColors.surfaceAlt,
    salesProductCardAltBorderColor: PremiumThemeColors.appBarBorder,
    salesProductCardAltTextColor: PremiumThemeColors.textPrimary,
    salesProductPriceColor: PremiumThemeColors.primary,
    salesControlBarBackgroundColor: PremiumThemeColors.salesControlSurface,
    salesControlBarContentBackgroundColor: PremiumThemeColors.salesControlSurface,
    salesControlBarBorderColor: PremiumThemeColors.appBarBorder,
    salesControlBarTextColor: PremiumThemeColors.salesControlText,
    salesControlBarDropdownBackgroundColor: PremiumThemeColors.surface,
    salesControlBarDropdownBorderColor: PremiumThemeColors.appBarBorder,
    salesControlBarDropdownTextColor: PremiumThemeColors.textPrimary,
    salesControlBarPopupBackgroundColor: PremiumThemeColors.surface,
    salesControlBarPopupTextColor: PremiumThemeColors.textPrimary,
    salesControlBarPopupSelectedBackgroundColor:
        PremiumThemeColors.selectionSurface,
    salesControlBarPopupSelectedTextColor: PremiumThemeColors.primaryDark,
    salesFooterButtonsBackgroundColor: PremiumThemeColors.salesControlSurface,
    salesFooterButtonsTextColor: PremiumThemeColors.textPrimary,
    salesFooterButtonsBorderColor:
      PremiumThemeColors.salesFooterButtonsBorder,
    fontSize: 14.0,
    fontFamily: 'Poppins',
    applyChromeToEntireLayout: true,
    isDarkMode: false,
  );

  AppThemeConfig toAppThemeConfig() {
    return AppThemeConfig(
      primaryColor: primaryColor,
      sidebarColor: sidebarColor,
      appbarColor: topbarColor,
      footerColor: footerColor,
      cardColor: cardColor,
      gridBackgroundColor: salesGridBackgroundColor,
      salesDetailColor: salesDetailBackgroundColor,
      textPrimary: textColor,
      textSecondary: PremiumThemeColors.textSecondary,
      applyChromeToEntireLayout: applyChromeToEntireLayout,
    );
  }

  static Color _colorFromStoredValue(dynamic value, Color fallback) {
    if (value is int) return Color(value);
    if (value is num) return Color(value.toInt());
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return fallback;

      final directInt = int.tryParse(trimmed);
      if (directInt != null) {
        return Color(directInt);
      }

      final normalized = trimmed
          .replaceAll('#', '')
          .replaceFirst(RegExp(r'^0x', caseSensitive: false), '')
          .toUpperCase();
      final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
      if (RegExp(r'^[0-9A-F]{8}$').hasMatch(hex)) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    return fallback;
  }

  /// Crear desde Map (para cargar desde DB)
  factory ThemeSettings.fromMap(Map<String, dynamic> map) {
    final defaults = ThemeSettings.defaultSettings;
    final appBarColor = _colorFromStoredValue(
      map['appBarColor'],
      defaults.appBarColor,
    );
    final appBarTextColor = _colorFromStoredValue(
      map['appBarTextColor'],
      defaults.appBarTextColor,
    );

    return ThemeSettings(
      primaryColor: _colorFromStoredValue(
        map['primaryColor'],
        defaults.primaryColor,
      ),
      accentColor: _colorFromStoredValue(
        map['accentColor'],
        defaults.accentColor,
      ),
      backgroundColor: _colorFromStoredValue(
        map['backgroundColor'],
        defaults.backgroundColor,
      ),
      surfaceColor: _colorFromStoredValue(
        map['surfaceColor'],
        defaults.surfaceColor,
      ),
      textColor: _colorFromStoredValue(map['textColor'], defaults.textColor),
      hoverColor: _colorFromStoredValue(map['hoverColor'], defaults.hoverColor),
      appBarColor: appBarColor,
      appBarTextColor: appBarTextColor,
      // Backwards compatible: si no existe topbarColor, heredarlo de appBarColor.
      topbarColor: _colorFromStoredValue(map['topbarColor'], appBarColor),
      topbarTextColor: _colorFromStoredValue(
        map['topbarTextColor'],
        appBarTextColor,
      ),
      cardColor: _colorFromStoredValue(map['cardColor'], defaults.cardColor),
      buttonColor: _colorFromStoredValue(
        map['buttonColor'],
        defaults.buttonColor,
      ),
      successColor: _colorFromStoredValue(
        map['successColor'],
        defaults.successColor,
      ),
      errorColor: _colorFromStoredValue(map['errorColor'], defaults.errorColor),
      warningColor: _colorFromStoredValue(
        map['warningColor'],
        defaults.warningColor,
      ),
      sidebarColor: _colorFromStoredValue(
        map['sidebarColor'],
        defaults.sidebarColor,
      ),
      sidebarTextColor: _colorFromStoredValue(
        map['sidebarTextColor'],
        defaults.sidebarTextColor,
      ),
      sidebarActiveColor: _colorFromStoredValue(
        map['sidebarActiveColor'],
        defaults.sidebarActiveColor,
      ),
      footerColor: _colorFromStoredValue(
        map['footerColor'],
        defaults.footerColor,
      ),
      footerTextColor: _colorFromStoredValue(
        map['footerTextColor'],
        defaults.footerTextColor,
      ),
      backgroundGradientStart: _colorFromStoredValue(
        map['backgroundGradientStart'],
        defaults.backgroundGradientStart,
      ),
      backgroundGradientMid: _colorFromStoredValue(
        map['backgroundGradientMid'],
        defaults.backgroundGradientMid,
      ),
      backgroundGradientEnd: _colorFromStoredValue(
        map['backgroundGradientEnd'],
        defaults.backgroundGradientEnd,
      ),
      salesDetailBackgroundColor: _colorFromStoredValue(
        map['salesDetailBackgroundColor'],
        _colorFromStoredValue(
          map['salesDetailGradientMid'],
          defaults.salesDetailBackgroundColor,
        ),
      ),
      salesDetailGradientStart: _colorFromStoredValue(
        map['salesDetailGradientStart'],
        defaults.salesDetailGradientStart,
      ),
      salesDetailGradientMid: _colorFromStoredValue(
        map['salesDetailGradientMid'],
        defaults.salesDetailGradientMid,
      ),
      salesDetailGradientEnd: _colorFromStoredValue(
        map['salesDetailGradientEnd'],
        defaults.salesDetailGradientEnd,
      ),
      salesDetailTextColor: _colorFromStoredValue(
        map['salesDetailTextColor'],
        defaults.salesDetailTextColor,
      ),
      salesGridBackgroundColor: _colorFromStoredValue(
        map['salesGridBackgroundColor'],
        defaults.salesGridBackgroundColor,
      ),
      salesProductCardBackgroundColor: _colorFromStoredValue(
        map['salesProductCardBackgroundColor'],
        defaults.salesProductCardBackgroundColor,
      ),
      salesProductCardBorderColor: _colorFromStoredValue(
        map['salesProductCardBorderColor'],
        defaults.salesProductCardBorderColor,
      ),
      salesProductCardTextColor: _colorFromStoredValue(
        map['salesProductCardTextColor'],
        defaults.salesProductCardTextColor,
      ),
      salesProductCardAltBackgroundColor: _colorFromStoredValue(
        map['salesProductCardAltBackgroundColor'],
        defaults.salesProductCardAltBackgroundColor,
      ),
      salesProductCardAltBorderColor: _colorFromStoredValue(
        map['salesProductCardAltBorderColor'],
        defaults.salesProductCardAltBorderColor,
      ),
      salesProductCardAltTextColor: _colorFromStoredValue(
        map['salesProductCardAltTextColor'],
        defaults.salesProductCardAltTextColor,
      ),
      salesProductPriceColor: _colorFromStoredValue(
        map['salesProductPriceColor'],
        defaults.salesProductPriceColor,
      ),
      salesControlBarBackgroundColor: _colorFromStoredValue(
        map['salesControlBarBackgroundColor'],
        defaults.salesControlBarBackgroundColor,
      ),
      salesControlBarContentBackgroundColor: _colorFromStoredValue(
        map['salesControlBarContentBackgroundColor'],
        defaults.salesControlBarContentBackgroundColor,
      ),
      salesControlBarBorderColor: _colorFromStoredValue(
        map['salesControlBarBorderColor'],
        defaults.salesControlBarBorderColor,
      ),
      salesControlBarTextColor: _colorFromStoredValue(
        map['salesControlBarTextColor'],
        defaults.salesControlBarTextColor,
      ),
      salesControlBarDropdownBackgroundColor: _colorFromStoredValue(
        map['salesControlBarDropdownBackgroundColor'],
        defaults.salesControlBarDropdownBackgroundColor,
      ),
      salesControlBarDropdownBorderColor: _colorFromStoredValue(
        map['salesControlBarDropdownBorderColor'],
        defaults.salesControlBarDropdownBorderColor,
      ),
      salesControlBarDropdownTextColor: _colorFromStoredValue(
        map['salesControlBarDropdownTextColor'],
        defaults.salesControlBarDropdownTextColor,
      ),
      salesControlBarPopupBackgroundColor: _colorFromStoredValue(
        map['salesControlBarPopupBackgroundColor'],
        defaults.salesControlBarPopupBackgroundColor,
      ),
      salesControlBarPopupTextColor: _colorFromStoredValue(
        map['salesControlBarPopupTextColor'],
        defaults.salesControlBarPopupTextColor,
      ),
      salesControlBarPopupSelectedBackgroundColor: _colorFromStoredValue(
        map['salesControlBarPopupSelectedBackgroundColor'],
        defaults.salesControlBarPopupSelectedBackgroundColor,
      ),
      salesControlBarPopupSelectedTextColor: _colorFromStoredValue(
        map['salesControlBarPopupSelectedTextColor'],
        defaults.salesControlBarPopupSelectedTextColor,
      ),
      salesFooterButtonsBackgroundColor: _colorFromStoredValue(
        map['salesFooterButtonsBackgroundColor'],
        defaults.salesFooterButtonsBackgroundColor,
      ),
      salesFooterButtonsTextColor: _colorFromStoredValue(
        map['salesFooterButtonsTextColor'],
        defaults.salesFooterButtonsTextColor,
      ),
      salesFooterButtonsBorderColor: _colorFromStoredValue(
        map['salesFooterButtonsBorderColor'],
        defaults.salesFooterButtonsBorderColor,
      ),
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? defaults.fontSize,
      fontFamily: map['fontFamily'] as String? ?? defaults.fontFamily,
      applyChromeToEntireLayout:
          (map['applyChromeToEntireLayout'] as int? ??
              (defaults.applyChromeToEntireLayout ? 1 : 0)) ==
          1,
      isDarkMode:
          (map['isDarkMode'] as int? ?? (defaults.isDarkMode ? 1 : 0)) == 1,
    );
  }

  /// Convertir a Map (para guardar en DB)
  Map<String, dynamic> toMap() {
    return {
      'primaryColor': primaryColor.toARGB32(),
      'accentColor': accentColor.toARGB32(),
      'backgroundColor': backgroundColor.toARGB32(),
      'surfaceColor': surfaceColor.toARGB32(),
      'textColor': textColor.toARGB32(),
      'hoverColor': hoverColor.toARGB32(),
      'appBarColor': appBarColor.toARGB32(),
      'appBarTextColor': appBarTextColor.toARGB32(),
      'topbarColor': topbarColor.toARGB32(),
      'topbarTextColor': topbarTextColor.toARGB32(),
      'cardColor': cardColor.toARGB32(),
      'buttonColor': buttonColor.toARGB32(),
      'successColor': successColor.toARGB32(),
      'errorColor': errorColor.toARGB32(),
      'warningColor': warningColor.toARGB32(),
      'sidebarColor': sidebarColor.toARGB32(),
      'sidebarTextColor': sidebarTextColor.toARGB32(),
      'sidebarActiveColor': sidebarActiveColor.toARGB32(),
      'footerColor': footerColor.toARGB32(),
      'footerTextColor': footerTextColor.toARGB32(),
      'backgroundGradientStart': backgroundGradientStart.toARGB32(),
      'backgroundGradientMid': backgroundGradientMid.toARGB32(),
      'backgroundGradientEnd': backgroundGradientEnd.toARGB32(),
      'salesDetailBackgroundColor': salesDetailBackgroundColor.toARGB32(),
      'salesDetailGradientStart': salesDetailGradientStart.toARGB32(),
      'salesDetailGradientMid': salesDetailGradientMid.toARGB32(),
      'salesDetailGradientEnd': salesDetailGradientEnd.toARGB32(),
      'salesDetailTextColor': salesDetailTextColor.toARGB32(),
      'salesGridBackgroundColor': salesGridBackgroundColor.toARGB32(),
      'salesProductCardBackgroundColor': salesProductCardBackgroundColor
          .toARGB32(),
      'salesProductCardBorderColor': salesProductCardBorderColor.toARGB32(),
      'salesProductCardTextColor': salesProductCardTextColor.toARGB32(),
      'salesProductCardAltBackgroundColor': salesProductCardAltBackgroundColor
          .toARGB32(),
      'salesProductCardAltBorderColor': salesProductCardAltBorderColor
          .toARGB32(),
      'salesProductCardAltTextColor': salesProductCardAltTextColor.toARGB32(),
      'salesProductPriceColor': salesProductPriceColor.toARGB32(),
      'salesControlBarBackgroundColor': salesControlBarBackgroundColor
          .toARGB32(),
      'salesControlBarContentBackgroundColor':
          salesControlBarContentBackgroundColor.toARGB32(),
      'salesControlBarBorderColor': salesControlBarBorderColor.toARGB32(),
      'salesControlBarTextColor': salesControlBarTextColor.toARGB32(),
      'salesControlBarDropdownBackgroundColor':
          salesControlBarDropdownBackgroundColor.toARGB32(),
      'salesControlBarDropdownBorderColor': salesControlBarDropdownBorderColor
          .toARGB32(),
      'salesControlBarDropdownTextColor': salesControlBarDropdownTextColor
          .toARGB32(),
      'salesControlBarPopupBackgroundColor': salesControlBarPopupBackgroundColor
          .toARGB32(),
      'salesControlBarPopupTextColor': salesControlBarPopupTextColor.toARGB32(),
      'salesControlBarPopupSelectedBackgroundColor':
          salesControlBarPopupSelectedBackgroundColor.toARGB32(),
      'salesControlBarPopupSelectedTextColor':
          salesControlBarPopupSelectedTextColor.toARGB32(),
      'salesFooterButtonsBackgroundColor': salesFooterButtonsBackgroundColor
          .toARGB32(),
      'salesFooterButtonsTextColor': salesFooterButtonsTextColor.toARGB32(),
      'salesFooterButtonsBorderColor': salesFooterButtonsBorderColor.toARGB32(),
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'applyChromeToEntireLayout': applyChromeToEntireLayout ? 1 : 0,
      'isDarkMode': isDarkMode ? 1 : 0,
    };
  }

  /// Crear copia con modificaciones
  ThemeSettings copyWith({
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? textColor,
    Color? hoverColor,
    Color? appBarColor,
    Color? appBarTextColor,
    Color? topbarColor,
    Color? topbarTextColor,
    Color? cardColor,
    Color? buttonColor,
    Color? successColor,
    Color? errorColor,
    Color? warningColor,
    Color? sidebarColor,
    Color? sidebarTextColor,
    Color? sidebarActiveColor,
    Color? footerColor,
    Color? footerTextColor,
    Color? backgroundGradientStart,
    Color? backgroundGradientMid,
    Color? backgroundGradientEnd,
    Color? salesDetailBackgroundColor,
    Color? salesDetailGradientStart,
    Color? salesDetailGradientMid,
    Color? salesDetailGradientEnd,
    Color? salesDetailTextColor,
    Color? salesGridBackgroundColor,
    Color? salesProductCardBackgroundColor,
    Color? salesProductCardBorderColor,
    Color? salesProductCardTextColor,
    Color? salesProductCardAltBackgroundColor,
    Color? salesProductCardAltBorderColor,
    Color? salesProductCardAltTextColor,
    Color? salesProductPriceColor,
    Color? salesControlBarBackgroundColor,
    Color? salesControlBarContentBackgroundColor,
    Color? salesControlBarBorderColor,
    Color? salesControlBarTextColor,
    Color? salesControlBarDropdownBackgroundColor,
    Color? salesControlBarDropdownBorderColor,
    Color? salesControlBarDropdownTextColor,
    Color? salesControlBarPopupBackgroundColor,
    Color? salesControlBarPopupTextColor,
    Color? salesControlBarPopupSelectedBackgroundColor,
    Color? salesControlBarPopupSelectedTextColor,
    Color? salesFooterButtonsBackgroundColor,
    Color? salesFooterButtonsTextColor,
    Color? salesFooterButtonsBorderColor,
    double? fontSize,
    String? fontFamily,
    bool? applyChromeToEntireLayout,
    bool? isDarkMode,
  }) {
    return ThemeSettings(
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      textColor: textColor ?? this.textColor,
      hoverColor: hoverColor ?? this.hoverColor,
      appBarColor: appBarColor ?? this.appBarColor,
      appBarTextColor: appBarTextColor ?? this.appBarTextColor,
      topbarColor: topbarColor ?? this.topbarColor,
      topbarTextColor: topbarTextColor ?? this.topbarTextColor,
      cardColor: cardColor ?? this.cardColor,
      buttonColor: buttonColor ?? this.buttonColor,
      successColor: successColor ?? this.successColor,
      errorColor: errorColor ?? this.errorColor,
      warningColor: warningColor ?? this.warningColor,
      sidebarColor: sidebarColor ?? this.sidebarColor,
      sidebarTextColor: sidebarTextColor ?? this.sidebarTextColor,
      sidebarActiveColor: sidebarActiveColor ?? this.sidebarActiveColor,
      footerColor: footerColor ?? this.footerColor,
      footerTextColor: footerTextColor ?? this.footerTextColor,
      backgroundGradientStart:
          backgroundGradientStart ?? this.backgroundGradientStart,
      backgroundGradientMid:
          backgroundGradientMid ?? this.backgroundGradientMid,
      backgroundGradientEnd:
          backgroundGradientEnd ?? this.backgroundGradientEnd,
        salesDetailBackgroundColor:
          salesDetailBackgroundColor ?? this.salesDetailBackgroundColor,
      salesDetailGradientStart:
          salesDetailGradientStart ?? this.salesDetailGradientStart,
      salesDetailGradientMid:
          salesDetailGradientMid ?? this.salesDetailGradientMid,
      salesDetailGradientEnd:
          salesDetailGradientEnd ?? this.salesDetailGradientEnd,
      salesDetailTextColor: salesDetailTextColor ?? this.salesDetailTextColor,
      salesGridBackgroundColor:
          salesGridBackgroundColor ?? this.salesGridBackgroundColor,
      salesProductCardBackgroundColor:
          salesProductCardBackgroundColor ??
          this.salesProductCardBackgroundColor,
      salesProductCardBorderColor:
          salesProductCardBorderColor ?? this.salesProductCardBorderColor,
      salesProductCardTextColor:
          salesProductCardTextColor ?? this.salesProductCardTextColor,
      salesProductCardAltBackgroundColor:
          salesProductCardAltBackgroundColor ??
          this.salesProductCardAltBackgroundColor,
      salesProductCardAltBorderColor:
          salesProductCardAltBorderColor ?? this.salesProductCardAltBorderColor,
      salesProductCardAltTextColor:
          salesProductCardAltTextColor ?? this.salesProductCardAltTextColor,
      salesProductPriceColor:
          salesProductPriceColor ?? this.salesProductPriceColor,
      salesControlBarBackgroundColor:
          salesControlBarBackgroundColor ?? this.salesControlBarBackgroundColor,
      salesControlBarContentBackgroundColor:
          salesControlBarContentBackgroundColor ??
          this.salesControlBarContentBackgroundColor,
      salesControlBarBorderColor:
          salesControlBarBorderColor ?? this.salesControlBarBorderColor,
      salesControlBarTextColor:
          salesControlBarTextColor ?? this.salesControlBarTextColor,
      salesControlBarDropdownBackgroundColor:
          salesControlBarDropdownBackgroundColor ??
          this.salesControlBarDropdownBackgroundColor,
      salesControlBarDropdownBorderColor:
          salesControlBarDropdownBorderColor ??
          this.salesControlBarDropdownBorderColor,
      salesControlBarDropdownTextColor:
          salesControlBarDropdownTextColor ??
          this.salesControlBarDropdownTextColor,
      salesControlBarPopupBackgroundColor:
          salesControlBarPopupBackgroundColor ??
          this.salesControlBarPopupBackgroundColor,
      salesControlBarPopupTextColor:
          salesControlBarPopupTextColor ?? this.salesControlBarPopupTextColor,
      salesControlBarPopupSelectedBackgroundColor:
          salesControlBarPopupSelectedBackgroundColor ??
          this.salesControlBarPopupSelectedBackgroundColor,
      salesControlBarPopupSelectedTextColor:
          salesControlBarPopupSelectedTextColor ??
          this.salesControlBarPopupSelectedTextColor,
      salesFooterButtonsBackgroundColor:
          salesFooterButtonsBackgroundColor ??
          this.salesFooterButtonsBackgroundColor,
      salesFooterButtonsTextColor:
          salesFooterButtonsTextColor ?? this.salesFooterButtonsTextColor,
      salesFooterButtonsBorderColor:
          salesFooterButtonsBorderColor ?? this.salesFooterButtonsBorderColor,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      applyChromeToEntireLayout:
          applyChromeToEntireLayout ?? this.applyChromeToEntireLayout,
      isDarkMode: isDarkMode ?? this.isDarkMode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.primaryColor == primaryColor &&
        other.accentColor == accentColor &&
        other.backgroundColor == backgroundColor &&
        other.surfaceColor == surfaceColor &&
        other.textColor == textColor &&
        other.hoverColor == hoverColor &&
        other.appBarColor == appBarColor &&
        other.appBarTextColor == appBarTextColor &&
        other.topbarColor == topbarColor &&
        other.topbarTextColor == topbarTextColor &&
        other.cardColor == cardColor &&
        other.buttonColor == buttonColor &&
        other.successColor == successColor &&
        other.errorColor == errorColor &&
        other.warningColor == warningColor &&
        other.sidebarColor == sidebarColor &&
        other.sidebarTextColor == sidebarTextColor &&
        other.sidebarActiveColor == sidebarActiveColor &&
        other.footerColor == footerColor &&
        other.footerTextColor == footerTextColor &&
        other.backgroundGradientStart == backgroundGradientStart &&
        other.backgroundGradientMid == backgroundGradientMid &&
        other.backgroundGradientEnd == backgroundGradientEnd &&
        other.salesDetailBackgroundColor == salesDetailBackgroundColor &&
        other.salesDetailGradientStart == salesDetailGradientStart &&
        other.salesDetailGradientMid == salesDetailGradientMid &&
        other.salesDetailGradientEnd == salesDetailGradientEnd &&
        other.salesDetailTextColor == salesDetailTextColor &&
        other.salesGridBackgroundColor == salesGridBackgroundColor &&
        other.salesProductCardBackgroundColor ==
            salesProductCardBackgroundColor &&
        other.salesProductCardBorderColor == salesProductCardBorderColor &&
        other.salesProductCardTextColor == salesProductCardTextColor &&
        other.salesProductCardAltBackgroundColor ==
            salesProductCardAltBackgroundColor &&
        other.salesProductCardAltBorderColor ==
            salesProductCardAltBorderColor &&
        other.salesProductCardAltTextColor == salesProductCardAltTextColor &&
        other.salesProductPriceColor == salesProductPriceColor &&
        other.salesControlBarBackgroundColor ==
            salesControlBarBackgroundColor &&
        other.salesControlBarContentBackgroundColor ==
            salesControlBarContentBackgroundColor &&
        other.salesControlBarBorderColor == salesControlBarBorderColor &&
        other.salesControlBarTextColor == salesControlBarTextColor &&
        other.salesControlBarDropdownBackgroundColor ==
            salesControlBarDropdownBackgroundColor &&
        other.salesControlBarDropdownBorderColor ==
            salesControlBarDropdownBorderColor &&
        other.salesControlBarDropdownTextColor ==
            salesControlBarDropdownTextColor &&
        other.salesControlBarPopupBackgroundColor ==
            salesControlBarPopupBackgroundColor &&
        other.salesControlBarPopupTextColor == salesControlBarPopupTextColor &&
        other.salesControlBarPopupSelectedBackgroundColor ==
            salesControlBarPopupSelectedBackgroundColor &&
        other.salesControlBarPopupSelectedTextColor ==
            salesControlBarPopupSelectedTextColor &&
        other.salesFooterButtonsBackgroundColor ==
            salesFooterButtonsBackgroundColor &&
        other.salesFooterButtonsTextColor == salesFooterButtonsTextColor &&
        other.salesFooterButtonsBorderColor == salesFooterButtonsBorderColor &&
        other.fontSize == fontSize &&
        other.fontFamily == fontFamily &&
          other.applyChromeToEntireLayout == applyChromeToEntireLayout &&
        other.isDarkMode == isDarkMode;
  }

  @override
  int get hashCode => Object.hashAll([
    primaryColor,
    accentColor,
    backgroundColor,
    surfaceColor,
    textColor,
    hoverColor,
    appBarColor,
    appBarTextColor,
    topbarColor,
    topbarTextColor,
    cardColor,
    buttonColor,
    successColor,
    errorColor,
    warningColor,
    sidebarColor,
    sidebarTextColor,
    sidebarActiveColor,
    footerColor,
    footerTextColor,
    backgroundGradientStart,
    backgroundGradientMid,
    backgroundGradientEnd,
    salesDetailBackgroundColor,
    salesDetailGradientStart,
    salesDetailGradientMid,
    salesDetailGradientEnd,
    salesDetailTextColor,
    salesGridBackgroundColor,
    salesProductCardBackgroundColor,
    salesProductCardBorderColor,
    salesProductCardTextColor,
    salesProductCardAltBackgroundColor,
    salesProductCardAltBorderColor,
    salesProductCardAltTextColor,
    salesProductPriceColor,
    salesControlBarBackgroundColor,
    salesControlBarContentBackgroundColor,
    salesControlBarBorderColor,
    salesControlBarTextColor,
    salesControlBarDropdownBackgroundColor,
    salesControlBarDropdownBorderColor,
    salesControlBarDropdownTextColor,
    salesControlBarPopupBackgroundColor,
    salesControlBarPopupTextColor,
    salesControlBarPopupSelectedBackgroundColor,
    salesControlBarPopupSelectedTextColor,
    salesFooterButtonsBackgroundColor,
    salesFooterButtonsTextColor,
    salesFooterButtonsBorderColor,
    fontSize,
    fontFamily,
    applyChromeToEntireLayout,
    isDarkMode,
  ]);
}
