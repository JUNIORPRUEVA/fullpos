import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'electronic_invoicing_diagnostics_repository.dart';
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
    case 'SEQUENCE_END_NUMBER_REQUIRED':
      return 'Debe indicar el límite final de la secuencia.';
    case 'SEQUENCE_RANGE_INVALID':
    case 'SEQUENCE_CURRENT_OUT_OF_RANGE':
      return 'Revise el rango autorizado de la secuencia';
    case 'SEQUENCE_ALREADY_USED_LOCKED':
      return 'La secuencia ya fue usada y no se puede cambiar libremente';
    case 'SEQUENCE_PREFIX_INVALID':
      return 'El prefijo no corresponde al tipo de comprobante';
    case 'ELECTRONIC_SEQUENCE_STORAGE_MIGRATION_REQUIRED':
      return 'El backend debe actualizarse para aceptar rangos DGII de 10 dígitos';
  }

  if (statusCode == 401) {
    return 'La llave de conexión del POS no fue aceptada por el backend';
  }

  final normalized = (message ?? '').toLowerCase();
  if (normalized.contains('empresa')) {
    return 'No se pudo identificar la empresa';
  }
  if (normalized.contains('null constraint violation') &&
      normalized.contains('endnumber')) {
    return 'El backend debe aplicar la migración de secuencias: existe una columna legacy endNumber obligatoria.';
  }
  if (normalized.contains('endnumber') && normalized.contains('null')) {
    return 'El backend debe aplicar la migración de secuencias: existe una columna legacy endNumber obligatoria.';
  }
  if (normalized.contains('10 dígitos') ||
      normalized.contains('10 digitos') ||
      normalized.contains('p2022') ||
      normalized.contains('column does not exist') ||
      normalized.contains('schema mismatch') ||
      normalized.contains('no coincide con prisma') ||
      normalized.contains('migracion') ||
      normalized.contains('migración')) {
    return 'El backend debe actualizarse para aceptar rangos DGII de 10 dígitos';
  }
  if ((statusCode ?? 0) >= 500 &&
      (message ?? '').trim().isNotEmpty &&
      normalized != 'unexpected error') {
    return message!.trim();
  }
  if ((statusCode ?? 0) >= 500) {
    return 'El backend no pudo guardar la secuencia. Aplique las migraciones del backend y reinicie el servicio.';
  }
  return 'No se pudo crear la secuencia';
}

class ElectronicSequenceRepository {
  ElectronicSequenceRepository({ApiClient? apiClient}) : _apiClient = apiClient;

  final ApiClient? _apiClient;

  static const List<String> _defaultTypes = ['31', '32', '34'];

  Map<String, Object?> _localPersistenceMap(ElectronicSequenceModel sequence) =>
      {
        'company_id': sequence.companyId,
        'branch_id': sequence.branchId,
        'document_type_code': sequence.documentTypeCode,
        'prefix': sequence.prefix,
        'start_number': sequence.startNumber,
        'current_number': sequence.currentNumber,
        'end_number': sequence.endNumber,
        'status': sequence.status,
        'updated_at_ms': sequence.updatedAtMs,
      };

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
    final localMap = _localPersistenceMap(payload);
    if (existing.isEmpty) {
      final id = await db.insert(DbTables.electronicSequences, localMap);
      return payload.copyWith(id: id);
    }

    final id = existing.first['id'] as int?;
    await db.update(
      DbTables.electronicSequences,
      localMap,
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
    headers['x-request-id'] = newElectronicRequestId();

    final companyId = await SessionManager.companyId();
    final locators = buildElectronicCompanyLocators(
      sessionCompanyId: companyId,
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );
    debugPrint(
      '[electronic-sequence] save request documentTypeCode=$documentTypeCode '
      'prefix=$prefix startNumber=$startNumber currentNumber=$currentNumber '
      'endNumber=$endNumber maxNumber=$endNumber '
      'companyRnc=${settings.rnc} companyCloudId=${settings.cloudCompanyId}',
    );
    late final dynamic response;
    try {
      response = await api.postJson(
        '/api/electronic-invoicing/sequences',
        headers: headers,
        body: {
          'branchId': 0,
          'documentTypeCode': documentTypeCode,
          'prefix': prefix,
          'startNumber': startNumber,
          'currentNumber': currentNumber,
          'endNumber': endNumber,
          'maxNumber': endNumber,
          'status': status,
          ...locators,
        },
        retry: false,
      );
    } on ApiException catch (error) {
      debugPrint(
        '[electronic-sequence] save api exception status=${error.statusCode} message=${error.message}',
      );
      throw ElectronicSequenceException(
        friendlyElectronicSequenceErrorMessage(
          message: error.message,
          statusCode: error.statusCode,
        ),
      );
    }

    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[electronic-sequence] save failed status=${response.statusCode} '
        'errorCode=${decoded['errorCode']} message=${decoded['message']} '
        'details=${sanitizeElectronicLogValue(decoded['details'])}',
      );
      throw ElectronicSequenceException(
        friendlyElectronicSequenceErrorMessage(
          errorCode: decoded['errorCode']?.toString(),
          message: decoded['message']?.toString(),
          statusCode: response.statusCode,
        ),
      );
    }

    final sequenceJson = decoded['sequence'] is Map<String, dynamic>
        ? decoded['sequence'] as Map<String, dynamic>
        : decoded;

    final model = ElectronicSequenceModel(
      id: sequenceJson['id'] as int?,
      companyId:
          (sequenceJson['companyId'] as num?)?.toInt() ?? (companyId ?? 0),
      branchId: (sequenceJson['branchId'] as int?) ?? 0,
      documentTypeCode:
          sequenceJson['documentTypeCode']?.toString().trim() ??
          documentTypeCode,
      prefix: sequenceJson['prefix']?.toString().trim() ?? prefix,
      startNumber:
          (sequenceJson['startNumber'] as num?)?.toInt() ?? startNumber,
      currentNumber:
          (sequenceJson['currentNumber'] as num?)?.toInt() ?? currentNumber,
      endNumber: (sequenceJson['endNumber'] as num?)?.toInt() ?? endNumber,
      status: sequenceJson['status']?.toString().trim() ?? status,
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
