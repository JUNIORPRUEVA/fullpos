import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_repository.dart';
import 'electronic_sequence_repository.dart';
import 'models/electronic_company_model.dart';
import 'models/electronic_invoicing_config_model.dart';
import 'models/electronic_sequence_model.dart';

class ElectronicInvoicingConfigException implements Exception {
  const ElectronicInvoicingConfigException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class ElectronicInvoicingConfigRepository {
  ElectronicInvoicingConfigRepository({ApiClient? apiClient})
      : _apiClient = apiClient;

  final ApiClient? _apiClient;
  final ElectronicSequenceRepository _sequenceRepository =
      ElectronicSequenceRepository();

  Future<ElectronicInvoicingResolvedConfig> loadResolvedConfig() async {
    final localCompany = await ElectronicCompanyRepository.getOrCreate();
    final localSequences = await _sequenceRepository.listLocal();
    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = await _locators(settings);

    if (locators.isEmpty) {
      return _fallback(localCompany, localSequences, const <String>[]);
    }

    try {
      final api = _api(settings);
      final response = await api.get(
        '/api/electronic-invoicing/config/by-rnc',
        headers: _headers(settings),
        queryParameters: <String, String>{
          ...locators,
          'branchId': '0',
        },
        retry: false,
      );

      final decoded = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallback(
          localCompany,
          localSequences,
          <String>[
            _friendlyMessage(
              message: decoded['message']?.toString(),
              statusCode: response.statusCode,
            ),
          ],
        );
      }

      final resolved = ElectronicInvoicingResolvedConfig.fromBackendMap(
        decoded,
        localApiToken: localCompany.apiToken,
      );
      await _cacheResolvedConfig(resolved);
      return resolved;
    } catch (_) {
      return _fallback(
        localCompany,
        localSequences,
        const <String>['No se pudo validar la configuración con el backend.'],
      );
    }
  }

  Future<ElectronicInvoicingResolvedConfig> saveConfig({
    required ElectronicCompanyModel company,
    required bool electronicInvoicingEnabled,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = await _locators(settings);
    if (locators.isEmpty) {
      throw const ElectronicInvoicingConfigException(
        'No se pudo identificar la empresa actual',
      );
    }

    final api = _api(settings);
    late final dynamic response;
    try {
      response = await api.putJson(
        '/api/electronic-invoicing/config/by-rnc',
        headers: _headers(settings),
        body: <String, dynamic>{
          ...locators,
          'branchId': 0,
          'active': electronicInvoicingEnabled,
          'outboundEnabled': company.automaticEmission == 1,
          'authEnabled': true,
          'environment': _backendEnvironment(company.environment),
          'publicBaseUrl': api.baseUrl,
          'tokenTtlSeconds': 300,
        },
        retry: false,
      );
    } on ApiException catch (error) {
      throw ElectronicInvoicingConfigException(error.message);
    }

    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ElectronicInvoicingConfigException(
        _friendlyMessage(
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }

    final resolved = ElectronicInvoicingResolvedConfig.fromBackendMap(
      decoded,
      localApiToken: company.apiToken,
    );
    await _cacheResolvedConfig(resolved.copyWithCompany(company));
    return resolved.copyWithCompany(company);
  }

  Future<void> cacheDraftConfig(ElectronicCompanyModel company) async {
    await ElectronicCompanyRepository.save(company);
  }

  Future<void> cacheDraftSequences(List<ElectronicSequenceModel> sequences) async {
    for (final sequence in sequences) {
      await _sequenceRepository.saveLocal(sequence);
    }
  }

  Future<Map<String, String>> _locators(BusinessSettings settings) async {
    final companyId = await SessionManager.companyId();
    final locators = <String, String>{};
    if (companyId != null) {
      locators['companyId'] = companyId.toString();
    }
    final companyCloudId = settings.cloudCompanyId?.trim();
    if (companyCloudId != null && companyCloudId.isNotEmpty) {
      locators['companyCloudId'] = companyCloudId;
    }
    final rnc = settings.rnc?.trim();
    if (rnc != null && rnc.isNotEmpty) {
      locators['companyRnc'] = rnc;
    }
    return locators;
  }

  ApiClient _api(BusinessSettings settings) {
    return _apiClient ??
        ApiClient(
          baseUrl:
              CloudSyncService.instance.debugResolveCloudBaseUrl(settings),
        );
  }

  Map<String, String> _headers(BusinessSettings settings) {
    final headers = <String, String>{};
    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey != null && cloudKey.isNotEmpty) {
      headers['x-cloud-key'] = cloudKey;
    }
    return headers;
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  String _friendlyMessage({String? message, int? statusCode}) {
    if (statusCode == 401 || statusCode == 403) {
      return 'No se pudo validar la empresa en el backend';
    }
    final normalized = (message ?? '').trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return 'No se pudo guardar la configuración de facturación electrónica';
  }

  Future<void> _cacheResolvedConfig(
    ElectronicInvoicingResolvedConfig resolved,
  ) async {
    await ElectronicCompanyRepository.save(resolved.company);
    for (final sequence in resolved.sequences) {
      await _sequenceRepository.saveLocal(sequence);
    }
  }

  ElectronicInvoicingResolvedConfig _fallback(
    ElectronicCompanyModel localCompany,
    List<ElectronicSequenceModel> localSequences,
    List<String> messages,
  ) {
    final missing = <String>[];
    if (!localCompany.hasCertificateConfigured) {
      missing.add('Certificado');
    }
    for (final sequence in localSequences) {
      if (!sequence.hasAuthorizedRange) {
        missing.add('Secuencia ${sequence.documentTypeCode}');
      }
    }
    return ElectronicInvoicingResolvedConfig.localFallback(
      company: localCompany,
      sequences: localSequences,
      missing: missing,
      messages: messages,
    );
  }

  String _backendEnvironment(String uiValue) {
    return uiValue.trim().toLowerCase() == 'produccion'
        ? 'production'
        : 'precertification';
  }
}

extension on ElectronicInvoicingResolvedConfig {
  ElectronicInvoicingResolvedConfig copyWithCompany(
    ElectronicCompanyModel company,
  ) {
    return ElectronicInvoicingResolvedConfig(
      company: company.copyWith(
        environment: this.company.environment,
        certificateName: this.company.certificateName,
        certificateValidFromMs: this.company.certificateValidFromMs,
        certificateValidToMs: this.company.certificateValidToMs,
        certificateStatus: this.company.certificateStatus,
        automaticEmission: this.company.automaticEmission,
      ),
      sequences: sequences,
      readiness: readiness,
      companySummary: companySummary,
      dgiiSubmitConfigured: dgiiSubmitConfigured,
      dgiiTokenConfigured: dgiiTokenConfigured,
    );
  }
}