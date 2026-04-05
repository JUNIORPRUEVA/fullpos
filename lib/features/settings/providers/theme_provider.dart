import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/theme_settings_model.dart';
import '../data/theme_settings_repository.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_gradient_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/theme/sales_products_theme.dart';
import '../../../core/theme/sales_page_theme.dart';
import '../../../core/session/session_manager.dart';

/// Notifier para manejar el estado del tema
class ThemeNotifier extends StateNotifier<ThemeSettings> {
  final ThemeSettingsRepository _repository;
  StreamSubscription<void>? _sessionSub;

  ThemeNotifier(this._repository) : super(ThemeSettings.defaultSettings) {
    _loadSettings();

    // Live update across tenants: when login/logout or companyId changes,
    // reload theme overrides for the active company.
    _sessionSub = SessionManager.changes.listen((_) {
      unawaited(_loadSettings());
    });
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _sessionSub = null;
    super.dispose();
  }

  /// Cargar configuraciÃ³n guardada
  Future<void> _loadSettings() async {
    final loaded = await _repository.loadThemeSettings();
    state = loaded;
  }

  /// Actualizar color primario
  Future<void> updatePrimaryColor(Color color) async {
    final newSettings = state.copyWith(primaryColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de acento
  Future<void> updateAccentColor(Color color) async {
    final newSettings = state.copyWith(accentColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de fondo
  Future<void> updateBackgroundColor(Color color) async {
    final newSettings = state.copyWith(backgroundColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de superficie
  Future<void> updateSurfaceColor(Color color) async {
    final newSettings = state.copyWith(surfaceColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de texto
  Future<void> updateTextColor(Color color) async {
    final newSettings = state.copyWith(textColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de hover general (InkWell/Sidebar, etc.)
  Future<void> updateHoverColor(Color color) async {
    final newSettings = state.copyWith(hoverColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del AppBar
  Future<void> updateAppBarColor(Color color) async {
    final newSettings = state.copyWith(appBarColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del texto del AppBar
  Future<void> updateAppBarTextColor(Color color) async {
    final newSettings = state.copyWith(appBarTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del AppBar principal (Topbar del layout)
  Future<void> updateTopbarColor(Color color) async {
    final newSettings = state.copyWith(topbarColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del texto/iconos del AppBar principal (Topbar)
  Future<void> updateTopbarTextColor(Color color) async {
    final newSettings = state.copyWith(topbarTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de cards
  Future<void> updateCardColor(Color color) async {
    final newSettings = state.copyWith(cardColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de botones
  Future<void> updateButtonColor(Color color) async {
    final newSettings = state.copyWith(buttonColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de Ã©xito
  Future<void> updateSuccessColor(Color color) async {
    final newSettings = state.copyWith(successColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de error
  Future<void> updateErrorColor(Color color) async {
    final newSettings = state.copyWith(errorColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color de advertencia
  Future<void> updateWarningColor(Color color) async {
    final newSettings = state.copyWith(warningColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del sidebar
  Future<void> updateSidebarColor(Color color) async {
    final newSettings = state.copyWith(sidebarColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del texto del sidebar
  Future<void> updateSidebarTextColor(Color color) async {
    final newSettings = state.copyWith(sidebarTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color activo del sidebar
  Future<void> updateSidebarActiveColor(Color color) async {
    final newSettings = state.copyWith(sidebarActiveColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del footer
  Future<void> updateFooterColor(Color color) async {
    final newSettings = state.copyWith(footerColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar color del texto del footer
  Future<void> updateFooterTextColor(Color color) async {
    final newSettings = state.copyWith(footerTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateBackgroundGradientStart(Color color) async {
    final newSettings = state.copyWith(backgroundGradientStart: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateBackgroundGradientMid(Color color) async {
    final newSettings = state.copyWith(backgroundGradientMid: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateBackgroundGradientEnd(Color color) async {
    final newSettings = state.copyWith(backgroundGradientEnd: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesDetailGradientStart(Color color) async {
    final newSettings = state.copyWith(salesDetailGradientStart: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesDetailGradientMid(Color color) async {
    final newSettings = state.copyWith(salesDetailGradientMid: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesDetailGradientEnd(Color color) async {
    final newSettings = state.copyWith(salesDetailGradientEnd: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesDetailTextColor(Color color) async {
    final newSettings = state.copyWith(salesDetailTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  // ======== Accesos rapidos (aplicar a AppBar/Sidebar/Footer) ========

  Future<void> updateChromeBackgroundColor(Color color) async {
    final newSettings = state.copyWith(
      // "Chrome" = AppBar principal (Topbar) + Sidebar + Footer.
      appBarColor: state.applyChromeToEntireLayout ? color : state.appBarColor,
      topbarColor: color,
      sidebarColor: color,
      footerColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateChromeTextColor(Color color) async {
    final newSettings = state.copyWith(
      appBarTextColor: state.applyChromeToEntireLayout
          ? color
          : state.appBarTextColor,
      topbarTextColor: color,
      sidebarTextColor: color,
      footerTextColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateChromeHoverColor(Color color) async {
    final newSettings = state.copyWith(
      sidebarActiveColor: color,
      hoverColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateApplyChromeToEntireLayout(bool enabled) async {
    final newSettings = enabled
        ? state.copyWith(
            applyChromeToEntireLayout: true,
            appBarColor: state.topbarColor,
            appBarTextColor: state.topbarTextColor,
          )
        : state.copyWith(applyChromeToEntireLayout: false);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  // ======== Pagina de ventas (grid/tarjetas de productos) ========

  Future<void> updateSalesGridBackgroundColor(Color color) async {
    final newSettings = state.copyWith(salesGridBackgroundColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesProductCardBackgroundColor(Color color) async {
    final newSettings = state.copyWith(salesProductCardBackgroundColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesProductCardBorderColor(Color color) async {
    final newSettings = state.copyWith(salesProductCardBorderColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesProductCardTextColor(Color color) async {
    final newSettings = state.copyWith(salesProductCardTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesProductCardAltBackgroundColor(Color color) async {
    final newSettings = state.copyWith(
      salesProductCardAltBackgroundColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesProductCardAltBorderColor(Color color) async {
    final newSettings = state.copyWith(salesProductCardAltBorderColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesProductCardAltTextColor(Color color) async {
    final newSettings = state.copyWith(salesProductCardAltTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesProductPriceColor(Color color) async {
    final newSettings = state.copyWith(salesProductPriceColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  // ======== Pagina de ventas (barra superior/botones inferiores) ========

  Future<void> updateSalesControlBarBackgroundColor(Color color) async {
    final newSettings = state.copyWith(salesControlBarBackgroundColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarContentBackgroundColor(Color color) async {
    final newSettings = state.copyWith(
      salesControlBarContentBackgroundColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarBorderColor(Color color) async {
    final newSettings = state.copyWith(salesControlBarBorderColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarTextColor(Color color) async {
    final newSettings = state.copyWith(salesControlBarTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarDropdownBackgroundColor(Color color) async {
    final newSettings = state.copyWith(
      salesControlBarDropdownBackgroundColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarDropdownBorderColor(Color color) async {
    final newSettings = state.copyWith(
      salesControlBarDropdownBorderColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarDropdownTextColor(Color color) async {
    final newSettings = state.copyWith(salesControlBarDropdownTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarPopupBackgroundColor(Color color) async {
    final newSettings = state.copyWith(
      salesControlBarPopupBackgroundColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarPopupTextColor(Color color) async {
    final newSettings = state.copyWith(salesControlBarPopupTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarPopupSelectedBackgroundColor(
    Color color,
  ) async {
    final newSettings = state.copyWith(
      salesControlBarPopupSelectedBackgroundColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesControlBarPopupSelectedTextColor(Color color) async {
    final newSettings = state.copyWith(
      salesControlBarPopupSelectedTextColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesFooterButtonsBackgroundColor(Color color) async {
    final newSettings = state.copyWith(
      salesFooterButtonsBackgroundColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesFooterButtonsTextColor(Color color) async {
    final newSettings = state.copyWith(salesFooterButtonsTextColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateSalesFooterButtonsBorderColor(Color color) async {
    final newSettings = state.copyWith(salesFooterButtonsBorderColor: color);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar tamaÃ±o de fuente
  Future<void> updateFontSize(double size) async {
    final newSettings = state.copyWith(fontSize: size);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Actualizar familia de fuente
  Future<void> updateFontFamily(String family) async {
    final newSettings = state.copyWith(fontFamily: family);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Cambiar modo oscuro
  Future<void> toggleDarkMode() async {
    final targetIsDark = !state.isDarkMode;
    final base = state.copyWith(isDarkMode: targetIsDark);
    // Auto-ajuste: si el usuario aÃºn tiene colores "de claro" al pasar a oscuro
    // (o viceversa), ajustamos fondo/surface/texto/appbar/sidebar/footer para que
    // el modo se vea diferente. Si ya estÃ¡n configurados para ese modo, se respetan.
    final newSettings = _autoAdjustForMode(base, isDark: targetIsDark);
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  /// Resetear a valores por defecto
  Future<void> resetToDefault() async {
    await _repository.resetToDefault();
    state = ThemeSettings.defaultSettings;
  }

  /// Guardar configuraciÃ³n actual
  Future<void> saveSettings(ThemeSettings settings) async {
    state = settings;
    await _repository.saveThemeSettings(settings);
  }

  /// Vista previa temporal del tema sin persistirlo.
  void previewSettings(ThemeSettings settings) {
    state = settings;
  }

  ThemeSettings _autoAdjustForMode(
    ThemeSettings settings, {
    required bool isDark,
  }) {
    bool isTooLight(Color c) => c.computeLuminance() > 0.45;
    bool isTooDark(Color c) => c.computeLuminance() < 0.25;
    Color contrast(Color c) =>
        c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    const darkBg = PremiumThemeColors.darkBackground;
    const darkSurface = PremiumThemeColors.darkSurface;
    const darkCard = PremiumThemeColors.darkSurfaceAlt;
    const darkText = PremiumThemeColors.darkText;
    const darkMuted = PremiumThemeColors.darkTextSecondary;
    const lightBg = PremiumThemeColors.background;
    const lightSurface = PremiumThemeColors.surface;
    const lightText = PremiumThemeColors.textPrimary;

    if (isDark) {
      final nextAppBarColor = isTooLight(settings.appBarColor)
          ? darkSurface
          : settings.appBarColor;
      final nextSidebarColor = isTooLight(settings.sidebarColor)
          ? darkBg
          : settings.sidebarColor;
      return settings.copyWith(
        backgroundColor: isTooLight(settings.backgroundColor)
            ? darkBg
            : settings.backgroundColor,
        surfaceColor: isTooLight(settings.surfaceColor)
            ? darkSurface
            : settings.surfaceColor,
        cardColor: isTooLight(settings.cardColor)
            ? darkCard
            : settings.cardColor,
        textColor: isTooDark(settings.textColor)
            ? darkText
            : settings.textColor,
        appBarColor: nextAppBarColor,
        appBarTextColor: isTooDark(settings.appBarTextColor)
            ? contrast(nextAppBarColor)
            : settings.appBarTextColor,
        sidebarColor: nextSidebarColor,
        sidebarTextColor: isTooDark(settings.sidebarTextColor)
            ? contrast(nextSidebarColor)
            : settings.sidebarTextColor,
        footerColor: isTooLight(settings.footerColor)
            ? darkSurface
            : settings.footerColor,
        footerTextColor: isTooDark(settings.footerTextColor)
            ? darkMuted
            : settings.footerTextColor,
      );
    }

    final nextAppBarColor = isTooDark(settings.appBarColor)
        ? PremiumThemeColors.chromeBackground
        : settings.appBarColor;
    final nextTopbarColor = isTooDark(settings.topbarColor)
        ? PremiumThemeColors.chromeBackground
        : settings.topbarColor;
    final nextFooterColor = isTooDark(settings.footerColor)
        ? PremiumThemeColors.chromeBackground
        : settings.footerColor;
    final nextSidebarColor = isTooLight(settings.sidebarColor)
        ? PremiumThemeColors.sidebarBackground
        : settings.sidebarColor;
    return settings.copyWith(
      backgroundColor: isTooDark(settings.backgroundColor)
          ? lightBg
          : settings.backgroundColor,
      surfaceColor: isTooDark(settings.surfaceColor)
          ? lightSurface
          : settings.surfaceColor,
      textColor: isTooLight(settings.textColor)
          ? lightText
          : settings.textColor,
      appBarColor: nextAppBarColor,
      appBarTextColor: (nextAppBarColor != settings.appBarColor)
          ? contrast(nextAppBarColor)
          : settings.appBarTextColor,
      topbarColor: nextTopbarColor,
      topbarTextColor: (nextTopbarColor != settings.topbarColor)
          ? contrast(nextTopbarColor)
          : settings.topbarTextColor,
      cardColor: isTooDark(settings.cardColor)
          ? lightSurface
          : settings.cardColor,
      sidebarColor: nextSidebarColor,
      sidebarTextColor: (nextSidebarColor != settings.sidebarColor)
          ? contrast(nextSidebarColor)
          : settings.sidebarTextColor,
      footerColor: nextFooterColor,
      footerTextColor: (nextFooterColor != settings.footerColor)
          ? contrast(nextFooterColor)
          : settings.footerTextColor,
    );
  }
}

/// Provider del repositorio
final themeRepositoryProvider = Provider<ThemeSettingsRepository>((ref) {
  return ThemeSettingsRepository();
});

/// Provider del tema
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeSettings>((
  ref,
) {
  final repository = ref.watch(themeRepositoryProvider);
  return ThemeNotifier(repository);
});

/// Provider que genera el ThemeData a partir de ThemeSettings
final themeDataProvider = Provider<ThemeData>((ref) {
  final settings = ref.watch(themeProvider);
  return _buildThemeData(settings);
});

final appThemeConfigProvider = Provider<AppThemeConfig>((ref) {
  final settings = ref.watch(themeProvider);
  return settings.toAppThemeConfig();
});

/// Construye el ThemeData a partir de ThemeSettings
ThemeData _buildThemeData(ThemeSettings settings) {
  final config = settings.toAppThemeConfig();
  final brightness = settings.isDarkMode ? Brightness.dark : Brightness.light;
  final onPrimary = _getContrastColor(settings.primaryColor);
  final onAccent = _getContrastColor(settings.accentColor);
  final onError = _getContrastColor(settings.errorColor);
  final onButton = _getContrastColor(settings.buttonColor);
  final scaffoldBg = settings.backgroundColor;
  final surfaceColor = settings.surfaceColor.opacity == 0
      ? PremiumThemeColors.surface
      : settings.surfaceColor;
  final effectiveTextColor = _ensureReadableColor(
    settings.textColor,
    surfaceColor,
  );
  final secondaryTextColor = _ensureReadableColor(
    PremiumThemeColors.textSecondary,
    surfaceColor,
    minRatio: 3.2,
  );
  final appBarTextColor = _ensureReadableColor(
    settings.appBarTextColor,
    settings.appBarColor,
  );
  final outlineColor = brightness == Brightness.dark
      ? Colors.white.withOpacity(0.12)
      : PremiumThemeColors.appBarBorder;
  final chromeDividerColor = settings.appBarColor.computeLuminance() < 0.16
      ? Colors.white.withOpacity(0.08)
      : outlineColor;
  final salesDetailTextColor = _ensureReadableColor(
    settings.salesDetailTextColor,
    settings.salesDetailGradientMid,
  );
  final outlineVariant = brightness == Brightness.dark
      ? Colors.white.withOpacity(0.08)
      : PremiumThemeColors.appBarBorder;
  final surfaceAlt = brightness == Brightness.dark
      ? Color.alphaBlend(Colors.white.withOpacity(0.04), surfaceColor)
      : PremiumThemeColors.surfaceAlt;
  final subtleShadow = Colors.black.withOpacity(
    brightness == Brightness.dark ? 0.16 : 0.06,
  );
  const inactiveTone = PremiumThemeColors.inactive;
  final hoverTint = brightness == Brightness.dark
      ? Colors.white.withOpacity(0.04)
      : settings.primaryColor.withOpacity(0.045);
  final focusTint = settings.primaryColor.withOpacity(
    brightness == Brightness.dark ? 0.22 : 0.12,
  );
  final scheme =
      ColorScheme.fromSeed(
        seedColor: settings.primaryColor,
        brightness: brightness,
      ).copyWith(
        primary: settings.primaryColor,
        onPrimary: onPrimary,
        secondary: settings.accentColor,
        onSecondary: onAccent,
        surface: surfaceColor,
        onSurface: effectiveTextColor,
        onSurfaceVariant: secondaryTextColor,
        error: settings.errorColor,
        onError: onError,
        outline: outlineColor,
        outlineVariant: outlineVariant,
        surfaceContainerHighest: surfaceAlt,
      );
  final snackBarBackground = Color.alphaBlend(
    scheme.primary.withOpacity(brightness == Brightness.dark ? 0.16 : 0.08),
    scheme.surface,
  );
  final snackBarForeground = ColorUtils.readableTextColor(snackBarBackground);

  final searchBg = settings.salesControlBarContentBackgroundColor.opacity == 0
      ? surfaceAlt
      : settings.salesControlBarContentBackgroundColor;
  final tokenSearchText = _ensureReadableColor(
    settings.textColor,
    searchBg,
    minRatio: 4.5,
  );
  final tokenSearchIcon = _ensureReadableColor(
    settings.textColor.withOpacity(0.9),
    searchBg,
    minRatio: 3.0,
  );

  final tokens = AppTokens(
    topbarBackground: config.appbarColor,
    topbarText: settings.topbarTextColor,
    footerBackground: config.footerColor,
    footerText: settings.footerTextColor,
    panelBackground: settings.backgroundColor,
    panelBorder: outlineVariant,
    cardBackground: config.cardColor,
    cardBorder: outlineVariant,
    sidebarBackground: config.sidebarColor,
    sidebarBorder: outlineVariant,
    sidebarText: settings.sidebarTextColor,
    sidebarActive: settings.sidebarActiveColor,
    controlBarBackground: settings.salesControlBarBackgroundColor,
    controlBarBorder: settings.salesControlBarBorderColor,
    controlBarText: settings.salesControlBarTextColor,
    buttonPrimary: config.primaryColor,
    buttonSecondary: settings.accentColor,
    buttonDanger: settings.errorColor,
    searchFieldBackground: searchBg,
    searchFieldText: tokenSearchText,
    searchFieldIcon: tokenSearchIcon,
    tileHover: settings.hoverColor,
    outline: scheme.outlineVariant,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,

    scaffoldBackgroundColor: scaffoldBg,
    canvasColor: scaffoldBg,
    hoverColor: hoverTint,
    focusColor: focusTint,
    splashColor: settings.primaryColor.withOpacity(0.08),
    disabledColor: inactiveTone,
    unselectedWidgetColor: inactiveTone,
    highlightColor: Colors.transparent,
    iconTheme: IconThemeData(color: effectiveTextColor),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: settings.appBarColor,
      surfaceTintColor: Colors.transparent,
      foregroundColor: appBarTextColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: appBarTextColor),
      actionsIconTheme: IconThemeData(color: secondaryTextColor),
      titleTextStyle: TextStyle(
        color: appBarTextColor,
        fontSize: settings.fontSize + 4,
        fontWeight: FontWeight.w700,
        fontFamily: settings.fontFamily,
      ),
      toolbarTextStyle: TextStyle(
        color: appBarTextColor,
        fontSize: settings.fontSize,
        fontWeight: FontWeight.w600,
        fontFamily: settings.fontFamily,
      ),
      shape: Border(bottom: BorderSide(color: chromeDividerColor, width: 1)),
    ),

    // Cards
    cardTheme: CardThemeData(
      color: settings.cardColor,
      elevation: 1,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shadowColor: subtleShadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL + 2),
        side: BorderSide(color: outlineVariant, width: 1),
      ),
    ),

    // Input decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.dark ? surfaceAlt : scheme.surface,
      prefixIconColor: inactiveTone,
      suffixIconColor: inactiveTone,
      hintStyle: TextStyle(
        color: secondaryTextColor,
        fontFamily: settings.fontFamily,
      ),
      labelStyle: TextStyle(
        color: secondaryTextColor,
        fontFamily: settings.fontFamily,
      ),
      floatingLabelStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
        fontFamily: settings.fontFamily,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: outlineVariant, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: outlineVariant, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingM,
        vertical: AppSizes.paddingM,
      ),
    ),

    // Filled Button (Material 3)
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: settings.buttonColor,
        foregroundColor: onButton,
        minimumSize: const Size(0, 46),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        textStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: settings.fontSize + 1,
          fontFamily: settings.fontFamily,
        ),
      ),
    ),

    // Elevated Button
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: settings.buttonColor,
        foregroundColor: onButton,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: settings.fontSize + 1,
          fontFamily: settings.fontFamily,
        ),
      ),
    ),

    // Outlined Button
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: effectiveTextColor,
        side: BorderSide(color: outlineColor, width: 1.2),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        textStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: settings.fontSize + 1,
          fontFamily: settings.fontFamily,
        ),
      ),
    ),

    // Text Button
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: settings.primaryColor,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: settings.fontSize,
          fontFamily: settings.fontFamily,
        ),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: secondaryTextColor,
      textColor: effectiveTextColor,
      tileColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: subtleShadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        side: BorderSide(color: outlineVariant),
      ),
      textStyle: TextStyle(
        color: effectiveTextColor,
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: surfaceAlt,
      circularTrackColor: surfaceAlt,
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: effectiveTextColor,
        disabledForegroundColor: inactiveTone,
        hoverColor: hoverTint,
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return Colors.transparent;
      }),
      side: BorderSide(color: outlineColor, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return inactiveTone;
      }),
    ),

    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withOpacity(0.35);
        }
        return inactiveTone.withOpacity(0.45);
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return inactiveTone;
      }),
    ),

    // Divider
    dividerTheme: DividerThemeData(
      color: outlineVariant,
      thickness: 1,
      space: 1,
    ),

    // Dialogs
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: subtleShadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL + 2),
        side: BorderSide(color: outlineColor, width: 1.0),
      ),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: settings.fontSize + 2,
        fontWeight: FontWeight.w700,
        fontFamily: settings.fontFamily,
      ),
      contentTextStyle: TextStyle(
        color: scheme.onSurface.withAlpha(210),
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
      ),
    ),

    // Snackbars
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: snackBarBackground,
      elevation: 2,
      insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        side: BorderSide(color: outlineVariant),
      ),
      contentTextStyle: TextStyle(
        color: snackBarForeground,
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: scheme.primary,
      closeIconColor: snackBarForeground.withAlpha(180),
      showCloseIcon: true,
    ),

    // Text theme
    textTheme: TextTheme(
      displayLarge: TextStyle(
        color: effectiveTextColor,
        fontSize: settings.fontSize + 18,
        fontWeight: FontWeight.bold,
        fontFamily: settings.fontFamily,
      ),
      displayMedium: TextStyle(
        color: effectiveTextColor,
        fontSize: settings.fontSize + 14,
        fontWeight: FontWeight.bold,
        fontFamily: settings.fontFamily,
      ),
      titleLarge: TextStyle(
        color: effectiveTextColor,
        fontSize: settings.fontSize + 8,
        fontWeight: FontWeight.w600,
        fontFamily: settings.fontFamily,
      ),
      titleMedium: TextStyle(
        color: effectiveTextColor,
        fontSize: settings.fontSize + 4,
        fontWeight: FontWeight.w600,
        fontFamily: settings.fontFamily,
      ),
      bodyLarge: TextStyle(
        color: effectiveTextColor,
        fontSize: settings.fontSize + 2,
        fontWeight: FontWeight.normal,
        fontFamily: settings.fontFamily,
      ),
      bodyMedium: TextStyle(
        color: effectiveTextColor,
        fontSize: settings.fontSize,
        fontWeight: FontWeight.normal,
        fontFamily: settings.fontFamily,
      ),
      labelLarge: TextStyle(
        color: secondaryTextColor,
        fontSize: settings.fontSize,
        fontWeight: FontWeight.w500,
        fontFamily: settings.fontFamily,
      ),
    ),
    extensions: [
      tokens,
      AppGradientTheme(
        start: settings.backgroundGradientStart,
        mid: settings.backgroundGradientMid,
        end: settings.backgroundGradientEnd,
      ),
      SalesDetailGradientTheme(
        start: settings.salesDetailGradientStart,
        mid: settings.salesDetailGradientMid,
        end: settings.salesDetailGradientEnd,
      ),
      SalesDetailTextTheme(textColor: salesDetailTextColor),
      SalesProductsTheme(
        gridBackgroundColor: settings.salesGridBackgroundColor,
        cardBackgroundColor: settings.salesProductCardBackgroundColor,
        cardBorderColor: settings.salesProductCardBorderColor,
        cardTextColor: settings.salesProductCardTextColor,
        cardAltBackgroundColor: settings.salesProductCardAltBackgroundColor,
        cardAltBorderColor: settings.salesProductCardAltBorderColor,
        cardAltTextColor: settings.salesProductCardAltTextColor,
        priceColor: settings.salesProductPriceColor,
      ),
      SalesPageTheme(
        controlBarBackgroundColor: settings.salesControlBarBackgroundColor,
        controlBarContentBackgroundColor:
            settings.salesControlBarContentBackgroundColor,
        controlBarBorderColor: settings.salesControlBarBorderColor,
        controlBarTextColor: settings.salesControlBarTextColor,
        controlBarDropdownBackgroundColor:
            settings.salesControlBarDropdownBackgroundColor,
        controlBarDropdownBorderColor:
            settings.salesControlBarDropdownBorderColor,
        controlBarDropdownTextColor: settings.salesControlBarDropdownTextColor,
        controlBarPopupBackgroundColor:
            settings.salesControlBarPopupBackgroundColor,
        controlBarPopupTextColor: settings.salesControlBarPopupTextColor,
        controlBarPopupSelectedBackgroundColor:
            settings.salesControlBarPopupSelectedBackgroundColor,
        controlBarPopupSelectedTextColor:
            settings.salesControlBarPopupSelectedTextColor,
        footerButtonsBackgroundColor:
            settings.salesFooterButtonsBackgroundColor,
        footerButtonsTextColor: settings.salesFooterButtonsTextColor,
        footerButtonsBorderColor: settings.salesFooterButtonsBorderColor,
      ),
      AppStatusTheme(
        success: settings.successColor,
        warning: settings.warningColor,
        error: settings.errorColor,
        info: settings.accentColor,
      ),
    ],
  );
}

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance() + 0.05;
  final l2 = b.computeLuminance() + 0.05;
  return l1 > l2 ? l1 / l2 : l2 / l1;
}

Color _ensureReadableColor(Color fg, Color bg, {double minRatio = 4.5}) {
  if (_contrastRatio(fg, bg) >= minRatio) return fg;
  return _getContrastColor(bg);
}

Color _getContrastColor(Color color) {
  final luminance = color.computeLuminance();
  return luminance > 0.5 ? Colors.black : Colors.white;
}
