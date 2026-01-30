import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_settings_model.dart';
import '../data/business_settings_repository.dart';
import '../../../core/services/app_configuration_service.dart';

/// Notifier para manejar el estado de la configuración del negocio
class BusinessSettingsNotifier extends StateNotifier<BusinessSettings> {
  final BusinessSettingsRepository _repository;

  BusinessSettingsNotifier(this._repository, {BusinessSettings? initial})
    : super(initial ?? BusinessSettings.defaultSettings) {
    // Mantener servicio global inicializado desde el primer frame.
    appConfigService.initialize(state);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  /// Cargar configuración guardada
  Future<void> _loadSettings() async {
    final settings = await _repository.loadSettings();
    state = settings;
    // Mantener servicio global inicializado/actualizado.
    appConfigService.initialize(settings);
  }

  /// Recargar configuración
  Future<void> reload() async {
    await _loadSettings();
  }

  /// Actualizar nombre del negocio
  Future<void> updateBusinessName(String name) async {
    final newSettings = state.copyWith(businessName: name);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar logo
  Future<void> updateLogo(String? path) async {
    final newSettings = path != null
        ? state.copyWith(logoPath: path)
        : state.copyWith(clearLogoPath: true);
    state = newSettings;
    await _repository.saveSettings(newSettings);
    appConfigService.updateSettings(newSettings);
  }

  /// Actualizar teléfono
  Future<void> updatePhone(String? phone) async {
    final newSettings = state.copyWith(phone: phone);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar teléfono secundario
  Future<void> updatePhone2(String? phone) async {
    final newSettings = state.copyWith(phone2: phone);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar email
  Future<void> updateEmail(String? email) async {
    final newSettings = state.copyWith(email: email);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar dirección
  Future<void> updateAddress(String? address) async {
    final newSettings = state.copyWith(address: address);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar ciudad
  Future<void> updateCity(String? city) async {
    final newSettings = state.copyWith(city: city);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar RNC
  Future<void> updateRnc(String? rnc) async {
    final newSettings = state.copyWith(rnc: rnc);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar slogan
  Future<void> updateSlogan(String? slogan) async {
    final newSettings = state.copyWith(slogan: slogan);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar sitio web
  Future<void> updateWebsite(String? website) async {
    final newSettings = state.copyWith(website: website);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar teléfono de la empresa
  Future<void> updateCompanyPhone(String phone) async {
    final newSettings = state.copyWith(phone: phone);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar tasa de impuesto
  Future<void> updateDefaultTaxRate(double rate) async {
    final newSettings = state.copyWith(defaultTaxRate: rate);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar si impuesto incluido en precios
  Future<void> updateTaxIncludedInPrices(bool included) async {
    final newSettings = state.copyWith(taxIncludedInPrices: included);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar moneda
  Future<void> updateCurrency(String currency, String symbol) async {
    final newSettings = state.copyWith(
      defaultCurrency: currency,
      currencySymbol: symbol,
    );
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar encabezado del recibo
  Future<void> updateReceiptHeader(String header) async {
    final newSettings = state.copyWith(receiptHeader: header);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar pie del recibo
  Future<void> updateReceiptFooter(String footer) async {
    final newSettings = state.copyWith(receiptFooter: footer);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar mostrar logo en recibos
  Future<void> updateShowLogoOnReceipt(bool show) async {
    final newSettings = state.copyWith(showLogoOnReceipt: show);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar impresión automática
  Future<void> updatePrintReceiptAutomatically(bool auto) async {
    final newSettings = state.copyWith(printReceiptAutomatically: auto);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar backup automático
  Future<void> updateEnableAutoBackup(bool enable) async {
    final newSettings = state.copyWith(enableAutoBackup: enable);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar notificaciones
  Future<void> updateEnableNotifications(bool enable) async {
    final newSettings = state.copyWith(enableNotifications: enable);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar rastreo de inventario
  Future<void> updateEnableInventoryTracking(bool enable) async {
    final newSettings = state.copyWith(enableInventoryTracking: enable);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar aprobación de clientes
  Future<void> updateEnableClientApproval(bool enable) async {
    final newSettings = state.copyWith(enableClientApproval: enable);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar encriptación de datos
  Future<void> updateEnableDataEncryption(bool enable) async {
    final newSettings = state.copyWith(enableDataEncryption: enable);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar detalles en dashboard
  Future<void> updateShowDetailsOnDashboard(bool show) async {
    final newSettings = state.copyWith(showDetailsOnDashboard: show);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar modo oscuro
  Future<void> updateDarkModeEnabled(bool enabled) async {
    final newSettings = state.copyWith(darkModeEnabled: enabled);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Actualizar timeout de sesión
  Future<void> updateSessionTimeoutMinutes(int minutes) async {
    final newSettings = state.copyWith(sessionTimeoutMinutes: minutes);
    state = newSettings;
    await _repository.saveSettings(newSettings);
  }

  /// Guardar todas las configuraciones
  Future<void> saveSettings(BusinessSettings settings) async {
    state = settings;
    await _repository.saveSettings(settings);
    appConfigService.updateSettings(settings);
  }

  /// Resetear a valores por defecto
  Future<void> resetToDefault() async {
    await _repository.resetToDefault();
    state = BusinessSettings.defaultSettings;
    appConfigService.updateSettings(BusinessSettings.defaultSettings);
  }
}

/// Provider del repositorio
final businessRepositoryProvider = Provider<BusinessSettingsRepository>((ref) {
  return BusinessSettingsRepository();
});

/// Provider de la configuración del negocio
final businessSettingsProvider =
    StateNotifierProvider<BusinessSettingsNotifier, BusinessSettings>((ref) {
      final repository = ref.watch(businessRepositoryProvider);
      return BusinessSettingsNotifier(repository);
    });
