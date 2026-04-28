import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'electronic_invoicing_diagnostics_repository.dart';
import 'models/electronic_signer_model.dart';

class ElectronicSignerException implements Exception {
  const ElectronicSignerException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class ElectronicSignerRepository {
  ElectronicSignerRepository({ApiClient? apiClient}) : _apiClient = apiClient;

  final ApiClient? _apiClient;

  Future<ElectronicSignerModel> loadSigner() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = await _locators(settings);
    if (locators.isEmpty) {
      return ElectronicSignerModel.empty();
    }

    final api = _api(settings);
    final requestId = newElectronicRequestId();
    try {
      final response = await api.get(
        '/api/electronic-invoicing/signer/by-rnc',
        headers: _headers(settings, requestId: requestId),
        queryParameters: <String, String>{...locators, 'branchId': '0'},
        retry: false,
      );
      final decoded = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ElectronicSignerException(
          _friendlyMessage(
            message: decoded['message']?.toString(),
            statusCode: response.statusCode,
          ),
        );
      }
      final signer =
          (decoded['signer'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return ElectronicSignerModel.fromMap(signer);
    } on ApiException catch (error) {
      throw ElectronicSignerException(error.message);
    }
  }

  Future<ElectronicSignerModel> saveSigner({
    required ElectronicSignerModel signer,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = await _locators(settings);
    if (locators.isEmpty) {
      throw const ElectronicSignerException(
        'No se pudo identificar la empresa actual',
      );
    }

    final api = _api(settings);
    final requestId = newElectronicRequestId();
    late final dynamic response;
    try {
      response = await api.putJson(
        '/api/electronic-invoicing/signer/by-rnc',
        headers: _headers(settings, requestId: requestId),
        body: <String, dynamic>{
          ...locators,
          'signerFullName': signer.signerFullName.trim(),
          'signerDocumentType': signer.signerDocumentType.trim().toUpperCase(),
          'signerDocumentNumber': signer.signerDocumentNumber.trim().replaceAll(
            RegExp(r'[-\s]'),
            '',
          ),
          'signerAuthorizedForDgii': signer.signerAuthorizedForDgii,
        },
        retry: false,
      );
    } on ApiException catch (error) {
      throw ElectronicSignerException(error.message);
    }

    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ElectronicSignerException(
        _friendlyMessage(
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }

    final signerMap =
        (decoded['signer'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return ElectronicSignerModel.fromMap(signerMap);
  }

  Future<Map<String, String>> _locators(BusinessSettings settings) async {
    final sessionCompanyId = await SessionManager.companyId();
    return buildElectronicCompanyLocators(
      sessionCompanyId: sessionCompanyId,
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
    return 'No se pudo guardar el responsable de firma';
  }
}
