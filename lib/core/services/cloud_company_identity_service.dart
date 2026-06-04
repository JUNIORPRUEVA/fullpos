import '../../features/registration/services/business_identity_storage.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../session/session_manager.dart';

class CloudCompanyIdentity {
  final String? companyRnc;
  final String? companyCloudId;
  final String? companyTenantKey;
  final String businessId;
  final String terminalId;
  final String companyName;

  const CloudCompanyIdentity({
    required this.companyRnc,
    required this.companyCloudId,
    required this.companyTenantKey,
    required this.businessId,
    required this.terminalId,
    required this.companyName,
  });

  Map<String, dynamic> toPayload() {
    return {
      if (companyTenantKey != null && companyTenantKey!.trim().isNotEmpty)
        'companyTenantKey': companyTenantKey,
      'businessId': businessId,
      'deviceId': terminalId,
      'terminalId': terminalId,
      'companyName': companyName,
      if (companyRnc != null && companyRnc!.isNotEmpty)
        'companyRnc': companyRnc,
      if (companyCloudId != null && companyCloudId!.isNotEmpty)
        'companyCloudId': companyCloudId,
    };
  }
}

class CloudCompanyIdentityService {
  CloudCompanyIdentityService._();

  static String normalizeRnc(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
  }

  static String _normalizeKeyPart(String value) {
    return value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '-',
    );
  }

  static Future<CloudCompanyIdentity> resolve(BusinessSettings settings) async {
    final rnc = settings.rnc?.trim();
    final normalizedRnc = normalizeRnc(rnc);
    final companyCloudId = settings.cloudCompanyId?.trim();
    final businessIdStorage = BusinessIdentityStorage();
    final businessId = (await businessIdStorage.getBusinessId()) ?? '';
    final terminalId = await SessionManager.ensureTerminalId();
    final companyName = settings.businessName.trim().isNotEmpty
        ? settings.businessName.trim()
        : 'FULLPOS';

    // En instalaciones múltiples de la misma empresa, incluir businessId/terminalId
    // en tenantKey provoca conflictos de identidad entre PCs. Si hay RNC o
    // cloudCompanyId, dejamos que backend resuelva por esos localizadores.
    String? tenantKey;
    if (normalizedRnc.isEmpty && (companyCloudId ?? '').isEmpty) {
      tenantKey = [
        'fp',
        'sin-rnc',
        _normalizeKeyPart(businessId),
        _normalizeKeyPart(terminalId),
      ].where((part) => part.trim().isNotEmpty).join('-');
    }

    return CloudCompanyIdentity(
      companyRnc: rnc != null && rnc.isNotEmpty ? rnc : null,
      companyCloudId:
          companyCloudId != null && companyCloudId.isNotEmpty
              ? companyCloudId
              : null,
      companyTenantKey: tenantKey,
      businessId: businessId,
      terminalId: terminalId,
      companyName: companyName,
    );
  }
}