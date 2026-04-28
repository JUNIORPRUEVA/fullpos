import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'electronic_company_repository.dart';
import 'electronic_invoicing_diagnostics_repository.dart';

class ElectronicCertificateUploadResult {
  const ElectronicCertificateUploadResult({
    required this.alias,
    required this.serial,
    required this.validFrom,
    required this.validTo,
    required this.isExpired,
    this.message,
  });

  final String alias;
  final String serial;
  final DateTime validFrom;
  final DateTime validTo;
  final bool isExpired;
  final String? message;
}

class ElectronicCertificateUploadException implements Exception {
  const ElectronicCertificateUploadException(
    this.userMessage, {
    this.errorCode,
    this.statusCode,
    this.backendMessage,
    this.details,
    this.requestId,
  });

  final String userMessage;
  final String? errorCode;
  final int? statusCode;
  final String? backendMessage;
  final Map<String, dynamic>? details;
  final String? requestId;

  @override
  String toString() => userMessage;
}

@visibleForTesting
String friendlyCertificateUploadErrorMessage({
  String? errorCode,
  String? message,
  int? statusCode,
}) {
  switch ((errorCode ?? '').trim()) {
    case 'POS_OVERRIDE_KEY_REQUIRED':
      return 'El backend requiere configurar la llave de conexión del POS';
    case 'POS_OVERRIDE_KEY_INVALID':
      return 'La llave de conexión del POS no coincide con el backend';
    case 'ELECTRONIC_CERTIFICATE_PASSWORD_INVALID':
    case 'CERTIFICATE_INVALID_PASSWORD':
      return 'La contraseña no es correcta';
    case 'ELECTRONIC_CERTIFICATE_INVALID_FILE':
    case 'ELECTRONIC_CERTIFICATE_FILE_REQUIRED':
    case 'CERTIFICATE_INVALID':
      return 'El certificado no es válido';
    case 'CERTIFICATE_EXPIRED':
      return 'El certificado está vencido';
    case 'CERTIFICATE_RNC_MISMATCH':
      return 'El RNC del certificado no coincide con la empresa';
    case 'ELECTRONIC_CERTIFICATE_COMPANY_REQUIRED':
      return 'No se pudo identificar la empresa';
    case 'DGII_SEED_VALIDATE_BAD_REQUEST':
      return 'DGII rechazó la firma del certificado. Verifique el certificado, contraseña y que el backend esté actualizado';
  }

  final normalizedMessage = (message ?? '').toLowerCase();
  if (normalizedMessage.contains('firma del certificado inválida') ||
      normalizedMessage.contains('firma del certificado invalida')) {
    return 'DGII rechazó la firma del certificado. Verifique el certificado, contraseña y que el backend esté actualizado';
  }
  if (normalizedMessage.contains('vencido')) {
    return 'El certificado está vencido';
  }
  if (statusCode == 401) {
    return 'No se pudo validar la conexión';
  }
  return 'No se pudo cargar el certificado';
}

class ElectronicCertificateRepository {
  ElectronicCertificateRepository({ApiClient? apiClient})
    : _apiClient = apiClient;

  final ApiClient? _apiClient;

  Future<ElectronicCertificateUploadResult> uploadCertificate({
    required String filePath,
    required String alias,
    required String password,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl = CloudSyncService.instance.debugResolveCloudBaseUrl(
      settings,
    );
    final api = _apiClient ?? ApiClient(baseUrl: baseUrl);
    final uri = api.uri('/api/electronic-invoicing/certificates');
    final request = http.MultipartRequest('POST', uri);

    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey != null && cloudKey.isNotEmpty) {
      request.headers['x-cloud-key'] = cloudKey;
      request.headers['x-override-key'] = cloudKey;
      request.headers['Authorization'] = 'Bearer $cloudKey';
    }
    final requestId = newElectronicRequestId();
    request.headers['x-request-id'] = requestId;

    final companyId = await SessionManager.companyId();
    final locators = buildElectronicCompanyLocators(
      sessionCompanyId: companyId,
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );
    final username = await SessionManager.username();

    request.fields['alias'] = alias.trim();
    request.fields['password'] = password;
    for (final entry in locators.entries) {
      request.fields[entry.key] = entry.value;
    }
    if (username != null && username.trim().isNotEmpty) {
      request.fields['uploadedBy'] = username.trim();
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType('application', 'x-pkcs12'),
      ),
    );

    try {
      final streamed = await api.sendMultipart(
        request,
        timeout: const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      final decoded = _decodeBody(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorCode = decoded['errorCode']?.toString();
        final message = decoded['message']?.toString();
        final details = _normalizeDetails(decoded['details']);
        await _logUploadFailure(
          requestId: requestId,
          uri: uri,
          statusCode: response.statusCode,
          errorCode: errorCode,
          message: message,
          details: details,
        );
        throw ElectronicCertificateUploadException(
          friendlyCertificateUploadErrorMessage(
            errorCode: errorCode,
            message: message,
            statusCode: response.statusCode,
          ),
          errorCode: errorCode,
          statusCode: response.statusCode,
          backendMessage: message,
          details: details,
          requestId: requestId,
        );
      }

      final validFrom = DateTime.parse(decoded['validFrom'] as String);
      final validTo = DateTime.parse(decoded['validTo'] as String);
      final warning = decoded['warning']?.toString().trim();
      final result = ElectronicCertificateUploadResult(
        alias: decoded['alias']?.toString().trim() ?? alias.trim(),
        serial: decoded['serial']?.toString().trim() ?? '',
        validFrom: validFrom,
        validTo: validTo,
        isExpired:
            (warning != null && warning.isNotEmpty) ||
            validTo.isBefore(DateTime.now()),
        message: warning,
      );

      final company = await ElectronicCompanyRepository.getOrCreate();
      await ElectronicCompanyRepository.save(
        company.copyWith(
          certificateName: result.alias,
          certificateValidFromMs: result.validFrom.millisecondsSinceEpoch,
          certificateValidToMs: result.validTo.millisecondsSinceEpoch,
          certificateStatus: result.isExpired ? 'expired' : 'active',
        ),
      );

      return result;
    } on ElectronicCertificateUploadException {
      rethrow;
    } on ApiException catch (error) {
      await _logUploadFailure(
        requestId: requestId,
        uri: uri,
        statusCode: error.statusCode,
        errorCode: null,
        message: error.message,
        details: const <String, dynamic>{'source': 'api_client'},
      );
      throw ElectronicCertificateUploadException(
        friendlyCertificateUploadErrorMessage(
          message: error.message,
          statusCode: error.statusCode,
        ),
        statusCode: error.statusCode,
        backendMessage: error.message,
        requestId: requestId,
      );
    } catch (error) {
      await _logUploadFailure(
        requestId: requestId,
        uri: uri,
        statusCode: null,
        errorCode: null,
        message: error.toString(),
        details: const <String, dynamic>{'source': 'unexpected'},
      );
      throw ElectronicCertificateUploadException(
        'No se pudo cargar el certificado',
        backendMessage: error.toString(),
        requestId: requestId,
      );
    }
  }

  Map<String, dynamic> _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _normalizeDetails(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  Future<void> _logUploadFailure({
    required String requestId,
    required Uri uri,
    required int? statusCode,
    required String? errorCode,
    required String? message,
    required Map<String, dynamic>? details,
  }) async {
    await AppLogger.instance.logWarn(
      jsonEncode({
        'event': 'electronic_certificate_upload_failed',
        'requestId': requestId,
        'path': uri.path,
        'statusCode': statusCode,
        'errorCode': errorCode,
        'message': message,
        'details': _sanitizeDetails(details),
      }),
      module: 'electronic_invoicing',
    );
  }

  Map<String, dynamic>? _sanitizeDetails(Map<String, dynamic>? details) {
    if (details == null) return null;
    const blockedKeys = {
      'password',
      'token',
      'authorization',
      'certificate',
      'certificateBuffer',
      'privateKey',
      'signedXml',
      'xml',
    };
    return details.map((key, value) {
      if (blockedKeys.contains(key.toLowerCase())) {
        return MapEntry(key, '<redacted>');
      }
      return MapEntry(key, value);
    });
  }
}
