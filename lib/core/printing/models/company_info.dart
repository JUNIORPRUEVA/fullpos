import 'dart:typed_data';
import 'dart:io';
import '../../services/empresa_service.dart';
import '../../../features/settings/data/business_settings_model.dart';
import '../../../features/settings/data/business_settings_repository.dart';

/// Información de la empresa para tickets
/// FUENTE ÚNICA: Solo se lee desde Configuración → Empresa
class CompanyInfo {
  final String name;
  final String? address;
  final String? phone;
  final String? phone2;
  final String? rnc;
  final String? email;
  final String? slogan;
  final String? website;
  final String? logoPath;
  final Uint8List? logoBytes;

  const CompanyInfo({
    required this.name,
    this.address,
    this.phone,
    this.phone2,
    this.rnc,
    this.email,
    this.slogan,
    this.website,
    this.logoPath,
    this.logoBytes,
  });

  /// Obtener teléfono principal o secundario
  String? get primaryPhone {
    if (phone != null && phone!.isNotEmpty) return phone;
    if (phone2 != null && phone2!.isNotEmpty) return phone2;
    return null;
  }

  /// Verificar si tiene datos mínimos configurados
  bool get hasMinimalData {
    return name.isNotEmpty &&
        name.toUpperCase() != 'FULLPOS' &&
      name.toUpperCase() != 'FULLTECH, SRL';
  }

  /// Crear desde BusinessSettings (fuente de BD)
  factory CompanyInfo.fromBusinessSettings(BusinessSettings settings) {
    return CompanyInfo(
      name: settings.businessName.isNotEmpty
          ? settings.businessName
          : 'FULLPOS',
      address: settings.address,
      phone: settings.phone,
      phone2: settings.phone2,
      rnc: settings.rnc,
      email: settings.email,
      slogan: settings.slogan,
      website: settings.website,
      logoPath: settings.logoPath,
    );
  }

  /// Crear desde EmpresaConfig
  factory CompanyInfo.fromEmpresaConfig(EmpresaConfig config) {
    return CompanyInfo(
      name: config.nombreEmpresa.isNotEmpty
          ? config.nombreEmpresa
          : 'FULLPOS',
      address: config.direccion,
      phone: config.telefono,
      phone2: config.telefono2,
      rnc: config.rnc,
      email: config.email,
      slogan: config.slogan,
      website: config.website,
      logoPath: config.logoPath,
    );
  }

  /// Valores por defecto
  factory CompanyInfo.defaults() {
    return const CompanyInfo(
      name: 'FULLTECH, SRL',
      slogan: 'FULLPOS',
    );
  }

  CompanyInfo copyWith({
    String? name,
    String? address,
    String? phone,
    String? phone2,
    String? rnc,
    String? email,
    String? slogan,
    String? website,
    String? logoPath,
    Uint8List? logoBytes,
  }) {
    return CompanyInfo(
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      phone2: phone2 ?? this.phone2,
      rnc: rnc ?? this.rnc,
      email: email ?? this.email,
      slogan: slogan ?? this.slogan,
      website: website ?? this.website,
      logoPath: logoPath ?? this.logoPath,
      logoBytes: logoBytes ?? this.logoBytes,
    );
  }

  @override
  String toString() =>
      'CompanyInfo('
      'name=$name, '
      'phone=$phone, '
      'rnc=$rnc, '
      'address=$address'
      ')';
}

/// Repositorio para obtener CompanyInfo
/// SIEMPRE lee desde la BD, nunca cachea
class CompanyInfoRepository {
  CompanyInfoRepository._();

  /// Obtiene la información actual de la empresa
  /// Esta es la ÚNICA fuente de verdad para datos del negocio
  static Future<CompanyInfo> getCurrentCompanyInfo() async {
    try {
      final config = await EmpresaService.getEmpresaConfig();
      var info = CompanyInfo.fromEmpresaConfig(config);

      final logoPath = (info.logoPath ?? '').trim();
      if (logoPath.isNotEmpty) {
        try {
          final file = File(logoPath);
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty) {
              info = info.copyWith(logoBytes: bytes);
            }
          }
        } catch (_) {
          // Ignorar si no se puede leer el logo.
        }
      }

      return info;
    } catch (e) {
      // Fallback: intentar desde BusinessSettingsRepository
      try {
        final repository = BusinessSettingsRepository();
        final settings = await repository.loadSettings();
        var info = CompanyInfo.fromBusinessSettings(settings);

        final logoPath = (info.logoPath ?? '').trim();
        if (logoPath.isNotEmpty) {
          try {
            final file = File(logoPath);
            if (file.existsSync()) {
              final bytes = await file.readAsBytes();
              if (bytes.isNotEmpty) {
                info = info.copyWith(logoBytes: bytes);
              }
            }
          } catch (_) {
            // Ignorar.
          }
        }

        return info;
      } catch (_) {
        return CompanyInfo.defaults();
      }
    }
  }

  /// Obtiene solo el nombre de la empresa
  static Future<String> getCompanyName() async {
    final info = await getCurrentCompanyInfo();
    return info.name;
  }

  /// Verifica si hay información de empresa configurada
  static Future<bool> hasCompanyInfo() async {
    final info = await getCurrentCompanyInfo();
    return info.hasMinimalData;
  }
}
