import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Modelo de configuración del negocio con todas las opciones configurables
class BusinessSettings {
  final int id;

  // Información básica del negocio
  final String businessName;
  final String? logoPath;
  final String? phone; // Teléfono principal
  final String? phone2; // Teléfono secundario
  final String? email;
  final String? address;
  final String? city;
  final String? rnc; // Registro Nacional de Contribuyentes
  final String? slogan;
  final String? website;
  final String? instagramUrl;
  final String? facebookUrl;

  // Configuraciones de ventas/impuestos
  final double defaultTaxRate; // Tasa de impuesto por defecto (ITBIS 18%)
  final bool taxIncludedInPrices; // Si los precios ya incluyen impuesto
  final String defaultCurrency; // Moneda por defecto
  final String currencySymbol; // Símbolo de la moneda

  // Configuraciones de recibos/impresión
  final String receiptHeader; // Encabezado del recibo
  final String receiptFooter; // Pie del recibo
  final bool showLogoOnReceipt; // Mostrar logo en recibos
  final bool printReceiptAutomatically; // Imprimir recibo automáticamente
  final String defaultChargeOutputMode; // ticket | pdf | none

  // Configuraciones avanzadas y características
  final bool enableAutoBackup; // Habilitar backup automático
  final bool enableNotifications; // Habilitar notificaciones
  final bool enableInventoryTracking; // Rastreo de inventario
  final bool enableClientApproval; // Requiere aprobación para clientes nuevos
  final bool enableDataEncryption; // Habilitar encriptación de datos
  final bool showDetailsOnDashboard; // Mostrar detalles en dashboard
  final bool darkModeEnabled; // Modo oscuro habilitado
  final int sessionTimeoutMinutes; // Timeout de sesión en minutos

  // Cloud / Nube
  final bool cloudEnabled;
  final String cloudProvider; // aws | gcp | azure | custom
  final String? cloudEndpoint;
  final String? cloudBucket;
  final String? cloudApiKey;
  final List<String> cloudAllowedRoles; // admin/supervisor/cashier
  final String? cloudOwnerAppAndroidUrl;
  final String? cloudOwnerAppIosUrl;
  final String? cloudOwnerUsername;
  final String? cloudCompanyId;

  // Metadatos
  final DateTime createdAt;
  final DateTime updatedAt;

  BusinessSettings({
    this.id = 1,
    this.businessName = 'FULLPOS',
    this.logoPath,
    this.phone,
    this.phone2,
    this.email,
    this.address,
    this.city,
    this.rnc,
    this.slogan,
    this.website,
    this.instagramUrl,
    this.facebookUrl,
    this.defaultTaxRate = 18.0,
    this.taxIncludedInPrices = true,
    this.defaultCurrency = 'DOP',
    this.currencySymbol = 'RD\$',
    this.receiptHeader = '',
    this.receiptFooter = '¡Gracias por su compra!',
    this.showLogoOnReceipt = true,
    this.printReceiptAutomatically = false,
    this.defaultChargeOutputMode = 'ticket',
    this.enableAutoBackup = true,
    this.enableNotifications = true,
    this.enableInventoryTracking = true,
    this.enableClientApproval = false,
    this.enableDataEncryption = true,
    this.showDetailsOnDashboard = true,
    this.darkModeEnabled = false,
    this.sessionTimeoutMinutes = 30,
    this.cloudEnabled = false,
    this.cloudProvider = 'custom',
    this.cloudEndpoint,
    this.cloudBucket,
    this.cloudApiKey,
    this.cloudAllowedRoles = const ['admin'],
    this.cloudOwnerAppAndroidUrl,
    this.cloudOwnerAppIosUrl,
    this.cloudOwnerUsername,
    this.cloudCompanyId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Configuración por defecto
  static final BusinessSettings defaultSettings = BusinessSettings();

  /// Crear desde Map (base de datos)
  factory BusinessSettings.fromMap(Map<String, dynamic> map) {
    return BusinessSettings(
      id: map['id'] as int? ?? 1,
      businessName: map['business_name'] as String? ?? 'FULLPOS',
      logoPath: map['logo_path'] as String?,
      phone: map['phone'] as String?,
      phone2: map['phone2'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      city: map['city'] as String?,
      rnc: map['rnc'] as String?,
      slogan: map['slogan'] as String?,
      website: map['website'] as String?,
      instagramUrl: map['instagram_url'] as String?,
      facebookUrl: map['facebook_url'] as String?,
      defaultTaxRate: (map['default_tax_rate'] as num?)?.toDouble() ?? 18.0,
      taxIncludedInPrices: (map['tax_included_in_prices'] as int? ?? 1) == 1,
      defaultCurrency: map['default_currency'] as String? ?? 'DOP',
      currencySymbol: map['currency_symbol'] as String? ?? 'RD\$',
      receiptHeader: map['receipt_header'] as String? ?? '',
      receiptFooter:
          map['receipt_footer'] as String? ?? '¡Gracias por su compra!',
      showLogoOnReceipt: (map['show_logo_on_receipt'] as int? ?? 1) == 1,
      printReceiptAutomatically:
          (map['print_receipt_automatically'] as int? ?? 0) == 1,
        defaultChargeOutputMode:
          (map['default_charge_output_mode'] as String? ?? 'ticket'),
      enableAutoBackup: (map['enable_auto_backup'] as int? ?? 1) == 1,
      enableNotifications: (map['enable_notifications'] as int? ?? 1) == 1,
      enableInventoryTracking:
          (map['enable_inventory_tracking'] as int? ?? 1) == 1,
      enableClientApproval: (map['enable_client_approval'] as int? ?? 0) == 1,
      enableDataEncryption: (map['enable_data_encryption'] as int? ?? 1) == 1,
      showDetailsOnDashboard:
          (map['show_details_on_dashboard'] as int? ?? 1) == 1,
      darkModeEnabled: (map['dark_mode_enabled'] as int? ?? 0) == 1,
      sessionTimeoutMinutes: map['session_timeout_minutes'] as int? ?? 30,
      cloudEnabled: (map['cloud_enabled'] as int? ?? 0) == 1,
      cloudProvider: map['cloud_provider'] as String? ?? 'custom',
      cloudEndpoint: map['cloud_endpoint'] as String?,
      cloudBucket: map['cloud_bucket'] as String?,
      cloudApiKey: map['cloud_api_key'] as String?,
      cloudAllowedRoles: (() {
        final raw = map['cloud_allowed_roles'];
        if (raw is String && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              return decoded.whereType<String>().toList();
            }
          } catch (_) {}
        }
        return <String>['admin'];
      })(),
      cloudOwnerAppAndroidUrl: map['cloud_owner_app_android_url'] as String?,
      cloudOwnerAppIosUrl: map['cloud_owner_app_ios_url'] as String?,
      cloudOwnerUsername: map['cloud_owner_username'] as String?,
      cloudCompanyId: map['cloud_company_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// Convertir a Map para base de datos
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_name': businessName,
      'logo_path': logoPath,
      'phone': phone,
      'phone2': phone2,
      'email': email,
      'address': address,
      'city': city,
      'rnc': rnc,
      'slogan': slogan,
      'website': website,
      'instagram_url': instagramUrl,
      'facebook_url': facebookUrl,
      'default_tax_rate': defaultTaxRate,
      'tax_included_in_prices': taxIncludedInPrices ? 1 : 0,
      'default_currency': defaultCurrency,
      'currency_symbol': currencySymbol,
      'receipt_header': receiptHeader,
      'receipt_footer': receiptFooter,
      'show_logo_on_receipt': showLogoOnReceipt ? 1 : 0,
      'print_receipt_automatically': printReceiptAutomatically ? 1 : 0,
      'default_charge_output_mode': defaultChargeOutputMode,
      'enable_auto_backup': enableAutoBackup ? 1 : 0,
      'enable_notifications': enableNotifications ? 1 : 0,
      'enable_inventory_tracking': enableInventoryTracking ? 1 : 0,
      'enable_client_approval': enableClientApproval ? 1 : 0,
      'enable_data_encryption': enableDataEncryption ? 1 : 0,
      'show_details_on_dashboard': showDetailsOnDashboard ? 1 : 0,
      'dark_mode_enabled': darkModeEnabled ? 1 : 0,
      'session_timeout_minutes': sessionTimeoutMinutes,
      'cloud_enabled': cloudEnabled ? 1 : 0,
      'cloud_provider': cloudProvider,
      'cloud_endpoint': cloudEndpoint,
      'cloud_bucket': cloudBucket,
      'cloud_api_key': cloudApiKey,
      'cloud_allowed_roles': jsonEncode(cloudAllowedRoles),
      'cloud_owner_app_android_url': cloudOwnerAppAndroidUrl,
      'cloud_owner_app_ios_url': cloudOwnerAppIosUrl,
      'cloud_owner_username': cloudOwnerUsername,
      'cloud_company_id': cloudCompanyId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Convertir a JSON
  String toJson() => json.encode(toMap());

  /// Crear desde JSON
  factory BusinessSettings.fromJson(String source) =>
      BusinessSettings.fromMap(json.decode(source) as Map<String, dynamic>);

  /// Crear copia con cambios
  BusinessSettings copyWith({
    int? id,
    String? businessName,
    String? logoPath,
    String? phone,
    String? phone2,
    String? email,
    String? address,
    String? city,
    String? rnc,
    String? slogan,
    String? website,
    String? instagramUrl,
    String? facebookUrl,
    double? defaultTaxRate,
    bool? taxIncludedInPrices,
    String? defaultCurrency,
    String? currencySymbol,
    String? receiptHeader,
    String? receiptFooter,
    bool? showLogoOnReceipt,
    bool? printReceiptAutomatically,
    String? defaultChargeOutputMode,
    bool? enableAutoBackup,
    bool? enableNotifications,
    bool? enableInventoryTracking,
    bool? enableClientApproval,
    bool? enableDataEncryption,
    bool? showDetailsOnDashboard,
    bool? darkModeEnabled,
    int? sessionTimeoutMinutes,
    bool? cloudEnabled,
    String? cloudProvider,
    String? cloudEndpoint,
    String? cloudBucket,
    String? cloudApiKey,
    List<String>? cloudAllowedRoles,
    String? cloudOwnerAppAndroidUrl,
    String? cloudOwnerAppIosUrl,
    String? cloudOwnerUsername,
    String? cloudCompanyId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearLogoPath = false,
  }) {
    return BusinessSettings(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      logoPath: clearLogoPath ? null : (logoPath ?? this.logoPath),
      phone: phone ?? this.phone,
      phone2: phone2 ?? this.phone2,
      email: email ?? this.email,
      address: address ?? this.address,
      city: city ?? this.city,
      rnc: rnc ?? this.rnc,
      slogan: slogan ?? this.slogan,
      website: website ?? this.website,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      facebookUrl: facebookUrl ?? this.facebookUrl,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      taxIncludedInPrices: taxIncludedInPrices ?? this.taxIncludedInPrices,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      receiptHeader: receiptHeader ?? this.receiptHeader,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      showLogoOnReceipt: showLogoOnReceipt ?? this.showLogoOnReceipt,
      printReceiptAutomatically:
          printReceiptAutomatically ?? this.printReceiptAutomatically,
        defaultChargeOutputMode:
          defaultChargeOutputMode ?? this.defaultChargeOutputMode,
      enableAutoBackup: enableAutoBackup ?? this.enableAutoBackup,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableInventoryTracking:
          enableInventoryTracking ?? this.enableInventoryTracking,
      enableClientApproval: enableClientApproval ?? this.enableClientApproval,
      enableDataEncryption: enableDataEncryption ?? this.enableDataEncryption,
      showDetailsOnDashboard:
          showDetailsOnDashboard ?? this.showDetailsOnDashboard,
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
      sessionTimeoutMinutes:
          sessionTimeoutMinutes ?? this.sessionTimeoutMinutes,
      cloudEnabled: cloudEnabled ?? this.cloudEnabled,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      cloudEndpoint: cloudEndpoint ?? this.cloudEndpoint,
      cloudBucket: cloudBucket ?? this.cloudBucket,
      cloudApiKey: cloudApiKey ?? this.cloudApiKey,
      cloudAllowedRoles: cloudAllowedRoles ?? this.cloudAllowedRoles,
      cloudOwnerAppAndroidUrl:
          cloudOwnerAppAndroidUrl ?? this.cloudOwnerAppAndroidUrl,
      cloudOwnerAppIosUrl: cloudOwnerAppIosUrl ?? this.cloudOwnerAppIosUrl,
      cloudOwnerUsername: cloudOwnerUsername ?? this.cloudOwnerUsername,
      cloudCompanyId: cloudCompanyId ?? this.cloudCompanyId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'BusinessSettings(businessName: $businessName, rnc: $rnc, cloudCompanyId: $cloudCompanyId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusinessSettings &&
        other.id == id &&
        other.businessName == businessName &&
        other.logoPath == logoPath &&
        other.phone == phone &&
        other.phone2 == phone2 &&
        other.email == email &&
        other.address == address &&
        other.city == city &&
        other.rnc == rnc &&
        other.slogan == slogan &&
        other.website == website &&
        other.instagramUrl == instagramUrl &&
        other.facebookUrl == facebookUrl &&
        other.defaultTaxRate == defaultTaxRate &&
        other.taxIncludedInPrices == taxIncludedInPrices &&
        other.defaultCurrency == defaultCurrency &&
        other.currencySymbol == currencySymbol &&
        other.receiptHeader == receiptHeader &&
        other.receiptFooter == receiptFooter &&
        other.showLogoOnReceipt == showLogoOnReceipt &&
        other.printReceiptAutomatically == printReceiptAutomatically &&
        other.defaultChargeOutputMode == defaultChargeOutputMode &&
        other.enableAutoBackup == enableAutoBackup &&
        other.enableNotifications == enableNotifications &&
        other.enableInventoryTracking == enableInventoryTracking &&
        other.enableClientApproval == enableClientApproval &&
        other.enableDataEncryption == enableDataEncryption &&
        other.showDetailsOnDashboard == showDetailsOnDashboard &&
        other.darkModeEnabled == darkModeEnabled &&
        other.sessionTimeoutMinutes == sessionTimeoutMinutes &&
        other.cloudEnabled == cloudEnabled &&
        other.cloudProvider == cloudProvider &&
        other.cloudEndpoint == cloudEndpoint &&
        other.cloudBucket == cloudBucket &&
        other.cloudApiKey == cloudApiKey &&
        listEquals(other.cloudAllowedRoles, cloudAllowedRoles) &&
        other.cloudOwnerAppAndroidUrl == cloudOwnerAppAndroidUrl &&
        other.cloudOwnerAppIosUrl == cloudOwnerAppIosUrl &&
        other.cloudOwnerUsername == cloudOwnerUsername &&
        other.cloudCompanyId == cloudCompanyId;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      businessName,
      logoPath,
      phone,
      phone2,
      email,
      address,
      city,
      rnc,
      slogan,
      website,
      instagramUrl,
      facebookUrl,
      defaultTaxRate,
      taxIncludedInPrices,
      defaultCurrency,
      currencySymbol,
      receiptHeader,
      receiptFooter,
      showLogoOnReceipt,
      printReceiptAutomatically,
      defaultChargeOutputMode,
      enableAutoBackup,
      enableNotifications,
      enableInventoryTracking,
      enableClientApproval,
      enableDataEncryption,
      showDetailsOnDashboard,
      darkModeEnabled,
      sessionTimeoutMinutes,
      cloudEnabled,
      cloudProvider,
      cloudEndpoint,
      cloudBucket,
      cloudApiKey,
      Object.hashAll(cloudAllowedRoles),
      cloudOwnerAppAndroidUrl,
      cloudOwnerAppIosUrl,
      cloudOwnerUsername,
      cloudCompanyId,
    ]);
  }
}
