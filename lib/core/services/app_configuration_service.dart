import 'dart:io';
import 'package:flutter/material.dart';
import '../../features/settings/data/business_settings_model.dart';

/// Servicio global de configuración de la aplicación
/// Este servicio centraliza todas las configuraciones del negocio
/// y las aplica globalmente en la app
class AppConfigurationService {
  static final AppConfigurationService _instance =
      AppConfigurationService._internal();

  late BusinessSettings _currentSettings;

  // Callbacks para cambios de configuración
  final List<VoidCallback> _listeners = [];

  AppConfigurationService._internal();

  factory AppConfigurationService() {
    return _instance;
  }

  /// Inicializar con las configuraciones
  void initialize(BusinessSettings settings) {
    _currentSettings = settings;
    _notifyListeners();
  }

  /// Obtener configuraciones actuales
  BusinessSettings get settings => _currentSettings;

  /// Actualizar configuraciones
  void updateSettings(BusinessSettings newSettings) {
    _currentSettings = newSettings;
    _notifyListeners();
  }

  /// Suscribirse a cambios de configuración
  void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  /// Desuscribirse de cambios de configuración
  void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  /// Notificar a todos los listeners
  void _notifyListeners() {
    for (final callback in _listeners) {
      callback();
    }
  }

  // ========== MÉTODOS DE ACCESO A CONFIGURACIONES ==========

  /// Obtener nombre del negocio
  String getBusinessName() => _currentSettings.businessName;

  /// Obtener logo path
  String? getLogoPath() => _currentSettings.logoPath;

  /// Verificar si hay logo disponible
  bool hasLogo() =>
      _currentSettings.logoPath != null &&
      _currentSettings.logoPath!.trim().isNotEmpty;

  /// Obtener imagen del logo como File
  File? getLogoFile() {
    final path = _currentSettings.logoPath;
    if (path != null && path.trim().isNotEmpty) return File(path);
    return null;
  }

  /// Obtener información de contacto
  String? getPhone() => _currentSettings.phone;
  String? getPhone2() => _currentSettings.phone2;
  String getCompanyPhone() => _currentSettings.phone ?? '';
  String? getEmail() => _currentSettings.email;
  String? getAddress() => _currentSettings.address;
  String? getCity() => _currentSettings.city;
  String? getRnc() => _currentSettings.rnc;

  /// Obtener información del negocio
  String? getSlogan() => _currentSettings.slogan;
  String? getWebsite() => _currentSettings.website;

  // ========== CONFIGURACIONES DE IMPUESTOS Y VENTAS ==========

  /// Obtener tasa de impuesto por defecto
  double getDefaultTaxRate() => _currentSettings.defaultTaxRate;

  /// Verificar si los precios incluyen impuesto
  bool isTaxIncludedInPrices() => _currentSettings.taxIncludedInPrices;

  /// Obtener moneda por defecto
  String getDefaultCurrency() => _currentSettings.defaultCurrency;

  /// Obtener símbolo de moneda
  String getCurrencySymbol() => _currentSettings.currencySymbol;

  /// Formatear cantidad con símbolo de moneda
  String formatCurrency(double amount) {
    return '${_currentSettings.currencySymbol} ${amount.toStringAsFixed(2)}';
  }

  // ========== CONFIGURACIONES DE RECIBOS ==========

  /// Obtener encabezado del recibo
  String getReceiptHeader() => _currentSettings.receiptHeader;

  /// Obtener pie del recibo
  String getReceiptFooter() => _currentSettings.receiptFooter;

  /// Verificar si se debe mostrar logo en recibos
  bool shouldShowLogoOnReceipt() => _currentSettings.showLogoOnReceipt;

  /// Verificar si se debe imprimir automáticamente
  bool shouldPrintReceiptAutomatically() =>
      _currentSettings.printReceiptAutomatically;

  // ========== CARACTERÍSTICAS AVANZADAS ==========

  /// Verificar si backup automático está habilitado
  bool isAutoBackupEnabled() => _currentSettings.enableAutoBackup;

  /// Verificar si notificaciones están habilitadas
  bool areNotificationsEnabled() => _currentSettings.enableNotifications;

  /// Verificar si rastreo de inventario está habilitado
  bool isInventoryTrackingEnabled() => _currentSettings.enableInventoryTracking;

  /// Verificar si aprobación de clientes está habilitada
  bool isClientApprovalEnabled() => _currentSettings.enableClientApproval;

  /// Verificar si encriptación de datos está habilitada
  bool isDataEncryptionEnabled() => _currentSettings.enableDataEncryption;

  /// Verificar si detalles en dashboard están habilitados
  bool shouldShowDetailsOnDashboard() =>
      _currentSettings.showDetailsOnDashboard;

  /// Verificar si modo oscuro está habilitado
  bool isDarkModeEnabled() => _currentSettings.darkModeEnabled;

  /// Obtener timeout de sesión en minutos
  int getSessionTimeoutMinutes() => _currentSettings.sessionTimeoutMinutes;

  /// Obtener duración de sesión
  Duration getSessionTimeout() =>
      Duration(minutes: _currentSettings.sessionTimeoutMinutes);

  // ========== UTILIDADES ==========

  /// Obtener información completa formateada
  String getFormattedBusinessInfo() {
    final buffer = StringBuffer();
    buffer.writeln(_currentSettings.businessName);

    if (_currentSettings.slogan != null &&
        _currentSettings.slogan!.isNotEmpty) {
      buffer.writeln(_currentSettings.slogan);
    }

    if (_currentSettings.rnc != null && _currentSettings.rnc!.isNotEmpty) {
      buffer.writeln('RNC: ${_currentSettings.rnc}');
    }

    if (_currentSettings.phone != null && _currentSettings.phone!.isNotEmpty) {
      buffer.writeln('Teléfono: ${_currentSettings.phone}');
    }

    if (_currentSettings.address != null &&
        _currentSettings.address!.isNotEmpty) {
      buffer.writeln(_currentSettings.address);
    }

    if (_currentSettings.city != null && _currentSettings.city!.isNotEmpty) {
      buffer.writeln(_currentSettings.city);
    }

    return buffer.toString();
  }

  /// Resetear a valores por defecto
  void resetToDefault() {
    _currentSettings = BusinessSettings.defaultSettings;
    _notifyListeners();
  }
}

/// Instancia global del servicio
final appConfigService = AppConfigurationService();
