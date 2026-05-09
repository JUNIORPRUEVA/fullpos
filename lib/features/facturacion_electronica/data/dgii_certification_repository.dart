import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'electronic_invoicing_diagnostics_repository.dart';
import 'models/dgii_certification_model.dart';

class DgiiCertificationException implements Exception {
  const DgiiCertificationException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class DgiiCertificationRepository {
  DgiiCertificationRepository({ApiClient? apiClient}) : _apiClient = apiClient;

  final ApiClient? _apiClient;

  Future<DgiiCertificationDiagnosticsModel>
  getCertificationDiagnostics() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/diagnostics',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
    return DgiiCertificationDiagnosticsModel.fromMap(decoded);
  }

  Future<String> downloadManualDgiiSeed() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/dgii-auth/seed',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
    return response.body;
  }

  Future<DgiiManualSignedSeedResult> uploadManualSignedDgiiSeed(
    String filePath,
  ) async {
    if (!filePath.toLowerCase().endsWith('.xml')) {
      throw const DgiiCertificationException(
        'Seleccione el XML de semilla firmado por la app DGII',
      );
    }

    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = await _locators(settings);
    if (locators.isEmpty) {
      throw const DgiiCertificationException(
        'No se pudo identificar la empresa actual',
      );
    }

    final api = _api(settings);
    final uri = api.uri(
      '/api/electronic-invoicing/certification/dgii-auth/signed-seed',
    );
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers(settings));
    request.headers['x-request-id'] = newElectronicRequestId();
    request.fields.addAll(locators);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType('application', 'xml'),
      ),
    );

    try {
      final streamed = await api.sendMultipart(
        request,
        timeout: const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamed);
      final decoded = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DgiiCertificationException(
          _friendlyMessage(
            errorCode: decoded['errorCode']?.toString(),
            message: decoded['message']?.toString(),
            statusCode: response.statusCode,
            details: _detailsFromDecoded(decoded),
          ),
        );
      }
      return DgiiManualSignedSeedResult.fromMap(decoded);
    } on DgiiCertificationException {
      rethrow;
    } on ApiException catch (error) {
      throw DgiiCertificationException(error.message);
    } catch (error) {
      throw DgiiCertificationException(error.toString());
    }
  }

  Future<DgiiCertificationImportResult> importCertificationExcel(
    String filePath,
  ) async {
    if (!filePath.toLowerCase().endsWith('.xlsx')) {
      throw const DgiiCertificationException(
        'Seleccione un archivo Excel .xlsx',
      );
    }

    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = await _locators(settings);
    if (locators.isEmpty) {
      throw const DgiiCertificationException(
        'No se pudo identificar la empresa actual',
      );
    }

    final api = _api(settings);
    final uri = api.uri('/api/electronic-invoicing/certification/import-excel');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers(settings));
    request.headers['x-request-id'] = newElectronicRequestId();
    request.fields.addAll(locators);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ),
    );

    try {
      final streamed = await api.sendMultipart(
        request,
        timeout: const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamed);
      final decoded = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DgiiCertificationException(
          _friendlyMessage(
            errorCode: decoded['errorCode']?.toString(),
            message: decoded['message']?.toString(),
            statusCode: response.statusCode,
          ),
        );
      }
      return DgiiCertificationImportResult.fromMap(decoded);
    } on DgiiCertificationException {
      rethrow;
    } on ApiException catch (error) {
      throw DgiiCertificationException(error.message);
    } catch (error) {
      throw DgiiCertificationException(error.toString());
    }
  }

  Future<List<DgiiCertificationBatchModel>> getCertificationBatches() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/batches',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    final decoded = _decodeList(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              DgiiCertificationBatchModel.fromMap(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<List<DgiiCertificationCaseModel>> getCertificationBatchCases(
    int batchId, {
    String? sheetName,
    String? status,
    String? tipoEcf,
    String? search,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final query = <String, String>{
      ...await _locators(settings),
      if (sheetName?.trim().isNotEmpty == true) 'sheetName': sheetName!.trim(),
      if (status?.trim().isNotEmpty == true) 'status': status!.trim(),
      if (tipoEcf?.trim().isNotEmpty == true) 'tipoEcf': tipoEcf!.trim(),
      if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
    };
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/batches/$batchId/cases',
      headers: _headers(settings),
      queryParameters: query,
      retry: false,
    );
    final decoded = _decodeList(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              DgiiCertificationCaseModel.fromMap(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<DgiiCertificationCaseModel> getCertificationCase(int caseId) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/cases/$caseId',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
          details: _detailsFromDecoded(decoded),
        ),
      );
    }
    return DgiiCertificationCaseModel.fromMap(decoded);
  }

  Future<DgiiCertificationCaseModel> generateCertificationCaseXml(
    int caseId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/generate-xml',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
          details: _detailsFromDecoded(decoded),
        ),
      );
    }
    final item = (decoded['case'] as Map?)?.cast<String, dynamic>() ?? decoded;
    return DgiiCertificationCaseModel.fromMap(item);
  }

  Future<DgiiCertificationBatchXmlResult> generateCertificationBatchXml(
    int batchId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/batches/$batchId/generate-xml',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }
    return DgiiCertificationBatchXmlResult.fromMap(decoded);
  }

  Future<DgiiCertificationCasePreflightModel> preflightCertificationCase(
    int caseId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/preflight',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }
    return DgiiCertificationCasePreflightModel.fromMap(decoded);
  }

  Future<DgiiCertificationBatchPreflightModel> preflightCertificationBatch(
    int batchId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/batches/$batchId/preflight',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }
    return DgiiCertificationBatchPreflightModel.fromMap(decoded);
  }

  Future<DgiiCertificationCaseModel> signCertificationCase(int caseId) async {
    return _caseAction(
      '/api/electronic-invoicing/certification/cases/$caseId/sign',
    );
  }

  Future<DgiiCertificationCaseModel> resetCertificationCase(
    int caseId, {
    bool force = false,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final body = <String, dynamic>{
      ...await _locators(settings),
      if (force) 'force': true,
    };
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/reset',
      headers: _headers(settings),
      body: body,
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
          details: _detailsFromDecoded(decoded),
        ),
      );
    }
    final item = (decoded['case'] as Map?)?.cast<String, dynamic>() ?? decoded;
    return DgiiCertificationCaseModel.fromMap(item);
  }

  Future<Map<String, dynamic>> resetCertificationBatch(
    int batchId, {
    bool force = false,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final body = <String, dynamic>{
      ...await _locators(settings),
      if (force) 'force': true,
    };
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/batches/$batchId/reset',
      headers: _headers(settings),
      body: body,
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
          details: _detailsFromDecoded(decoded),
        ),
      );
    }
    return decoded;
  }

  Future<DgiiCertificationXmlValidationResult> validateCertificationCaseXml(
    int caseId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/validate-xml',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }
    return DgiiCertificationXmlValidationResult.fromMap(decoded);
  }

  Future<DgiiCertificationBatchActionResult> signCertificationBatch(
    int batchId,
  ) async {
    return _batchAction(
      '/api/electronic-invoicing/certification/batches/$batchId/sign',
    );
  }

  Future<DgiiCertificationCaseModel> sendCertificationCase(int caseId) async {
    return _caseAction(
      '/api/electronic-invoicing/certification/cases/$caseId/send',
      timeout: const Duration(seconds: 45),
    );
  }

  Future<DgiiCertificationBatchActionResult> sendCertificationBatch(
    int batchId,
  ) async {
    return _batchAction(
      '/api/electronic-invoicing/certification/batches/$batchId/send',
      timeout: const Duration(minutes: 5),
    );
  }

  Future<Map<String, dynamic>> reprocessAndSendCertificationBatch(
    int batchId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/batches/$batchId/reprocess-and-send',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
      timeout: const Duration(minutes: 6),
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
          details: _detailsFromDecoded(decoded),
        ),
      );
    }
    return decoded;
  }

  Future<DgiiCertificationCaseModel> queryCertificationCaseResult(
    int caseId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/cases/$caseId/result',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }
    final item = (decoded['case'] as Map?)?.cast<String, dynamic>() ?? decoded;
    return DgiiCertificationCaseModel.fromMap(item);
  }

  Future<DgiiCertificationBatchActionResult> queryCertificationBatchResults(
    int batchId,
  ) async {
    return _batchAction(
      '/api/electronic-invoicing/certification/batches/$batchId/query-results',
    );
  }

  Future<DgiiCertificationBatchSummary> getCertificationBatchSummary(
    int batchId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/batches/$batchId/summary',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
    return DgiiCertificationBatchSummary.fromMap(decoded);
  }

  Future<DgiiCertificationAuditResult> auditCertificationCase(int caseId) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/audit',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_friendlyMessage(
        errorCode: decoded['errorCode']?.toString(),
        message: decoded['message']?.toString(),
        statusCode: response.statusCode,
        details: _detailsFromDecoded(decoded),
      ));
    }
    return DgiiCertificationAuditResult.fromMap(decoded);
  }

  Future<DgiiCertificationAuditResult> aiAuditCertificationCase(
    int caseId, {
    String? aiApiKey,
    String? aiModel,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/ai-audit',
      headers: _headers(settings),
      body: {
        ...await _locators(settings),
        if (aiApiKey?.trim().isNotEmpty == true) 'aiApiKey': aiApiKey!.trim(),
        if (aiModel?.trim().isNotEmpty == true) 'aiModel': aiModel!.trim(),
      },
      retry: false,
      throwOnServerError: false,
      timeout: const Duration(minutes: 2),
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_friendlyMessage(
        errorCode: decoded['errorCode']?.toString(),
        message: decoded['message']?.toString(),
        statusCode: response.statusCode,
        details: _detailsFromDecoded(decoded),
      ));
    }
    return DgiiCertificationAuditResult.fromMap(decoded);
  }

  Future<Map<String, dynamic>> aiFixSuggestionCertificationCase(
    int caseId, {
    String? aiApiKey,
    String? aiModel,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/ai-fix-suggestion',
      headers: _headers(settings),
      body: {
        ...await _locators(settings),
        if (aiApiKey?.trim().isNotEmpty == true) 'aiApiKey': aiApiKey!.trim(),
        if (aiModel?.trim().isNotEmpty == true) 'aiModel': aiModel!.trim(),
      },
      retry: false,
      throwOnServerError: false,
      timeout: const Duration(minutes: 2),
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_friendlyMessage(
        errorCode: decoded['errorCode']?.toString(),
        message: decoded['message']?.toString(),
        statusCode: response.statusCode,
        details: _detailsFromDecoded(decoded),
      ));
    }
    return decoded;
  }

  Future<Map<String, dynamic>> applyCertifiedFixCertificationCase(
    int caseId,
  ) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/cases/$caseId/apply-certified-fix',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
      timeout: const Duration(minutes: 2),
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_friendlyMessage(
        errorCode: decoded['errorCode']?.toString(),
        message: decoded['message']?.toString(),
        statusCode: response.statusCode,
        details: _detailsFromDecoded(decoded),
      ));
    }
    return decoded;
  }

  Future<Map<String, dynamic>> auditCertificationBatch(int batchId) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/batches/$batchId/audit',
      headers: _headers(settings),
      body: await _locators(settings),
      retry: false,
      throwOnServerError: false,
      timeout: const Duration(minutes: 2),
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_friendlyMessage(
        errorCode: decoded['errorCode']?.toString(),
        message: decoded['message']?.toString(),
        statusCode: response.statusCode,
        details: _detailsFromDecoded(decoded),
      ));
    }
    return decoded;
  }

  Future<Map<String, dynamic>> aiAuditCertificationBatch(
    int batchId, {
    String? aiApiKey,
    String? aiModel,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/batches/$batchId/ai-audit',
      headers: _headers(settings),
      body: {
        ...await _locators(settings),
        if (aiApiKey?.trim().isNotEmpty == true) 'aiApiKey': aiApiKey!.trim(),
        if (aiModel?.trim().isNotEmpty == true) 'aiModel': aiModel!.trim(),
      },
      retry: false,
      throwOnServerError: false,
      timeout: const Duration(minutes: 3),
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_friendlyMessage(
        errorCode: decoded['errorCode']?.toString(),
        message: decoded['message']?.toString(),
        statusCode: response.statusCode,
        details: _detailsFromDecoded(decoded),
      ));
    }
    return decoded;
  }

  Future<Map<String, dynamic>> aiFixSuggestionCertificationBatch(
    int batchId, {
    String? aiApiKey,
    String? aiModel,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      '/api/electronic-invoicing/certification/batches/$batchId/ai-fix-suggestion',
      headers: _headers(settings),
      body: {
        ...await _locators(settings),
        if (aiApiKey?.trim().isNotEmpty == true) 'aiApiKey': aiApiKey!.trim(),
        if (aiModel?.trim().isNotEmpty == true) 'aiModel': aiModel!.trim(),
      },
      retry: false,
      throwOnServerError: false,
      timeout: const Duration(minutes: 3),
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_friendlyMessage(
        errorCode: decoded['errorCode']?.toString(),
        message: decoded['message']?.toString(),
        statusCode: response.statusCode,
        details: _detailsFromDecoded(decoded),
      ));
    }
    return decoded;
  }

  Future<String> getCertificationCaseXml(int caseId) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/cases/$caseId/xml',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
    return response.body;
  }

  Future<String> getCertificationCaseSignedXml(int caseId) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).get(
      '/api/electronic-invoicing/certification/cases/$caseId/signed-xml',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
    return response.body;
  }

  Future<DgiiCertificationCaseModel> uploadManualSignedCertificationCaseXml(
    int caseId,
    String filePath,
  ) async {
    if (!filePath.toLowerCase().endsWith('.xml')) {
      throw const DgiiCertificationException(
        'Seleccione el XML firmado por la app DGII',
      );
    }

    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = await _locators(settings);
    if (locators.isEmpty) {
      throw const DgiiCertificationException(
        'No se pudo identificar la empresa actual',
      );
    }

    final api = _api(settings);
    final uri = api.uri(
      '/api/electronic-invoicing/certification/cases/$caseId/signed-xml/import',
    );
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers(settings));
    request.headers['x-request-id'] = newElectronicRequestId();
    request.fields.addAll(locators);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType('application', 'xml'),
      ),
    );

    try {
      final streamed = await api.sendMultipart(
        request,
        timeout: const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamed);
      final decoded = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DgiiCertificationException(
          _friendlyMessage(
            errorCode: decoded['errorCode']?.toString(),
            message: decoded['message']?.toString(),
            statusCode: response.statusCode,
            details: _detailsFromDecoded(decoded),
          ),
        );
      }
      final item = (decoded['case'] as Map?)?.cast<String, dynamic>() ?? decoded;
      return DgiiCertificationCaseModel.fromMap(item);
    } on DgiiCertificationException {
      rethrow;
    } on ApiException catch (error) {
      throw DgiiCertificationException(error.message);
    } catch (error) {
      throw DgiiCertificationException(error.toString());
    }
  }

  Future<void> deleteCertificationBatch(int batchId) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).delete(
      '/api/electronic-invoicing/certification/batches/$batchId',
      headers: _headers(settings),
      queryParameters: await _locators(settings),
      retry: false,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(_errorFromBody(response.body));
    }
  }

  Future<DgiiCertificationCaseModel> _caseAction(
    String path, {
    Duration? timeout,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      path,
      headers: _headers(settings),
      body: await _locators(settings),
      timeout: timeout,
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }
    final item = (decoded['case'] as Map?)?.cast<String, dynamic>() ?? decoded;
    return DgiiCertificationCaseModel.fromMap(item);
  }

  Future<DgiiCertificationBatchActionResult> _batchAction(
    String path, {
    Duration? timeout,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final response = await _api(settings).postJson(
      path,
      headers: _headers(settings),
      body: await _locators(settings),
      timeout: timeout,
      retry: false,
      throwOnServerError: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DgiiCertificationException(
        _friendlyMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
          details: _detailsFromDecoded(decoded),
        ),
      );
    }
    return DgiiCertificationBatchActionResult.fromMap(decoded);
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

  Map<String, String> _headers(BusinessSettings settings) {
    final headers = <String, String>{'x-request-id': newElectronicRequestId()};
    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey != null && cloudKey.isNotEmpty) {
      headers['x-cloud-key'] = cloudKey;
    }
    return headers;
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  List<dynamic> _decodeList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) return decoded;
    } catch (_) {}
    return const <dynamic>[];
  }

  String _errorFromBody(String body) {
    final decoded = _decodeMap(body);
    return _friendlyMessage(
      errorCode: decoded['errorCode']?.toString(),
      message: decoded['message']?.toString(),
      details: _detailsFromDecoded(decoded),
    );
  }

  Map<String, dynamic>? _detailsFromDecoded(Map<String, dynamic> decoded) {
    final details = decoded['details'];
    return details is Map ? details.cast<String, dynamic>() : null;
  }

  String _friendlyMessage({
    String? errorCode,
    String? message,
    int? statusCode,
    Map<String, dynamic>? details,
  }) {
    switch ((errorCode ?? '').trim()) {
      case 'DGII_CERTIFICATION_INVALID_FILE':
      case 'DGII_CERTIFICATION_FILE_REQUIRED':
        return 'Seleccione el archivo Excel .xlsx de pruebas DGII';
      case 'DGII_CERTIFICATION_SHEETS_MISSING':
        return 'El Excel debe contener las hojas ECF y RFCE';
      case 'DGII_CERTIFICATION_NO_CASES':
        return 'No se detectaron casos ECF/RFCE en el archivo';
      case 'DGII_CERTIFICATION_RFCE_XML_NOT_MAPPED':
        return 'RFCE XML generation is not fully mapped yet.';
      case 'DGII_CERTIFICATION_XML_REQUIRED_FIELDS_MISSING':
        final missing = details?['missingFields'];
        if (missing is List && missing.isNotEmpty) {
          return 'Faltan campos obligatorios: ${missing.map((item) => item.toString()).join(', ')}';
        }
        final human = details?['humanReadableMessage']?.toString();
        return human?.trim().isNotEmpty == true
            ? human!
            : 'Faltan campos obligatorios para generar XML';
      case 'DGII_CERTIFICATION_XML_NOT_FOUND':
        return 'Este caso aun no tiene XML generado';
      case 'DGII_CERTIFICATION_XML_NOT_WELL_FORMED':
        return 'El XML generado no esta bien formado';
      case 'DGII_CERTIFICATION_XML_NOT_SIGNABLE':
        return 'Este XML todavia no esta listo para firmarse. Corrige los campos requeridos o carga los XSD oficiales DGII.';
      case 'DGII_CERTIFICATION_AUDIT_BLOCKED':
        return message?.trim().isNotEmpty == true
            ? message!
            : 'La auditoría técnica bloqueó la firma o el envío.';
      case 'DGII_CERTIFICATION_SIGNED_XML_NOT_FOUND':
        return 'Este caso aun no tiene XML firmado';
      case 'DGII_CERTIFICATION_SIGNED_XML_FILE_REQUIRED':
      case 'DGII_CERTIFICATION_SIGNED_XML_INVALID_FILE':
        return 'Seleccione el XML firmado por la app DGII';
      case 'DGII_CERTIFICATION_IMPORTED_SIGNED_XML_INVALID':
        return message?.trim().isNotEmpty == true
            ? message!
            : 'El XML firmado importado no es valido para este caso';
      case 'DGII_CERTIFICATION_TRACK_ID_ALREADY_EXISTS':
        return 'Este caso ya fue enviado. Limpia/reinicia el XML antes de importar otra firma.';
      case 'DGII_CERTIFICATION_TRACK_ID_NOT_FOUND':
        return 'Este caso aun no tiene TrackId';
      case 'DGII_CERTIFICATION_RFCE_RECEPTION_FC_URL_MISSING':
        return 'RFCE requiere configurar el endpoint RecepcionFC';
      case 'DGII_CERTIFICATION_SUBMISSION_DISABLED':
        return 'El envio DGII de certificacion esta deshabilitado en esta fase';
      case 'DGII_CERTIFICATION_PREFLIGHT_BLOCKED':
        final blockers = details?['blockers'];
        if (blockers is List && blockers.isNotEmpty) {
          return 'La verificacion previa no permite enviar a DGII: ${blockers.map((item) => item.toString()).join(', ')}';
        }
        return 'La verificacion previa no permite enviar a DGII';
      case 'POS_OVERRIDE_KEY_REQUIRED':
      case 'POS_OVERRIDE_KEY_INVALID':
        return 'La llave de conexion del POS no fue aceptada por el backend';
    }
    if (statusCode == 401 || statusCode == 403) {
      return 'La llave de conexion del POS no fue aceptada por el backend';
    }
    final normalized = (message ?? '').trim();
    return normalized.isNotEmpty
        ? normalized
        : 'No se pudo completar la operacion de certificacion DGII';
  }
}
