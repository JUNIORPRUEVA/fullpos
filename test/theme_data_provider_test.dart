import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/theme/app_gradient_theme.dart';
import 'package:fullpos/core/theme/app_tokens.dart';
import 'package:fullpos/core/theme/sales_page_theme.dart';
import 'package:fullpos/core/theme/sales_products_theme.dart';
import 'package:fullpos/features/settings/data/theme_settings_model.dart';
import 'package:fullpos/features/settings/data/theme_settings_repository.dart';
import 'package:fullpos/features/settings/providers/theme_provider.dart';

class _MemoryThemeSettingsRepository extends ThemeSettingsRepository {
  _MemoryThemeSettingsRepository(this._current);

  ThemeSettings _current;

  @override
  Future<ThemeSettings> loadThemeSettings({int? companyId}) async => _current;

  @override
  Future<bool> saveThemeSettings(ThemeSettings settings, {int? companyId}) async {
    _current = settings;
    return true;
  }

  @override
  Future<bool> resetToDefault({int? companyId}) async {
    _current = ThemeSettings.defaultSettings;
    return true;
  }
}

void main() {
  test('Visible appearance options are reflected in ThemeData', () async {
    final customSettings = ThemeSettings.defaultSettings.copyWith(
      backgroundColor: const Color(0xFFF4EFE5),
      surfaceColor: const Color(0xFFFFFBF4),
      textColor: const Color(0xFF23180E),
      hoverColor: const Color(0xFFC98F2B),
      topbarColor: const Color(0xFF103A2F),
      topbarTextColor: Colors.white,
      sidebarColor: const Color(0xFF12382E),
      sidebarTextColor: const Color(0xFFF4EEE3),
      sidebarActiveColor: const Color(0xFFE7A93B),
      footerColor: const Color(0xFF163127),
      footerTextColor: const Color(0xFFEFE7DA),
      backgroundGradientStart: const Color(0xFFFFFBF3),
      backgroundGradientMid: const Color(0xFFF6E8CC),
      backgroundGradientEnd: const Color(0xFFE8D2A1),
      salesGridBackgroundColor: const Color(0xFFF2E5CF),
      salesProductCardBackgroundColor: const Color(0xFFFFFAF1),
      salesProductCardBorderColor: const Color(0xFFD7B47A),
      salesProductCardTextColor: const Color(0xFF2F2417),
      salesProductCardAltBackgroundColor: const Color(0xFFEEE0C8),
      salesProductCardAltBorderColor: const Color(0xFFC7984C),
      salesProductCardAltTextColor: const Color(0xFF24180D),
      salesProductPriceColor: const Color(0xFFB76A16),
      salesDetailGradientStart: const Color(0xFF1E2A37),
      salesDetailGradientMid: const Color(0xFF2A3D4F),
      salesDetailGradientEnd: const Color(0xFF18232E),
      salesDetailTextColor: Colors.white,
      fontSize: 16,
      fontFamily: 'Montserrat',
      salesControlBarBackgroundColor: const Color(0xFFFFF7EA),
      salesControlBarContentBackgroundColor: const Color(0xFFF8EEDB),
      salesControlBarBorderColor: const Color(0xFFD5B27A),
      salesControlBarTextColor: const Color(0xFF2C2115),
      salesControlBarDropdownBackgroundColor: const Color(0xFFFFFBF5),
      salesControlBarDropdownBorderColor: const Color(0xFFDAB885),
      salesControlBarDropdownTextColor: const Color(0xFF2C2217),
      salesControlBarPopupBackgroundColor: const Color(0xFFFFFBF4),
      salesControlBarPopupTextColor: const Color(0xFF2E241A),
      salesControlBarPopupSelectedBackgroundColor: const Color(0xFFEBCB93),
      salesControlBarPopupSelectedTextColor: const Color(0xFF24180D),
      salesFooterButtonsBackgroundColor: const Color(0xFFFFF5E3),
      salesFooterButtonsTextColor: const Color(0xFF2A2016),
      salesFooterButtonsBorderColor: const Color(0xFFD0A568),
    );
    final repository = _MemoryThemeSettingsRepository(customSettings);
    final container = ProviderContainer(
      overrides: [
        themeRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(themeProvider.notifier).saveSettings(customSettings);

    final theme = container.read(themeDataProvider);
    final tokens = theme.extension<AppTokens>();
    final appGradient = theme.extension<AppGradientTheme>();
    final salesGradient = theme.extension<SalesDetailGradientTheme>();
    final salesProducts = theme.extension<SalesProductsTheme>();
    final salesPage = theme.extension<SalesPageTheme>();
    final salesText = theme.extension<SalesDetailTextTheme>();

    expect(theme.scaffoldBackgroundColor.value, customSettings.backgroundColor.value);
    expect(theme.colorScheme.surface.value, customSettings.surfaceColor.value);
    expect(theme.textTheme.bodyMedium?.fontFamily, customSettings.fontFamily);
    expect(theme.textTheme.bodyMedium?.fontSize, customSettings.fontSize);

    expect(tokens, isNotNull);
    expect(tokens!.topbarBackground.value, customSettings.topbarColor.value);
    expect(tokens.topbarText.value, customSettings.topbarTextColor.value);
    expect(tokens.sidebarBackground.value, customSettings.sidebarColor.value);
    expect(tokens.sidebarText.value, customSettings.sidebarTextColor.value);
    expect(tokens.sidebarActive.value, customSettings.sidebarActiveColor.value);
    expect(tokens.footerBackground.value, customSettings.footerColor.value);
    expect(tokens.footerText.value, customSettings.footerTextColor.value);
    expect(tokens.tileHover.value, customSettings.hoverColor.value);

    expect(appGradient, isNotNull);
    expect(appGradient!.start.value, customSettings.backgroundGradientStart.value);
    expect(appGradient.mid.value, customSettings.backgroundGradientMid.value);
    expect(appGradient.end.value, customSettings.backgroundGradientEnd.value);

    expect(salesProducts, isNotNull);
    expect(salesProducts!.gridBackgroundColor.value, customSettings.salesGridBackgroundColor.value);
    expect(salesProducts.cardBackgroundColor.value, customSettings.salesProductCardBackgroundColor.value);
    expect(salesProducts.cardBorderColor.value, customSettings.salesProductCardBorderColor.value);
    expect(salesProducts.cardTextColor.value, customSettings.salesProductCardTextColor.value);
    expect(salesProducts.cardAltBackgroundColor.value, customSettings.salesProductCardAltBackgroundColor.value);
    expect(salesProducts.cardAltBorderColor.value, customSettings.salesProductCardAltBorderColor.value);
    expect(salesProducts.cardAltTextColor.value, customSettings.salesProductCardAltTextColor.value);
    expect(salesProducts.priceColor.value, customSettings.salesProductPriceColor.value);

    expect(salesGradient, isNotNull);
    expect(salesGradient!.start.value, customSettings.salesDetailGradientStart.value);
    expect(salesGradient.mid.value, customSettings.salesDetailGradientMid.value);
    expect(salesGradient.end.value, customSettings.salesDetailGradientEnd.value);

    expect(salesText, isNotNull);
    expect(salesText!.textColor.value, customSettings.salesDetailTextColor.value);

    expect(salesPage, isNotNull);
    expect(salesPage!.controlBarBackgroundColor.value, customSettings.salesControlBarBackgroundColor.value);
    expect(salesPage.controlBarContentBackgroundColor.value, customSettings.salesControlBarContentBackgroundColor.value);
    expect(salesPage.controlBarBorderColor.value, customSettings.salesControlBarBorderColor.value);
    expect(salesPage.controlBarTextColor.value, customSettings.salesControlBarTextColor.value);
    expect(salesPage.controlBarDropdownBackgroundColor.value, customSettings.salesControlBarDropdownBackgroundColor.value);
    expect(salesPage.controlBarDropdownBorderColor.value, customSettings.salesControlBarDropdownBorderColor.value);
    expect(salesPage.controlBarDropdownTextColor.value, customSettings.salesControlBarDropdownTextColor.value);
    expect(salesPage.controlBarPopupBackgroundColor.value, customSettings.salesControlBarPopupBackgroundColor.value);
    expect(salesPage.controlBarPopupTextColor.value, customSettings.salesControlBarPopupTextColor.value);
    expect(salesPage.controlBarPopupSelectedBackgroundColor.value, customSettings.salesControlBarPopupSelectedBackgroundColor.value);
    expect(salesPage.controlBarPopupSelectedTextColor.value, customSettings.salesControlBarPopupSelectedTextColor.value);
    expect(salesPage.footerButtonsBackgroundColor.value, customSettings.salesFooterButtonsBackgroundColor.value);
    expect(salesPage.footerButtonsTextColor.value, customSettings.salesFooterButtonsTextColor.value);
    expect(salesPage.footerButtonsBorderColor.value, customSettings.salesFooterButtonsBorderColor.value);
  });
}