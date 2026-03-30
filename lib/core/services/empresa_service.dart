import 'package:flutter/foundation.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/business_settings_repository.dart';

/// Modelo único para datos de empresa (Single Source of Truth)
class EmpresaConfig {
  final String nombreEmpresa;
  final String? telefono;
  final String? telefono2;
  final String? direccion;
  final String? ciudad;
  final String? rnc;
  final String? email;
  final String? slogan;
  final String? website;
  final String? instagramUrl;
  final String? facebookUrl;
  final String? logoPath;

  EmpresaConfig({
    required this.nombreEmpresa,
    this.telefono,
    this.telefono2,
    this.direccion,
    this.ciudad,
    this.rnc,
    this.email,
    this.slogan,
    this.website,
    this.instagramUrl,
    this.facebookUrl,
    this.logoPath,
  });

  /// Crear desde BusinessSettings
  factory EmpresaConfig.fromBusinessSettings(BusinessSettings settings) {
    return EmpresaConfig(
      nombreEmpresa: settings.businessName,
      telefono: settings.phone,
      telefono2: settings.phone2,
      direccion: settings.address,
      ciudad: settings.city,
      rnc: settings.rnc,
      email: settings.email,
      slogan: settings.slogan,
      website: settings.website,
      instagramUrl: settings.instagramUrl,
      facebookUrl: settings.facebookUrl,
      logoPath: settings.logoPath,
    );
  }

  /// Obtener teléfono principal o secundario
  String? getTelefono() {
    if (telefono != null && telefono!.isNotEmpty) return telefono;
    if (telefono2 != null && telefono2!.isNotEmpty) return telefono2;
    return null;
  }

  String get direccionCompleta {
    final parts = <String>[
      (direccion ?? '').trim(),
      (ciudad ?? '').trim(),
    ].where((value) => value.isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  bool get hasConfiguredBusinessName {
    final normalized = nombreEmpresa.trim();
    return normalized.isNotEmpty && normalized.toUpperCase() != 'FULLPOS';
  }

  List<String> missingElectronicInvoicingFields() {
    final missing = <String>[];
    if (!hasConfiguredBusinessName) missing.add('Nombre empresa');
    if ((rnc ?? '').trim().isEmpty) missing.add('RNC');
    if (direccionCompleta.isEmpty) missing.add('Dirección');
    return missing;
  }

  /// Validar que tenemos datos mínimos
  bool hasMinimalData() {
    return missingElectronicInvoicingFields().isEmpty;
  }

  @override
  String toString() => 'EmpresaConfig('
      'nombre=$nombreEmpresa, '
      'tel=$telefono, '
      'rnc=$rnc, '
      'dir=$direccion'
      ')';
}

/// Servicio centralizado para obtener configuración de empresa
/// Single Source of Truth para todos los módulos
class EmpresaService {
  EmpresaService._();

  /// Obtener la configuración actual de empresa (ÚNICA FUENTE DE VERDAD)
  /// Siempre lee desde la base de datos, nunca cachea
  static Future<EmpresaConfig> getEmpresaConfig() async {
    try {
      // Leer directamente desde repositorio (sin cache)
      final repository = BusinessSettingsRepository();
      final settings = await repository.loadSettings();
      
      debugPrint('📋 EmpresaService: Cargada configuración de empresa: ${settings.businessName}');
      
      return EmpresaConfig.fromBusinessSettings(settings);
    } catch (e) {
      debugPrint('❌ Error cargando EmpresaConfig: $e');
      
      // Retornar valores por defecto seguros
      return EmpresaConfig(
        nombreEmpresa: 'FULLPOS',
        telefono: null,
        direccion: null,
        rnc: null,
        email: null,
        website: null,
        instagramUrl: null,
        facebookUrl: null,
      );
    }
  }

  /// Obtener solo el nombre de empresa
  static Future<String> getEmpresaNombre() async {
    final config = await getEmpresaConfig();
    return config.nombreEmpresa;
  }

  /// Obtener solo el teléfono
  static Future<String?> getEmpresaTelefono() async {
    final config = await getEmpresaConfig();
    return config.getTelefono();
  }

  /// Obtener solo la dirección
  static Future<String?> getEmpresaDireccion() async {
    final config = await getEmpresaConfig();
    return config.direccion;
  }

  /// Obtener solo el RNC
  static Future<String?> getEmpresaRnc() async {
    final config = await getEmpresaConfig();
    return config.rnc;
  }

  /// Obtener solo el email
  static Future<String?> getEmpresaEmail() async {
    final config = await getEmpresaConfig();
    return config.email;
  }

  /// Obtener solo el logo
  static Future<String?> getEmpresaLogo() async {
    final config = await getEmpresaConfig();
    return config.logoPath;
  }
}
