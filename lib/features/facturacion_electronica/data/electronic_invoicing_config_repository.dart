import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'electronic_company_repository.dart';
import 'electronic_invoicing_diagnostics_repository.dart';
import 'electronic_sequence_repository.dart';
import 'models/electronic_company_model.dart';
import 'models/electronic_invoicing_config_model.dart';
import 'models/electronic_sequence_model.dart';
import 'models/electronic_signer_model.dart';

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
      final requestId = newElectronicRequestId();
      final response = await api.get(
        '/api/electronic-invoicing/config/by-rnc',
        headers: _headers(settings, requestId: requestId),
        queryParameters: <String, String>{...locators, 'branchId': '0'},
        retry: false,
      );

      final decoded = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallback(localCompany, localSequences, <String>[
          _friendlyMessage(
            message: decoded['message']?.toString(),
            statusCode: response.statusCode,
          ),
        ]);
      }

      final resolved =
          ElectronicInvoicingResolvedConfig.fromBackendMap(
            decoded,
            localApiToken: localCompany.apiToken,
          ).copyWith(
            sequences: mergeResolvedElectronicSequences(
              remote: ElectronicInvoicingResolvedConfig.fromBackendMap(
                decoded,
                localApiToken: localCompany.apiToken,
              ).sequences,
              local: localSequences,
            ),
          );
      await _cacheResolvedConfig(resolved);
      return resolved;
    } on ApiException catch (error) {
      return _fallback(localCompany, localSequences, <String>[error.message]);
    } catch (_) {
      return _fallback(localCompany, localSequences, const <String>[
        'No se pudo validar la configuración con el backend.',
      ]);
    }
  }

  Future<ElectronicInvoicingResolvedConfig> saveConfig({
    required ElectronicCompanyModel company,
    bool? active,
    bool? outboundEnabled,
    bool? authEnabled,
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
      final requestId = newElectronicRequestId();
      response = await api.putJson(
        '/api/electronic-invoicing/config/by-rnc',
        headers: _headers(settings, requestId: requestId),
        body: <String, dynamic>{
          ...locators,
          'branchId': 0,
          'active': active ?? true,
          'outboundEnabled':
              outboundEnabled ?? (company.automaticEmission == 1),
          'authEnabled': authEnabled ?? true,
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

    final resolved =
        ElectronicInvoicingResolvedConfig.fromBackendMap(
          decoded,
          localApiToken: company.apiToken,
        ).copyWith(
          sequences: mergeResolvedElectronicSequences(
            remote: ElectronicInvoicingResolvedConfig.fromBackendMap(
              decoded,
              localApiToken: company.apiToken,
            ).sequences,
            local: await _sequenceRepository.listLocal(),
          ),
        );
    await _cacheResolvedConfig(resolved.copyWithCompany(company));
    return resolved.copyWithCompany(company);
  }

  Future<void> cacheDraftConfig(ElectronicCompanyModel company) async {
    await ElectronicCompanyRepository.save(company);
  }

  Future<void> cacheDraftSequences(
    List<ElectronicSequenceModel> sequences,
  ) async {
    for (final sequence in sequences) {
      await _sequenceRepository.saveLocal(sequence);
    }
  }

  Future<Map<String, String>> _locators(BusinessSettings settings) async {
    return buildElectronicCompanyLocators(
      sessionCompanyId: await SessionManager.companyId(),
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );
  }

  ApiClient _api(BusinessSettings settings) {
    return _apiClient ??
        ApiClient(
          baseUrl: CloudSyncService.instance.debugResolveCloudBaseUrl(settings),
        );
  }

  Map<String, String> _headers(BusinessSettings settings, {String? requestId}) {
    final headers = <String, String>{};
    final id = requestId?.trim();
    if (id != null && id.isNotEmpty) {
      headers['x-request-id'] = id;
    }
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
      return 'La llave de conexión del POS no fue aceptada por el backend';
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
  ElectronicInvoicingResolvedConfig copyWith({
    ElectronicCompanyModel? company,
    List<ElectronicSequenceModel>? sequences,
    ElectronicInvoicingReadiness? readiness,
    Map<String, String?>? companySummary,
    ElectronicSignerModel? signer,
    ElectronicSignerCertificateComparison? certificateComparison,
    bool? dgiiSubmitConfigured,
    bool? dgiiTokenConfigured,
  }) {
    return ElectronicInvoicingResolvedConfig(
      company: company ?? this.company,
      sequences: sequences ?? this.sequences,
      readiness: readiness ?? this.readiness,
      companySummary: companySummary ?? this.companySummary,
      signer: signer ?? this.signer,
      certificateComparison:
          certificateComparison ?? this.certificateComparison,
      dgiiSubmitConfigured: dgiiSubmitConfigured ?? this.dgiiSubmitConfigured,
      dgiiTokenConfigured: dgiiTokenConfigured ?? this.dgiiTokenConfigured,
    );
  }

  ElectronicInvoicingResolvedConfig copyWithCompany(
    ElectronicCompanyModel company,
  ) {
    return ElectronicInvoicingResolvedConfig(
      company: this.company.copyWith(
        apiToken: company.apiToken,
        updatedAtMs: company.updatedAtMs,
      ),
      sequences: sequences,
      readiness: readiness,
      companySummary: companySummary,
      signer: signer,
      certificateComparison: certificateComparison,
      dgiiSubmitConfigured: dgiiSubmitConfigured,
      dgiiTokenConfigured: dgiiTokenConfigured,
    );
  }
}

@visibleForTesting
List<ElectronicSequenceModel> mergeResolvedElectronicSequences({
  required List<ElectronicSequenceModel> remote,
  required List<ElectronicSequenceModel> local,
}) {
  final localByType = {
    for (final sequence in local) sequence.documentTypeCode: sequence,
  };
  final merged = <ElectronicSequenceModel>[];

  for (final remoteSequence in remote) {
    final localSequence = localByType.remove(remoteSequence.documentTypeCode);
    if (localSequence == null) {
      merged.add(remoteSequence);
      continue;
    }

    final mergedCurrent =
        remoteSequence.currentNumber >= localSequence.currentNumber
        ? remoteSequence.currentNumber
        : localSequence.currentNumber;
    final mergedEnd = remoteSequence.endNumber ?? localSequence.endNumber;
    final resolvedStatus = mergedEnd != null && mergedCurrent >= mergedEnd
        ? 'EXHAUSTED'
        : (localSequence.currentNumber > remoteSequence.currentNumber &&
              localSequence.status.trim().isNotEmpty)
        ? localSequence.status
        : remoteSequence.status;

    merged.add(
      remoteSequence.copyWith(
        currentNumber: mergedCurrent,
        endNumber: mergedEnd,
        status: resolvedStatus,
        updatedAtMs: remoteSequence.updatedAtMs >= localSequence.updatedAtMs
            ? remoteSequence.updatedAtMs
            : localSequence.updatedAtMs,
      ),
    );
  }

  merged.addAll(localByType.values);
  merged.sort((a, b) => a.documentTypeCode.compareTo(b.documentTypeCode));
  return merged;
}
