import 'dart:convert';
import 'dart:math';

import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'models/electronic_invoicing_config_model.dart';

String maskElectronicSecret(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'No configurada';
  if (trimmed.length <= 8) {
    return '${trimmed.substring(0, min(4, trimmed.length))}...';
  }
  return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
}

String newElectronicRequestId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final suffix = List.generate(
    6,
    (_) => chars[random.nextInt(chars.length)],
  ).join();
  return 'fe-${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

Object? sanitizeElectronicLogValue(Object? value) {
  if (value is Map) {
    return value.map((key, dynamic item) {
      final lower = key.toString().toLowerCase();
      if (lower.contains('authorization') ||
          lower.contains('bearer') ||
          lower.contains('x-cloud-key') ||
          lower.contains('cloudapikey') ||
          lower.contains('apitoken') ||
          lower.contains('dgiiManualToken'.toLowerCase())) {
        return MapEntry(key, maskElectronicSecret(item?.toString()));
      }
      if (lower.contains('password')) {
        return MapEntry(key, '***');
      }
      return MapEntry(key, sanitizeElectronicLogValue(item));
    });
  }
  if (value is List) {
    return value.map(sanitizeElectronicLogValue).toList(growable: false);
  }
  return value;
}

String classifyElectronicDiagnosticError({
  String? errorCode,
  String? message,
  int? statusCode,
}) {
  final code = (errorCode ?? '').trim().toUpperCase();
  final text = (message ?? '').trim().toLowerCase();
  if (statusCode == 0 ||
      text.contains('conectar') ||
      text.contains('red') ||
      text.contains('tiempo de espera')) {
    return 'Error de conexión con el backend';
  }
  if (statusCode == 401 ||
      statusCode == 403 ||
      code.contains('OVERRIDE_KEY') ||
      code.contains('POS_')) {
    return 'La llave de conexión del POS no fue aceptada por el backend';
  }
  if (code.contains('DGII') ||
      code.contains('SEED') ||
      code.contains('TOKEN') ||
      code.contains('AUTH_ENDPOINT')) {
    return 'El backend respondió, pero DGII no pudo generar/validar el token';
  }
  if (code.contains('CERTIFICATE') || text.contains('certificado')) {
    return 'El certificado digital no está listo o no pudo ser leído';
  }
  if (code.contains('SEQUENCE') || text.contains('secuencia')) {
    return 'La secuencia del comprobante no está configurada o está agotada';
  }
  if (code.contains('SALE_SYNC') || code == 'SALE_NOT_FOUND') {
    return 'La venta no se sincronizó con la nube antes de generar el e-CF';
  }
  if (code == 'SALE_ITEMS_REQUIRED') {
    return 'La venta no tiene artículos para generar el e-CF';
  }
  if (code == 'CUSTOMER_RNC_REQUIRED_FOR_E31') {
    return 'La factura E31 requiere RNC válido del cliente';
  }
  if (code == 'XML_GENERATION_FAILED') {
    return 'El XML no pudo generarse por datos incompletos';
  }
  if (code == 'XML_SIGN_FAILED') {
    return 'El XML no pudo firmarse con el certificado activo';
  }
  if (code.contains('REJECT') || text.contains('rechaz')) {
    return 'DGII recibió el documento pero lo rechazó';
  }
  return message?.trim().isNotEmpty == true
      ? message!.trim()
      : 'No se pudo completar la operación';
}

class ElectronicBackendDiagnosticResult {
  const ElectronicBackendDiagnosticResult({
    required this.ok,
    required this.backendUrl,
    required this.requestId,
    required this.statusCode,
    required this.errorCode,
    required this.message,
    required this.classification,
    required this.cloudKeyExists,
    required this.maskedCloudKey,
    required this.backendAcceptedKey,
    required this.locators,
    required this.response,
    required this.testedAt,
  });

  final bool ok;
  final String backendUrl;
  final String requestId;
  final int? statusCode;
  final String? errorCode;
  final String? message;
  final String classification;
  final bool cloudKeyExists;
  final String maskedCloudKey;
  final bool? backendAcceptedKey;
  final Map<String, String> locators;
  final Map<String, dynamic> response;
  final DateTime testedAt;

  Map<String, String?> get companyResolved {
    final company = response['company'];
    if (company is Map) {
      return <String, String?>{
        'companyId': company['companyId']?.toString(),
        'companyCloudId': company['companyCloudId']?.toString(),
        'companyName': company['companyName']?.toString(),
        'rnc': company['rnc']?.toString(),
      };
    }
    return const <String, String?>{};
  }
}

class ElectronicDgiiAuthDiagnosticResult {
  const ElectronicDgiiAuthDiagnosticResult({
    required this.ok,
    required this.backendUrl,
    required this.requestId,
    required this.statusCode,
    required this.errorCode,
    required this.message,
    required this.classification,
    required this.locators,
    required this.response,
    required this.testedAt,
  });

  final bool ok;
  final String backendUrl;
  final String requestId;
  final int? statusCode;
  final String? errorCode;
  final String? message;
  final String classification;
  final Map<String, String> locators;
  final Map<String, dynamic> response;
  final DateTime testedAt;

  Map<String, dynamic> get dgiiAuth =>
      (response['dgiiAuth'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  Map<String, dynamic>? get companyResolved =>
      (response['companyResolved'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic> get certificate =>
      (response['certificate'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  Map<String, dynamic> get config =>
      (response['config'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  Map<String, dynamic> get signer =>
      (response['signer'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  Map<String, dynamic> get signerContext {
    final auth = dgiiAuth;
    return (auth['signerContext'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
  }
}

class ElectronicInvoicingDiagnosticsRepository {
  ElectronicInvoicingDiagnosticsRepository({ApiClient? apiClient})
    : _apiClient = apiClient;

  final ApiClient? _apiClient;

  Future<ElectronicBackendDiagnosticResult> testBackend({
    String? requestId,
  }) async {
    final context = await _context(requestId: requestId);
    try {
      final response = await context.api.get(
        '/api/electronic-invoicing/config/by-rnc',
        headers: context.headers,
        queryParameters: <String, String>{...context.locators, 'branchId': '0'},
        retry: false,
      );
      final decoded = _decodeMap(response.body);
      final errorCode = decoded['errorCode']?.toString();
      final message = decoded['message']?.toString();
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return ElectronicBackendDiagnosticResult(
        ok: ok,
        backendUrl: context.api.baseUrl,
        requestId:
            response.headers['x-request-id'] ??
            response.headers['x-correlation-id'] ??
            context.requestId,
        statusCode: response.statusCode,
        errorCode: errorCode,
        message: message,
        classification: ok
            ? 'Backend respondió correctamente'
            : classifyElectronicDiagnosticError(
                errorCode: errorCode,
                message: message,
                statusCode: response.statusCode,
              ),
        cloudKeyExists: context.cloudKeyExists,
        maskedCloudKey: context.maskedCloudKey,
        backendAcceptedKey: ok
            ? true
            : (response.statusCode == 401 || response.statusCode == 403
                  ? false
                  : null),
        locators: context.locators,
        response: decoded,
        testedAt: DateTime.now(),
      );
    } on ApiException catch (error) {
      return ElectronicBackendDiagnosticResult(
        ok: false,
        backendUrl: context.api.baseUrl,
        requestId: context.requestId,
        statusCode: error.statusCode,
        errorCode: null,
        message: error.message,
        classification: classifyElectronicDiagnosticError(
          message: error.message,
          statusCode: error.statusCode ?? 0,
        ),
        cloudKeyExists: context.cloudKeyExists,
        maskedCloudKey: context.maskedCloudKey,
        backendAcceptedKey: null,
        locators: context.locators,
        response: const <String, dynamic>{},
        testedAt: DateTime.now(),
      );
    }
  }

  Future<ElectronicDgiiAuthDiagnosticResult> testDgiiAuth({
    required String environment,
    String? requestId,
  }) async {
    final context = await _context(requestId: requestId);
    final body = <String, dynamic>{
      ...context.locators,
      'environment': _backendEnvironment(environment),
      'forceRefresh': true,
    };
    try {
      final response = await context.api.postJson(
        '/api/electronic-invoicing/debug/auth/by-rnc',
        headers: context.headers,
        body: body,
        retry: false,
      );
      final decoded = _decodeMap(response.body);
      final dgiiAuth =
          (decoded['dgiiAuth'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final errors = decoded['errors'];
      final firstError =
          errors is List && errors.isNotEmpty && errors.first is Map
          ? Map<String, dynamic>.from(errors.first as Map)
          : const <String, dynamic>{};
      final errorCode =
          (dgiiAuth['safeErrorCode'] ??
                  firstError['code'] ??
                  decoded['errorCode'])
              ?.toString();
      final message =
          (dgiiAuth['safeErrorMessage'] ??
                  firstError['message'] ??
                  decoded['message'])
              ?.toString();
      final ok =
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          decoded['ok'] == true;
      return ElectronicDgiiAuthDiagnosticResult(
        ok: ok,
        backendUrl: context.api.baseUrl,
        requestId:
            response.headers['x-request-id'] ??
            response.headers['x-correlation-id'] ??
            context.requestId,
        statusCode: response.statusCode,
        errorCode: errorCode,
        message: message,
        classification: ok
            ? 'Token DGII probado correctamente'
            : classifyElectronicDiagnosticError(
                errorCode: errorCode,
                message: message,
                statusCode: response.statusCode,
              ),
        locators: context.locators,
        response: decoded,
        testedAt: DateTime.now(),
      );
    } on ApiException catch (error) {
      return ElectronicDgiiAuthDiagnosticResult(
        ok: false,
        backendUrl: context.api.baseUrl,
        requestId: context.requestId,
        statusCode: error.statusCode,
        errorCode: null,
        message: error.message,
        classification: classifyElectronicDiagnosticError(
          message: error.message,
          statusCode: error.statusCode ?? 0,
        ),
        locators: context.locators,
        response: const <String, dynamic>{},
        testedAt: DateTime.now(),
      );
    }
  }

  Future<_DiagnosticRequestContext> _context({String? requestId}) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final api =
        _apiClient ??
        ApiClient(
          baseUrl: CloudSyncService.instance.debugResolveCloudBaseUrl(settings),
        );
    final sessionCompanyId = await SessionManager.companyId();
    final locators = buildElectronicCompanyLocators(
      sessionCompanyId: sessionCompanyId,
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );
    final id = requestId ?? newElectronicRequestId();
    final cloudKey = settings.cloudApiKey?.trim();
    final headers = <String, String>{'x-request-id': id};
    if (cloudKey != null && cloudKey.isNotEmpty) {
      headers['x-cloud-key'] = cloudKey;
    }
    return _DiagnosticRequestContext(
      api: api,
      requestId: id,
      headers: headers,
      locators: locators,
      cloudKeyExists: cloudKey != null && cloudKey.isNotEmpty,
      maskedCloudKey: maskElectronicSecret(cloudKey),
    );
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

  String _backendEnvironment(String uiValue) {
    return uiValue.trim().toLowerCase() == 'produccion'
        ? 'production'
        : 'precertification';
  }
}

class _DiagnosticRequestContext {
  const _DiagnosticRequestContext({
    required this.api,
    required this.requestId,
    required this.headers,
    required this.locators,
    required this.cloudKeyExists,
    required this.maskedCloudKey,
  });

  final ApiClient api;
  final String requestId;
  final Map<String, String> headers;
  final Map<String, String> locators;
  final bool cloudKeyExists;
  final String maskedCloudKey;
}

extension DiagnosticSummary on ElectronicInvoicingResolvedConfig {
  String get diagnosticDataSourceLabel => readiness.backendValidated
      ? 'Datos validados por backend'
      : 'Fallback con caché local';
}
