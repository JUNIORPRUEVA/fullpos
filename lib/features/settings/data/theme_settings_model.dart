import 'package:flutter/material.dart';

/// Modelo para la configuraciÃ³n del tema personalizado
class ThemeSettings {
  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color textColor;
  final Color hoverColor;
  final Color appBarColor;
  final Color appBarTextColor;
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

  /// Valores por defecto (tema Dominicano Dark)
  static const ThemeSettings defaultSettings = ThemeSettings(
    primaryColor: Color(0xFFF4B400),
    accentColor: Color(0xFF28C76F),
    backgroundColor: Color(0xFF0A1F44),
    surfaceColor: Color(0xFF1E4FA3),
    textColor: Color(0xFFFFFFFF),
    hoverColor: Color(0xFFF4B400),
    appBarColor: Color(0xFF0A1F44),
    appBarTextColor: Color(0xFFFFFFFF),
    cardColor: Color(0xFF1E4FA3),
    buttonColor: Color(0xFFF4B400),
    successColor: Color(0xFF28C76F),
    errorColor: Color(0xFFEA5455),
    warningColor: Color(0xFFF4B400),
    sidebarColor: Color(0xFF0A1F44),
    sidebarTextColor: Color(0xFFB0C4DE),
    sidebarActiveColor: Color(0xFFF4B400),
    footerColor: Color(0xFF0A1F44),
    footerTextColor: Color(0xFFB0C4DE),
    backgroundGradientStart: Color(0xFF0A1F44),
    backgroundGradientMid: Color(0xFF153A75),
    backgroundGradientEnd: Color(0xFF153A75),
    salesDetailGradientStart: Color(0xFF1E4FA3),
    salesDetailGradientMid: Color(0xFF153A75),
    salesDetailGradientEnd: Color(0xFF1E4FA3),
    salesDetailTextColor: Color(0xFFFFFFFF),
    salesGridBackgroundColor: Color(0x00000000),
    salesProductCardBackgroundColor: Color(0x00000000),
    salesProductCardBorderColor: Color(0x00000000),
    salesProductCardTextColor: Color(0x00000000),
    salesProductCardAltBackgroundColor: Color(0x00000000),
    salesProductCardAltBorderColor: Color(0x00000000),
    salesProductCardAltTextColor: Color(0x00000000),
    salesProductPriceColor: Color(0x00000000),
    salesControlBarBackgroundColor: Color(0x00000000),
    salesControlBarContentBackgroundColor: Color(0x00000000),
    salesControlBarBorderColor: Color(0x00000000),
    salesControlBarTextColor: Color(0x00000000),
    salesControlBarDropdownBackgroundColor: Color(0x00000000),
    salesControlBarDropdownBorderColor: Color(0x00000000),
    salesControlBarDropdownTextColor: Color(0x00000000),
    salesControlBarPopupBackgroundColor: Color(0x00000000),
    salesControlBarPopupTextColor: Color(0x00000000),
    salesControlBarPopupSelectedBackgroundColor: Color(0x00000000),
    salesControlBarPopupSelectedTextColor: Color(0x00000000),
    salesFooterButtonsBackgroundColor: Color(0x00000000),
    salesFooterButtonsTextColor: Color(0x00000000),
    salesFooterButtonsBorderColor: Color(0x00000000),
    fontSize: 14.0,
    fontFamily: 'Poppins',
    isDarkMode: true,
  );

  /// Crear desde Map (para cargar desde DB)
  factory ThemeSettings.fromMap(Map<String, dynamic> map) {
    return ThemeSettings(
      primaryColor: Color(map['primaryColor'] as int? ?? 0xFFF4B400),
      accentColor: Color(map['accentColor'] as int? ?? 0xFF28C76F),
      backgroundColor: Color(map['backgroundColor'] as int? ?? 0xFF0A1F44),
      surfaceColor: Color(map['surfaceColor'] as int? ?? 0xFF1E4FA3),
      textColor: Color(map['textColor'] as int? ?? 0xFFFFFFFF),
      hoverColor: Color(map['hoverColor'] as int? ?? 0xFFF4B400),
      appBarColor: Color(map['appBarColor'] as int? ?? 0xFF0A1F44),
      appBarTextColor: Color(map['appBarTextColor'] as int? ?? 0xFFFFFFFF),
      cardColor: Color(map['cardColor'] as int? ?? 0xFF1E4FA3),
      buttonColor: Color(map['buttonColor'] as int? ?? 0xFFF4B400),
      successColor: Color(map['successColor'] as int? ?? 0xFF28C76F),
      errorColor: Color(map['errorColor'] as int? ?? 0xFFEA5455),
      warningColor: Color(map['warningColor'] as int? ?? 0xFFF4B400),
      sidebarColor: Color(map['sidebarColor'] as int? ?? 0xFF0A1F44),
      sidebarTextColor: Color(map['sidebarTextColor'] as int? ?? 0xFFB0C4DE),
      sidebarActiveColor: Color(
        map['sidebarActiveColor'] as int? ?? 0xFFF4B400,
      ),
      footerColor: Color(map['footerColor'] as int? ?? 0xFF0A1F44),
      footerTextColor: Color(map['footerTextColor'] as int? ?? 0xFFB0C4DE),
      backgroundGradientStart: Color(
        map['backgroundGradientStart'] as int? ?? 0xFF0A1F44,
      ),
      backgroundGradientMid: Color(
        map['backgroundGradientMid'] as int? ?? 0xFF153A75,
      ),
      backgroundGradientEnd: Color(
        map['backgroundGradientEnd'] as int? ?? 0xFF153A75,
      ),
      salesDetailGradientStart: Color(
        map['salesDetailGradientStart'] as int? ?? 0xFF1E4FA3,
      ),
      salesDetailGradientMid: Color(
        map['salesDetailGradientMid'] as int? ?? 0xFF153A75,
      ),
      salesDetailGradientEnd: Color(
        map['salesDetailGradientEnd'] as int? ?? 0xFF1E4FA3,
      ),
      salesDetailTextColor: Color(
        map['salesDetailTextColor'] as int? ?? 0xFFFFFFFF,
      ),
      salesGridBackgroundColor: Color(
        map['salesGridBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesProductCardBackgroundColor: Color(
        map['salesProductCardBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesProductCardBorderColor: Color(
        map['salesProductCardBorderColor'] as int? ?? 0x00000000,
      ),
      salesProductCardTextColor: Color(
        map['salesProductCardTextColor'] as int? ?? 0x00000000,
      ),
      salesProductCardAltBackgroundColor: Color(
        map['salesProductCardAltBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesProductCardAltBorderColor: Color(
        map['salesProductCardAltBorderColor'] as int? ?? 0x00000000,
      ),
      salesProductCardAltTextColor: Color(
        map['salesProductCardAltTextColor'] as int? ?? 0x00000000,
      ),
      salesProductPriceColor: Color(
        map['salesProductPriceColor'] as int? ?? 0x00000000,
      ),
      salesControlBarBackgroundColor: Color(
        map['salesControlBarBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesControlBarContentBackgroundColor: Color(
        map['salesControlBarContentBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesControlBarBorderColor: Color(
        map['salesControlBarBorderColor'] as int? ?? 0x00000000,
      ),
      salesControlBarTextColor: Color(
        map['salesControlBarTextColor'] as int? ?? 0x00000000,
      ),
      salesControlBarDropdownBackgroundColor: Color(
        map['salesControlBarDropdownBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesControlBarDropdownBorderColor: Color(
        map['salesControlBarDropdownBorderColor'] as int? ?? 0x00000000,
      ),
      salesControlBarDropdownTextColor: Color(
        map['salesControlBarDropdownTextColor'] as int? ?? 0x00000000,
      ),
      salesControlBarPopupBackgroundColor: Color(
        map['salesControlBarPopupBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesControlBarPopupTextColor: Color(
        map['salesControlBarPopupTextColor'] as int? ?? 0x00000000,
      ),
      salesControlBarPopupSelectedBackgroundColor: Color(
        map['salesControlBarPopupSelectedBackgroundColor'] as int? ??
            0x00000000,
      ),
      salesControlBarPopupSelectedTextColor: Color(
        map['salesControlBarPopupSelectedTextColor'] as int? ?? 0x00000000,
      ),
      salesFooterButtonsBackgroundColor: Color(
        map['salesFooterButtonsBackgroundColor'] as int? ?? 0x00000000,
      ),
      salesFooterButtonsTextColor: Color(
        map['salesFooterButtonsTextColor'] as int? ?? 0x00000000,
      ),
      salesFooterButtonsBorderColor: Color(
        map['salesFooterButtonsBorderColor'] as int? ?? 0x00000000,
      ),
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 14.0,
      fontFamily: map['fontFamily'] as String? ?? 'Roboto',
      isDarkMode: (map['isDarkMode'] as int? ?? 0) == 1,
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

/// Temas predefinidos para selecciÃ³n rÃ¡pida
class PresetThemes {
  PresetThemes._();

  static const Map<String, ThemeSettings> presets = {
    'default': ThemeSettings.defaultSettings,
    'sand': ThemeSettings(
      primaryColor: Color(0xFF1E5FD9),
      accentColor: Color(0xFFF4B400),
      backgroundColor: Color(0xFFF5F7FB),
      surfaceColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF1F2937),
      hoverColor: Color(0xFFF4B400),
      appBarColor: Color(0xFF1E5FD9),
      appBarTextColor: Color(0xFFFFFFFF),
      cardColor: Color(0xFFFFFFFF),
      buttonColor: Color(0xFF1E5FD9),
      successColor: Color(0xFF16A34A),
      errorColor: Color(0xFFDC2626),
      warningColor: Color(0xFFF59E0B),
      sidebarColor: Color(0xFF0A1F44),
      sidebarTextColor: Color(0xFFE5EEFF),
      sidebarActiveColor: Color(0xFFF4B400),
      footerColor: Color(0xFF0A1F44),
      footerTextColor: Color(0xFFCBD5E1),
      backgroundGradientStart: Color(0xFFF5F7FB),
      backgroundGradientMid: Color(0xFFE5ECF8),
      backgroundGradientEnd: Color(0xFFFFFFFF),
      salesDetailGradientStart: Color(0xFFF5F7FB),
      salesDetailGradientMid: Color(0xFFE5ECF8),
      salesDetailGradientEnd: Color(0xFFF5F7FB),
      salesDetailTextColor: Color(0xFF1F2937),
      salesGridBackgroundColor: Color(0x00000000),
      salesProductCardBackgroundColor: Color(0x00000000),
      salesProductCardBorderColor: Color(0x00000000),
      salesProductCardTextColor: Color(0x00000000),
      salesProductCardAltBackgroundColor: Color(0x00000000),
      salesProductCardAltBorderColor: Color(0x00000000),
      salesProductCardAltTextColor: Color(0x00000000),
      salesProductPriceColor: Color(0x00000000),
      salesControlBarBackgroundColor: Color(0x00000000),
      salesControlBarContentBackgroundColor: Color(0x00000000),
      salesControlBarBorderColor: Color(0x00000000),
      salesControlBarTextColor: Color(0x00000000),
      salesControlBarDropdownBackgroundColor: Color(0x00000000),
      salesControlBarDropdownBorderColor: Color(0x00000000),
      salesControlBarDropdownTextColor: Color(0x00000000),
      salesControlBarPopupBackgroundColor: Color(0x00000000),
      salesControlBarPopupTextColor: Color(0x00000000),
      salesControlBarPopupSelectedBackgroundColor: Color(0x00000000),
      salesControlBarPopupSelectedTextColor: Color(0x00000000),
      salesFooterButtonsBackgroundColor: Color(0x00000000),
      salesFooterButtonsTextColor: Color(0x00000000),
      salesFooterButtonsBorderColor: Color(0x00000000),
      fontSize: 14.0,
      fontFamily: 'Poppins',
      isDarkMode: false,
    ),
  };

  static List<String> get presetNames => presets.keys.toList();

  static ThemeSettings getPreset(String name) {
    return presets[name] ?? ThemeSettings.defaultSettings;
  }
}
