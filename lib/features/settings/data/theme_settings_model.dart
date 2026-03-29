import 'package:flutter/material.dart';

class PremiumThemeColors {
  PremiumThemeColors._();

  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF1F5F9);
  static const Color sidebarBackground = Color(0xFF0B1220);
  static const Color sidebarHover = Color(0xFF162033);
  static const Color sidebarActive = Color(0xFF2563EB);
  static const Color sidebarText = Color(0xFFE5EDF7);
  static const Color chromeBackground = Color(0xFF0F172A);
  static const Color chromeText = Color(0xFFF8FAFC);
  static const Color appBarBorder = Color(0xFFE2E8F0);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color gradientStart = Color(0xFFFFFFFF);
  static const Color gradientMid = Color(0xFFF8FAFC);
  static const Color gradientEnd = Color(0xFFEAF2FF);
  static const Color selectionSurface = Color(0xFFEFF6FF);
  static const Color darkBackground = Color(0xFF020617);
  static const Color darkSurface = Color(0xFF0F172A);
  static const Color darkSurfaceAlt = Color(0xFF111827);
  static const Color darkText = Color(0xFFE2E8F0);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
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
    topbarColor: PremiumThemeColors.chromeBackground,
    topbarTextColor: PremiumThemeColors.chromeText,
    cardColor: PremiumThemeColors.surface,
    buttonColor: PremiumThemeColors.primary,
    successColor: PremiumThemeColors.success,
    errorColor: PremiumThemeColors.error,
    warningColor: PremiumThemeColors.warning,
    sidebarColor: PremiumThemeColors.sidebarBackground,
    sidebarTextColor: PremiumThemeColors.sidebarText,
    sidebarActiveColor: PremiumThemeColors.primary,
    footerColor: PremiumThemeColors.chromeBackground,
    footerTextColor: PremiumThemeColors.chromeText,
    backgroundGradientStart: PremiumThemeColors.gradientStart,
    backgroundGradientMid: PremiumThemeColors.gradientMid,
    backgroundGradientEnd: PremiumThemeColors.gradientEnd,
    salesDetailGradientStart: PremiumThemeColors.chromeBackground,
    salesDetailGradientMid: PremiumThemeColors.darkSurfaceAlt,
    salesDetailGradientEnd: PremiumThemeColors.chromeBackground,
    salesDetailTextColor: Colors.white,
    salesGridBackgroundColor: PremiumThemeColors.background,
    salesProductCardBackgroundColor: PremiumThemeColors.surface,
    salesProductCardBorderColor: PremiumThemeColors.appBarBorder,
    salesProductCardTextColor: PremiumThemeColors.textPrimary,
    salesProductCardAltBackgroundColor: PremiumThemeColors.surfaceAlt,
    salesProductCardAltBorderColor: PremiumThemeColors.appBarBorder,
    salesProductCardAltTextColor: PremiumThemeColors.textPrimary,
    salesProductPriceColor: PremiumThemeColors.primary,
    salesControlBarBackgroundColor: PremiumThemeColors.surface,
    salesControlBarContentBackgroundColor: PremiumThemeColors.background,
    salesControlBarBorderColor: PremiumThemeColors.appBarBorder,
    salesControlBarTextColor: PremiumThemeColors.textPrimary,
    salesControlBarDropdownBackgroundColor: PremiumThemeColors.surface,
    salesControlBarDropdownBorderColor: PremiumThemeColors.appBarBorder,
    salesControlBarDropdownTextColor: PremiumThemeColors.textPrimary,
    salesControlBarPopupBackgroundColor: PremiumThemeColors.surface,
    salesControlBarPopupTextColor: PremiumThemeColors.textPrimary,
    salesControlBarPopupSelectedBackgroundColor:
        PremiumThemeColors.selectionSurface,
    salesControlBarPopupSelectedTextColor: PremiumThemeColors.primaryDark,
    salesFooterButtonsBackgroundColor: PremiumThemeColors.surface,
    salesFooterButtonsTextColor: PremiumThemeColors.textPrimary,
    salesFooterButtonsBorderColor: PremiumThemeColors.appBarBorder,
    fontSize: 14.0,
    fontFamily: 'Poppins',
    isDarkMode: false,
  );

  /// Crear desde Map (para cargar desde DB)
  factory ThemeSettings.fromMap(Map<String, dynamic> map) {
    final defaults = ThemeSettings.defaultSettings;
    final appBarColor = Color(
      map['appBarColor'] as int? ?? defaults.appBarColor.value,
    );
    final appBarTextColor = Color(
      map['appBarTextColor'] as int? ?? defaults.appBarTextColor.value,
    );

    return ThemeSettings(
      primaryColor: Color(
        map['primaryColor'] as int? ?? defaults.primaryColor.value,
      ),
      accentColor: Color(
        map['accentColor'] as int? ?? defaults.accentColor.value,
      ),
      backgroundColor: Color(
        map['backgroundColor'] as int? ?? defaults.backgroundColor.value,
      ),
      surfaceColor: Color(
        map['surfaceColor'] as int? ?? defaults.surfaceColor.value,
      ),
      textColor: Color(map['textColor'] as int? ?? defaults.textColor.value),
      hoverColor: Color(map['hoverColor'] as int? ?? defaults.hoverColor.value),
      appBarColor: appBarColor,
      appBarTextColor: appBarTextColor,
      // Backwards compatible: si no existe topbarColor, heredarlo de appBarColor.
      topbarColor: Color(map['topbarColor'] as int? ?? appBarColor.value),
      topbarTextColor: Color(
        map['topbarTextColor'] as int? ?? appBarTextColor.value,
      ),
      cardColor: Color(map['cardColor'] as int? ?? defaults.cardColor.value),
      buttonColor: Color(
        map['buttonColor'] as int? ?? defaults.buttonColor.value,
      ),
      successColor: Color(
        map['successColor'] as int? ?? defaults.successColor.value,
      ),
      errorColor: Color(map['errorColor'] as int? ?? defaults.errorColor.value),
      warningColor: Color(
        map['warningColor'] as int? ?? defaults.warningColor.value,
      ),
      sidebarColor: Color(
        map['sidebarColor'] as int? ?? defaults.sidebarColor.value,
      ),
      sidebarTextColor: Color(
        map['sidebarTextColor'] as int? ?? defaults.sidebarTextColor.value,
      ),
      sidebarActiveColor: Color(
        map['sidebarActiveColor'] as int? ?? defaults.sidebarActiveColor.value,
      ),
      footerColor: Color(
        map['footerColor'] as int? ?? defaults.footerColor.value,
      ),
      footerTextColor: Color(
        map['footerTextColor'] as int? ?? defaults.footerTextColor.value,
      ),
      backgroundGradientStart: Color(
        map['backgroundGradientStart'] as int? ??
            defaults.backgroundGradientStart.value,
      ),
      backgroundGradientMid: Color(
        map['backgroundGradientMid'] as int? ??
            defaults.backgroundGradientMid.value,
      ),
      backgroundGradientEnd: Color(
        map['backgroundGradientEnd'] as int? ??
            defaults.backgroundGradientEnd.value,
      ),
      salesDetailGradientStart: Color(
        map['salesDetailGradientStart'] as int? ??
            defaults.salesDetailGradientStart.value,
      ),
      salesDetailGradientMid: Color(
        map['salesDetailGradientMid'] as int? ??
            defaults.salesDetailGradientMid.value,
      ),
      salesDetailGradientEnd: Color(
        map['salesDetailGradientEnd'] as int? ??
            defaults.salesDetailGradientEnd.value,
      ),
      salesDetailTextColor: Color(
        map['salesDetailTextColor'] as int? ??
            defaults.salesDetailTextColor.value,
      ),
      salesGridBackgroundColor: Color(
        map['salesGridBackgroundColor'] as int? ??
            defaults.salesGridBackgroundColor.value,
      ),
      salesProductCardBackgroundColor: Color(
        map['salesProductCardBackgroundColor'] as int? ??
            defaults.salesProductCardBackgroundColor.value,
      ),
      salesProductCardBorderColor: Color(
        map['salesProductCardBorderColor'] as int? ??
            defaults.salesProductCardBorderColor.value,
      ),
      salesProductCardTextColor: Color(
        map['salesProductCardTextColor'] as int? ??
            defaults.salesProductCardTextColor.value,
      ),
      salesProductCardAltBackgroundColor: Color(
        map['salesProductCardAltBackgroundColor'] as int? ??
            defaults.salesProductCardAltBackgroundColor.value,
      ),
      salesProductCardAltBorderColor: Color(
        map['salesProductCardAltBorderColor'] as int? ??
            defaults.salesProductCardAltBorderColor.value,
      ),
      salesProductCardAltTextColor: Color(
        map['salesProductCardAltTextColor'] as int? ??
            defaults.salesProductCardAltTextColor.value,
      ),
      salesProductPriceColor: Color(
        map['salesProductPriceColor'] as int? ??
            defaults.salesProductPriceColor.value,
      ),
      salesControlBarBackgroundColor: Color(
        map['salesControlBarBackgroundColor'] as int? ??
            defaults.salesControlBarBackgroundColor.value,
      ),
      salesControlBarContentBackgroundColor: Color(
        map['salesControlBarContentBackgroundColor'] as int? ??
            defaults.salesControlBarContentBackgroundColor.value,
      ),
      salesControlBarBorderColor: Color(
        map['salesControlBarBorderColor'] as int? ??
            defaults.salesControlBarBorderColor.value,
      ),
      salesControlBarTextColor: Color(
        map['salesControlBarTextColor'] as int? ??
            defaults.salesControlBarTextColor.value,
      ),
      salesControlBarDropdownBackgroundColor: Color(
        map['salesControlBarDropdownBackgroundColor'] as int? ??
            defaults.salesControlBarDropdownBackgroundColor.value,
      ),
      salesControlBarDropdownBorderColor: Color(
        map['salesControlBarDropdownBorderColor'] as int? ??
            defaults.salesControlBarDropdownBorderColor.value,
      ),
      salesControlBarDropdownTextColor: Color(
        map['salesControlBarDropdownTextColor'] as int? ??
            defaults.salesControlBarDropdownTextColor.value,
      ),
      salesControlBarPopupBackgroundColor: Color(
        map['salesControlBarPopupBackgroundColor'] as int? ??
            defaults.salesControlBarPopupBackgroundColor.value,
      ),
      salesControlBarPopupTextColor: Color(
        map['salesControlBarPopupTextColor'] as int? ??
            defaults.salesControlBarPopupTextColor.value,
      ),
      salesControlBarPopupSelectedBackgroundColor: Color(
        map['salesControlBarPopupSelectedBackgroundColor'] as int? ??
            defaults.salesControlBarPopupSelectedBackgroundColor.value,
      ),
      salesControlBarPopupSelectedTextColor: Color(
        map['salesControlBarPopupSelectedTextColor'] as int? ??
            defaults.salesControlBarPopupSelectedTextColor.value,
      ),
      salesFooterButtonsBackgroundColor: Color(
        map['salesFooterButtonsBackgroundColor'] as int? ??
            defaults.salesFooterButtonsBackgroundColor.value,
      ),
      salesFooterButtonsTextColor: Color(
        map['salesFooterButtonsTextColor'] as int? ??
            defaults.salesFooterButtonsTextColor.value,
      ),
      salesFooterButtonsBorderColor: Color(
        map['salesFooterButtonsBorderColor'] as int? ??
            defaults.salesFooterButtonsBorderColor.value,
      ),
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? defaults.fontSize,
      fontFamily: map['fontFamily'] as String? ?? defaults.fontFamily,
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
    isDarkMode,
  ]);
}
