import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'electronic_company_repository.dart';

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
  const ElectronicCertificateUploadException(this.userMessage);

  final String userMessage;

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
    case 'ELECTRONIC_CERTIFICATE_PASSWORD_INVALID':
      return 'La contraseña no es correcta';
    case 'ELECTRONIC_CERTIFICATE_INVALID_FILE':
    case 'ELECTRONIC_CERTIFICATE_FILE_REQUIRED':
      return 'El certificado no es válido';
    case 'ELECTRONIC_CERTIFICATE_COMPANY_REQUIRED':
      return 'No se pudo identificar la empresa';
  }

  final normalizedMessage = (message ?? '').toLowerCase();
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
    }

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
        throw ElectronicCertificateUploadException(
          friendlyCertificateUploadErrorMessage(
            errorCode: decoded['errorCode']?.toString(),
            message: decoded['message']?.toString(),
            statusCode: response.statusCode,
          ),
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
    } catch (_) {
      throw const ElectronicCertificateUploadException(
        'No se pudo cargar el certificado',
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
}
