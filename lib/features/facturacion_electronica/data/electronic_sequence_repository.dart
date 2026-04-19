import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'models/electronic_sequence_model.dart';

class ElectronicSequenceException implements Exception {
  const ElectronicSequenceException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

@visibleForTesting
String friendlyElectronicSequenceErrorMessage({
  String? errorCode,
  String? message,
  int? statusCode,
}) {
  switch ((errorCode ?? '').trim()) {
    case 'ELECTRONIC_SEQUENCE_COMPANY_REQUIRED':
      return 'No se pudo identificar la empresa';
    case 'SEQUENCE_LIMIT_INVALID':
      return 'El límite autorizado no es válido';
    case 'SEQUENCE_RANGE_INVALID':
    case 'SEQUENCE_CURRENT_OUT_OF_RANGE':
      return 'Revise el rango autorizado de la secuencia';
    case 'SEQUENCE_ALREADY_USED_LOCKED':
      return 'La secuencia ya fue usada y no se puede cambiar libremente';
    case 'SEQUENCE_PREFIX_INVALID':
      return 'El prefijo no corresponde al tipo de comprobante';
  }

  if (statusCode == 401) {
    return 'No se pudo validar la conexión';
  }

  final normalized = (message ?? '').toLowerCase();
  if (normalized.contains('empresa')) {
    return 'No se pudo identificar la empresa';
  }
  return 'No se pudo crear la secuencia';
}

class ElectronicSequenceRepository {
  ElectronicSequenceRepository({ApiClient? apiClient}) : _apiClient = apiClient;

  final ApiClient? _apiClient;

  static const List<String> _defaultTypes = ['31', '32', '34'];

  Future<List<ElectronicSequenceModel>> listLocal() async {
    final db = await AppDb.database;
    final companyId = await SessionManager.companyId() ?? 0;
    final rows = await db.query(
      DbTables.electronicSequences,
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'document_type_code ASC',
    );

    final mapped = {
      for (final row in rows)
        (row['document_type_code'] as String? ?? '').trim():
            ElectronicSequenceModel.fromMap(row),
    };

    return _defaultTypes
        .map(
          (documentTypeCode) =>
              mapped[documentTypeCode] ??
              ElectronicSequenceModel.defaults(documentTypeCode),
        )
        .toList(growable: false);
  }

  Future<ElectronicSequenceModel> saveLocal(
    ElectronicSequenceModel sequence,
  ) async {
    final db = await AppDb.database;
    final companyId = await SessionManager.companyId() ?? sequence.companyId;
    final payload = sequence.copyWith(
      companyId: companyId,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final existing = await db.query(
      DbTables.electronicSequences,
      where: 'company_id = ? AND branch_id = ? AND document_type_code = ?',
      whereArgs: [companyId, payload.branchId, payload.documentTypeCode],
      limit: 1,
    );
    if (existing.isEmpty) {
      final id = await db.insert(DbTables.electronicSequences, payload.toMap());
      return payload.copyWith(id: id);
    }

    final id = existing.first['id'] as int?;
    await db.update(
      DbTables.electronicSequences,
      payload.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    return payload.copyWith(id: id);
  }

  Future<ElectronicSequenceModel> createSequence({
    required String documentTypeCode,
    required String prefix,
    required int startNumber,
    required int currentNumber,
    required int endNumber,
    required String status,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl = CloudSyncService.instance.debugResolveCloudBaseUrl(
      settings,
    );
    final api = _apiClient ?? ApiClient(baseUrl: baseUrl);
    final headers = <String, String>{};

    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey != null && cloudKey.isNotEmpty) {
      headers['x-cloud-key'] = cloudKey;
    }

    final companyId = await SessionManager.companyId();
    final locators = buildElectronicCompanyLocators(
      sessionCompanyId: companyId,
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );
    final response = await api.postJson(
      '/api/electronic-invoicing/sequences',
      headers: headers,
      body: {
        'branchId': 0,
        'documentTypeCode': documentTypeCode,
        'prefix': prefix,
        'startNumber': startNumber,
        'currentNumber': currentNumber,
        'endNumber': endNumber,
        'status': status,
        ...locators,
      },
      retry: false,
    );

    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ElectronicSequenceException(
        friendlyElectronicSequenceErrorMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }

    final model = ElectronicSequenceModel(
      id: decoded['id'] as int?,
      companyId: (decoded['companyId'] as num?)?.toInt() ?? (companyId ?? 0),
      branchId: (decoded['branchId'] as int?) ?? 0,
      documentTypeCode:
          decoded['documentTypeCode']?.toString().trim() ?? documentTypeCode,
      prefix: decoded['prefix']?.toString().trim() ?? prefix,
      startNumber: (decoded['startNumber'] as num?)?.toInt() ?? startNumber,
      currentNumber:
          (decoded['currentNumber'] as num?)?.toInt() ?? currentNumber,
      endNumber: (decoded['endNumber'] as num?)?.toInt() ?? endNumber,
      status: decoded['status']?.toString().trim() ?? status,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    return saveLocal(model);
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
}
