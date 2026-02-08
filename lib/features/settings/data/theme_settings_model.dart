import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

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
    primaryColor: AppColors.brandBlue,
    accentColor: AppColors.brandBlue,
    backgroundColor: AppColors.bgLight,
    surfaceColor: AppColors.surfaceLight,
    textColor: AppColors.textLight,
    hoverColor: AppColors.brandBlueAccent,
    appBarColor: AppColors.surfaceDark,
    appBarTextColor: AppColors.textLight,
    cardColor: AppColors.surfaceLight,
    buttonColor: AppColors.brandBlueLight,
    successColor: AppColors.success,
    errorColor: AppColors.error,
    warningColor: AppColors.warning,
    sidebarColor: AppColors.bgDark,
    sidebarTextColor: AppColors.textLight,
    sidebarActiveColor: AppColors.brandBlueLight,
    footerColor: AppColors.bgDark,
    footerTextColor: AppColors.textLight,
    backgroundGradientStart: AppColors.surfaceLight,
    backgroundGradientMid: AppColors.surfaceLight,
    backgroundGradientEnd: AppColors.surfaceLight,
    salesDetailGradientStart: AppColors.surfaceDark,
    salesDetailGradientMid: AppColors.surfaceDarkVariant,
    salesDetailGradientEnd: AppColors.surfaceDark,
    salesDetailTextColor: AppColors.textLight,
    salesGridBackgroundColor: AppColors.surfaceLightVariant,
    salesProductCardBackgroundColor: AppColors.surfaceDark,
    salesProductCardBorderColor: AppColors.surfaceDark,
    salesProductCardTextColor: AppColors.textLight,
    salesProductCardAltBackgroundColor: AppColors.surfaceDarkVariant,
    salesProductCardAltBorderColor: AppColors.surfaceDark,
    salesProductCardAltTextColor: AppColors.textLight,
    salesProductPriceColor: AppColors.brandBlueLight,
    salesControlBarBackgroundColor: AppColors.surfaceDark,
    salesControlBarContentBackgroundColor: AppColors.surfaceDarkVariant,
    salesControlBarBorderColor: AppColors.surfaceDark,
    salesControlBarTextColor: AppColors.textLight,
    salesControlBarDropdownBackgroundColor: AppColors.surfaceDark,
    salesControlBarDropdownBorderColor: AppColors.surfaceDarkVariant,
    salesControlBarDropdownTextColor: AppColors.textLight,
    salesControlBarPopupBackgroundColor: AppColors.surfaceDark,
    salesControlBarPopupTextColor: AppColors.textLight,
    salesControlBarPopupSelectedBackgroundColor: AppColors.surfaceDarkVariant,
    salesControlBarPopupSelectedTextColor: AppColors.textLight,
    salesFooterButtonsBackgroundColor: AppColors.surfaceDark,
    salesFooterButtonsTextColor: AppColors.textLight,
    salesFooterButtonsBorderColor: AppColors.surfaceDarkVariant,
    fontSize: 14.0,
    fontFamily: 'Poppins',
    isDarkMode: true,
  );

  /// Crear desde Map (para cargar desde DB)
  factory ThemeSettings.fromMap(Map<String, dynamic> map) {
    return ThemeSettings(
      primaryColor:
          Color(map['primaryColor'] as int? ?? AppColors.brandBlueLight.value),
      accentColor: Color(map['accentColor'] as int? ?? AppColors.brandBlue.value),
      backgroundColor:
          Color(map['backgroundColor'] as int? ?? AppColors.bgLight.value),
      surfaceColor:
          Color(map['surfaceColor'] as int? ?? AppColors.surfaceLight.value),
      textColor: Color(map['textColor'] as int? ?? AppColors.textLight.value),
      hoverColor:
          Color(map['hoverColor'] as int? ?? AppColors.brandBlueAccent.value),
      appBarColor:
          Color(map['appBarColor'] as int? ?? AppColors.surfaceDark.value),
      appBarTextColor:
          Color(map['appBarTextColor'] as int? ?? AppColors.textLight.value),
      cardColor: Color(map['cardColor'] as int? ?? AppColors.surfaceLight.value),
      buttonColor:
          Color(map['buttonColor'] as int? ?? AppColors.brandBlueLight.value),
      successColor: Color(map['successColor'] as int? ?? AppColors.success.value),
      errorColor: Color(map['errorColor'] as int? ?? AppColors.error.value),
      warningColor:
          Color(map['warningColor'] as int? ?? AppColors.warning.value),
      sidebarColor: Color(map['sidebarColor'] as int? ?? AppColors.bgDark.value),
      sidebarTextColor:
          Color(map['sidebarTextColor'] as int? ?? AppColors.textLight.value),
      sidebarActiveColor: Color(
        map['sidebarActiveColor'] as int? ?? AppColors.brandBlueLight.value,
      ),
      footerColor: Color(map['footerColor'] as int? ?? AppColors.bgDark.value),
      footerTextColor:
          Color(map['footerTextColor'] as int? ?? AppColors.textLight.value),
      backgroundGradientStart: Color(
        map['backgroundGradientStart'] as int? ?? AppColors.surfaceLight.value,
      ),
      backgroundGradientMid: Color(
        map['backgroundGradientMid'] as int? ?? AppColors.surfaceLight.value,
      ),
      backgroundGradientEnd: Color(
        map['backgroundGradientEnd'] as int? ?? AppColors.surfaceLight.value,
      ),
      salesDetailGradientStart: Color(
        map['salesDetailGradientStart'] as int? ?? AppColors.surfaceDark.value,
      ),
      salesDetailGradientMid: Color(
        map['salesDetailGradientMid'] as int? ?? AppColors.surfaceDarkVariant.value,
      ),
      salesDetailGradientEnd: Color(
        map['salesDetailGradientEnd'] as int? ?? AppColors.surfaceDark.value,
      ),
      salesDetailTextColor: Color(
        map['salesDetailTextColor'] as int? ?? AppColors.textLight.value,
      ),
      salesGridBackgroundColor: Color(
        map['salesGridBackgroundColor'] as int? ??
            AppColors.surfaceLightVariant.value,
      ),
      salesProductCardBackgroundColor: Color(
        map['salesProductCardBackgroundColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesProductCardBorderColor: Color(
        map['salesProductCardBorderColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesProductCardTextColor: Color(
        map['salesProductCardTextColor'] as int? ?? AppColors.textLight.value,
      ),
      salesProductCardAltBackgroundColor: Color(
        map['salesProductCardAltBackgroundColor'] as int? ??
            AppColors.surfaceDarkVariant.value,
      ),
      salesProductCardAltBorderColor: Color(
        map['salesProductCardAltBorderColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesProductCardAltTextColor: Color(
        map['salesProductCardAltTextColor'] as int? ?? AppColors.textLight.value,
      ),
      salesProductPriceColor: Color(
        map['salesProductPriceColor'] as int? ??
            AppColors.brandBlueLight.value,
      ),
      salesControlBarBackgroundColor: Color(
        map['salesControlBarBackgroundColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesControlBarContentBackgroundColor: Color(
        map['salesControlBarContentBackgroundColor'] as int? ??
            AppColors.surfaceDarkVariant.value,
      ),
      salesControlBarBorderColor: Color(
        map['salesControlBarBorderColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesControlBarTextColor: Color(
        map['salesControlBarTextColor'] as int? ?? AppColors.textLight.value,
      ),
      salesControlBarDropdownBackgroundColor: Color(
        map['salesControlBarDropdownBackgroundColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesControlBarDropdownBorderColor: Color(
        map['salesControlBarDropdownBorderColor'] as int? ??
            AppColors.surfaceDarkVariant.value,
      ),
      salesControlBarDropdownTextColor: Color(
        map['salesControlBarDropdownTextColor'] as int? ??
            AppColors.textLight.value,
      ),
      salesControlBarPopupBackgroundColor: Color(
        map['salesControlBarPopupBackgroundColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesControlBarPopupTextColor: Color(
        map['salesControlBarPopupTextColor'] as int? ??
            AppColors.textLight.value,
      ),
      salesControlBarPopupSelectedBackgroundColor: Color(
        map['salesControlBarPopupSelectedBackgroundColor'] as int? ??
            AppColors.surfaceDarkVariant.value,
      ),
      salesControlBarPopupSelectedTextColor: Color(
        map['salesControlBarPopupSelectedTextColor'] as int? ??
            AppColors.textLight.value,
      ),
      salesFooterButtonsBackgroundColor: Color(
        map['salesFooterButtonsBackgroundColor'] as int? ??
            AppColors.surfaceDark.value,
      ),
      salesFooterButtonsTextColor: Color(
        map['salesFooterButtonsTextColor'] as int? ?? AppColors.textLight.value,
      ),
      salesFooterButtonsBorderColor: Color(
        map['salesFooterButtonsBorderColor'] as int? ??
            AppColors.surfaceDarkVariant.value,
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
