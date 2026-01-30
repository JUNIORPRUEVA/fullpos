import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/theme_settings_model.dart';
import '../data/theme_settings_repository.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_gradient_theme.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/sales_products_theme.dart';
import '../../../core/theme/sales_page_theme.dart';

/// Notifier para manejar el estado del tema
class ThemeNotifier extends StateNotifier<ThemeSettings> {
  final ThemeSettingsRepository _repository;

  ThemeNotifier(this._repository) : super(ThemeSettings.defaultSettings) {
    _loadSettings();
  }

  /// Cargar configuraciÃ³n guardada
  Future<void> _loadSettings() async {
    final settings = await _repository.loadThemeSettings();
    state = settings;
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
      appBarColor: color,
      sidebarColor: color,
      footerColor: color,
    );
    state = newSettings;
    await _repository.saveThemeSettings(newSettings);
  }

  Future<void> updateChromeTextColor(Color color) async {
    final newSettings = state.copyWith(
      appBarTextColor: color,
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

  /// Aplicar tema preset
  Future<void> applyPreset(String presetName) async {
    final preset = PresetThemes.getPreset(presetName);
    state = preset;
    await _repository.saveThemeSettings(preset);
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

  ThemeSettings _autoAdjustForMode(
    ThemeSettings settings, {
    required bool isDark,
  }) {
    bool isTooLight(Color c) => c.computeLuminance() > 0.45;
    bool isTooDark(Color c) => c.computeLuminance() < 0.25;
    Color contrast(Color c) =>
        c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    // Paleta base para modo oscuro (corporativa neutra)
    const darkBg = Color(0xFF0B1220);
    const darkSurface = Color(0xFF111827);
    const darkText = Color(0xFFE5E7EB);
    const darkMuted = Color(0xFF94A3B8);

    // Paleta base para modo claro (surface gris claro solicitado)
    const lightBg = Color(0xFFF3F6F5);
    const lightSurface = Color(0xFFF8F9F9);
    const lightText = Color(0xFF1F2937);

    if (isDark) {
      final nextAppBarColor = isTooLight(settings.appBarColor)
          ? darkBg
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
            ? darkSurface
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
            ? darkBg
            : settings.footerColor,
        footerTextColor: isTooDark(settings.footerTextColor)
            ? darkMuted
            : settings.footerTextColor,
      );
    }

    final nextAppBarColor = isTooDark(settings.appBarColor)
        ? settings.primaryColor
        : settings.appBarColor;
    // En modo claro: solo corregimos fondo/surface/texto/appbar si venimos de un esquema muy oscuro.
    // Sidebar/Footer pueden ser oscuros en modo claro, asÃ­ que no los forzamos.
    return settings.copyWith(
      backgroundColor: isTooDark(settings.backgroundColor)
          ? lightBg
          : settings.backgroundColor,
      surfaceColor: isTooDark(settings.surfaceColor)
          ? lightSurface
          : settings.surfaceColor,
      cardColor: isTooDark(settings.cardColor)
          ? Colors.white
          : settings.cardColor,
      textColor: isTooLight(settings.textColor)
          ? lightText
          : settings.textColor,
      appBarColor: nextAppBarColor,
      appBarTextColor: (nextAppBarColor != settings.appBarColor)
          ? contrast(nextAppBarColor)
          : settings.appBarTextColor,
      // Mantener sidebar/footer tal cual (configuraciÃ³n del usuario o preset)
      footerTextColor: settings.footerTextColor,
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

/// Construye el ThemeData a partir de ThemeSettings
ThemeData _buildThemeData(ThemeSettings settings) {
  final brightness = settings.isDarkMode ? Brightness.dark : Brightness.light;
  final onPrimary = _getContrastColor(settings.primaryColor);
  final onAccent = _getContrastColor(settings.accentColor);
  final onError = _getContrastColor(settings.errorColor);
  final onButton = _getContrastColor(settings.buttonColor);
  const scaffoldBg = Colors.transparent;
  final surfaceColor = settings.surfaceColor.opacity == 0
      ? Colors.white
      : settings.surfaceColor;
  final effectiveTextColor = _ensureReadableColor(
    settings.textColor,
    surfaceColor,
  );
  final appBarTextColor = _ensureReadableColor(
    settings.appBarTextColor,
    settings.appBarColor,
  );
  final salesDetailTextColor = _ensureReadableColor(
    settings.salesDetailTextColor,
    settings.salesDetailGradientMid,
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
        error: settings.errorColor,
        onError: onError,
        surfaceContainerHighest: surfaceColor.withAlpha(230),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,

    scaffoldBackgroundColor: scaffoldBg,
    hoverColor: settings.hoverColor.withOpacity(0.12),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: appBarTextColor,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: appBarTextColor),
    ),

    // Cards
    cardTheme: CardThemeData(
      color: settings.cardColor,
      elevation: 1,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        side: BorderSide(color: scheme.onSurface.withAlpha(25), width: 1),
      ),
    ),

    // Input decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: scheme.onSurface.withAlpha(30), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: scheme.onSurface.withAlpha(30), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        borderSide: BorderSide(color: scheme.error, width: 2),
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
        minimumSize: const Size(0, 48),
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
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        elevation: 2,
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
        foregroundColor: settings.buttonColor,
        side: BorderSide(color: settings.buttonColor, width: 1.5),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
      ),
    ),

    // Text Button
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: settings.buttonColor,
        minimumSize: const Size(0, 48),
      ),
    ),

    // Divider
    dividerTheme: DividerThemeData(
      color: scheme.onSurface.withAlpha(30),
      thickness: 1,
      space: 1,
    ),

    // Dialogs
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: settings.fontSize + 2,
        fontWeight: FontWeight.w600,
        fontFamily: settings.fontFamily,
      ),
      contentTextStyle: TextStyle(
        color: scheme.onSurface.withAlpha(200),
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
      ),
    ),

    // Snackbars
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surface,
      contentTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
      ),
      actionTextColor: scheme.primary,
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
        color: effectiveTextColor.withAlpha(180),
        fontSize: settings.fontSize,
        fontWeight: FontWeight.w500,
        fontFamily: settings.fontFamily,
      ),
    ),
    extensions: [
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
