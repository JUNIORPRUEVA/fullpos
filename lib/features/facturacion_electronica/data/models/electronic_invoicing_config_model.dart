import 'electronic_company_model.dart';
import 'electronic_sequence_model.dart';
import 'electronic_signer_model.dart';

class ElectronicInvoicingReadiness {
  const ElectronicInvoicingReadiness({
    required this.status,
    required this.missing,
    required this.messages,
    required this.checklist,
    this.backendValidated = false,
  });

  final String status;
  final List<String> missing;
  final List<String> messages;
  final Map<String, bool> checklist;
  final bool backendValidated;

  bool get isReady => status == 'READY';

  String get uiLabel {
    switch (status) {
      case 'READY':
        return 'LISTO';
      case 'PARTIAL':
        return 'PARCIAL';
      default:
        return 'NO LISTO';
    }
  }

  factory ElectronicInvoicingReadiness.fromMap(
    Map<String, dynamic> map, {
    bool backendValidated = true,
  }) {
    final rawChecklist = map['checklist'];
    final checklist = <String, bool>{};
    if (rawChecklist is Map) {
      for (final entry in rawChecklist.entries) {
        checklist[entry.key.toString()] = entry.value == true;
      }
    }

    return ElectronicInvoicingReadiness(
      status: (map['status']?.toString().trim().toUpperCase() ?? 'NOT_READY'),
      missing:
          (map['missing'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
      messages:
          (map['messages'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
      checklist: checklist,
      backendValidated: backendValidated,
    );
  }

  factory ElectronicInvoicingReadiness.localFallback({
    required List<String> missing,
    required List<String> messages,
  }) {
    return ElectronicInvoicingReadiness(
      status: missing.isEmpty ? 'READY' : 'PARTIAL',
      missing: missing,
      messages: messages,
      checklist: const <String, bool>{},
      backendValidated: false,
    );
  }
}

class ElectronicInvoicingResolvedConfig {
  const ElectronicInvoicingResolvedConfig({
    required this.company,
    required this.sequences,
    required this.readiness,
    required this.companySummary,
    required this.signer,
    this.certificateComparison,
    this.dgiiSubmitConfigured = false,
    this.dgiiTokenConfigured = false,
  });

  final ElectronicCompanyModel company;
  final List<ElectronicSequenceModel> sequences;
  final ElectronicInvoicingReadiness readiness;
  final Map<String, String?> companySummary;
  final ElectronicSignerModel signer;
  final ElectronicSignerCertificateComparison? certificateComparison;
  final bool dgiiSubmitConfigured;
  final bool dgiiTokenConfigured;

  factory ElectronicInvoicingResolvedConfig.fromBackendMap(
    Map<String, dynamic> map, {
    required String localApiToken,
  }) {
    final companyMap =
        (map['company'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final configMap =
        (map['config'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final certificateMap = (map['certificate'] as Map?)
        ?.cast<String, dynamic>();
    final dgiiMap =
        (map['dgii'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final signerMap =
        (map['signer'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final certificateComparisonMap = (map['certificateComparison'] as Map?)
        ?.cast<String, dynamic>();
    final readinessMap =
        (map['readiness'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final companyName = companyMap['companyName']?.toString().trim() ?? '';
    final companyRnc = companyMap['rnc']?.toString().trim() ?? '';
    final companyAddress = companyMap['address']?.toString().trim() ?? '';
    final companyPhone = companyMap['phone']?.toString().trim() ?? '';
    final companyEmail = companyMap['email']?.toString().trim() ?? '';

    final certificateStatus =
        certificateMap?['status']?.toString().trim().toLowerCase() ?? '';
    final company = ElectronicCompanyModel.defaults().copyWith(
      id: int.tryParse(companyMap['companyId']?.toString() ?? ''),
      businessName: companyName,
      tradeName: companyName,
      rnc: companyRnc,
      emissionAddress: companyAddress,
      phone: companyPhone,
      email: companyEmail,
      environment:
          (configMap['uiEnvironment']?.toString().trim().isNotEmpty ?? false)
          ? configMap['uiEnvironment'].toString().trim()
          : _uiEnvironmentFromBackend(configMap['environment']?.toString()),
      apiToken: localApiToken,
      certificateName: certificateMap?['alias']?.toString().trim() ?? '',
      certificateValidFromMs: _dateToMs(certificateMap?['validFrom']),
      certificateValidToMs: _dateToMs(certificateMap?['validTo']),
      certificateStatus: certificateStatus,
      automaticEmission: configMap['outboundEnabled'] == true ? 1 : 0,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final sequences =
        (map['sequences'] as List?)
            ?.whereType<Map>()
            .map(
              (item) =>
                  ElectronicSequenceModel.fromMap(item.cast<String, Object?>()),
            )
            .toList(growable: false) ??
        const <ElectronicSequenceModel>[];

    return ElectronicInvoicingResolvedConfig(
      company: company,
      sequences: sequences,
      readiness: ElectronicInvoicingReadiness.fromMap(readinessMap),
      companySummary: <String, String?>{
        'companyId': companyMap['companyId']?.toString(),
        'companyCloudId': companyMap['companyCloudId']?.toString(),
        'companyName': companyMap['companyName']?.toString(),
        'rnc': companyMap['rnc']?.toString(),
        'address': companyMap['address']?.toString(),
        'city': companyMap['city']?.toString(),
        'phone': companyMap['phone']?.toString(),
        'email': companyMap['email']?.toString(),
      },
      signer: ElectronicSignerModel.fromMap(signerMap),
      certificateComparison: certificateComparisonMap == null
          ? null
          : ElectronicSignerCertificateComparison.fromMap(
              certificateComparisonMap,
            ),
      dgiiSubmitConfigured: dgiiMap['submitConfigured'] == true,
      dgiiTokenConfigured: dgiiMap['tokenConfigured'] == true,
    );
  }

  factory ElectronicInvoicingResolvedConfig.localFallback({
    required ElectronicCompanyModel company,
    required List<ElectronicSequenceModel> sequences,
    required List<String> missing,
    required List<String> messages,
  }) {
    return ElectronicInvoicingResolvedConfig(
      company: company,
      sequences: sequences,
      readiness: ElectronicInvoicingReadiness.localFallback(
        missing: missing,
        messages: messages,
      ),
      companySummary: const <String, String?>{},
      signer: ElectronicSignerModel.empty(),
      certificateComparison: null,
    );
  }

  static int? _dateToMs(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.millisecondsSinceEpoch;
  }

  static String _uiEnvironmentFromBackend(String? value) {
    return (value ?? '').trim().toLowerCase() == 'production'
        ? 'produccion'
        : 'pruebas';
  }
}
