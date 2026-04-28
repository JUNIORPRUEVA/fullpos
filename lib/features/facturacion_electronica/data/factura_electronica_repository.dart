import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../sales/data/sales_model.dart' as sales;
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'electronic_invoicing_diagnostics_repository.dart';
import 'models/factura_electronica_model.dart';

String _mapRemoteInvoiceStatus(Map<dynamic, dynamic> item) {
  final dgiiStatus = (item['dgiiStatus']?.toString() ?? '')
      .trim()
      .toUpperCase();
  switch (dgiiStatus) {
    case 'ACCEPTED':
    case 'ACCEPTED_CONDITIONAL':
      return FacturaElectronicaModel.statusAccepted;
    case 'REJECTED':
      return FacturaElectronicaModel.statusRejected;
    case 'ERROR':
      return FacturaElectronicaModel.statusSendError;
    case 'RECEIVED':
    case 'IN_PROCESS':
    case 'SUBMITTED':
    case 'PENDING':
      return FacturaElectronicaModel.statusPending;
  }

  final internalStatus = (item['internalStatus']?.toString() ?? '')
      .trim()
      .toUpperCase();
  if (internalStatus == 'SUBMISSION_PENDING' ||
      internalStatus == 'SUBMITTED' ||
      internalStatus == 'SIGNED' ||
      internalStatus == 'GENERATED') {
    return FacturaElectronicaModel.statusPending;
  }
  if (internalStatus == 'ACCEPTED' ||
      internalStatus == 'ACCEPTED_CONDITIONAL') {
    return FacturaElectronicaModel.statusAccepted;
  }
  if (internalStatus == 'REJECTED') {
    return FacturaElectronicaModel.statusRejected;
  }
  if (internalStatus == 'ERROR' ||
      internalStatus == 'AUTH_ERROR' ||
      internalStatus == 'SEND_ERROR') {
    return FacturaElectronicaModel.statusSendError;
  }
  return FacturaElectronicaModel.statusLocal;
}

bool _isBackendPersistedDocument(FacturaElectronicaModel document) {
  final ecf = (document.ecf ?? '').trim();
  final trackId = (document.dgiiTrackId ?? '').trim();
  final internalStatus = (document.estadoInterno ?? '').trim().toUpperCase();

  if (ecf.isEmpty && trackId.isEmpty) {
    return false;
  }

  return internalStatus != 'LOCAL_ONLY' &&
      internalStatus != 'CACHE_ONLY' &&
      internalStatus != 'CONFIG_PENDING';
}

List<FacturaElectronicaModel> _cachedBackendDocuments(
  List<FacturaElectronicaModel> documents, {
  required int limit,
}) {
  final filtered =
      documents.where(_isBackendPersistedDocument).toList(growable: false)
        ..sort((left, right) => right.createdAtMs.compareTo(left.createdAtMs));

  if (filtered.length <= limit) {
    return filtered;
  }
  return filtered.take(limit).toList(growable: false);
}

String _resolvedInvoiceKey(FacturaElectronicaModel document) {
  if (document.saleId > 0) return 'sale:${document.saleId}';
  final ecf = (document.ecf ?? '').trim();
  if (ecf.isNotEmpty) return 'ecf:$ecf';
  return 'local:${document.localCode.trim()}';
}

List<FacturaElectronicaModel> _mergeResolvedDocuments({
  required List<FacturaElectronicaModel> remote,
  required List<FacturaElectronicaModel> local,
  required int limit,
}) {
  final merged = <String, FacturaElectronicaModel>{
    for (final document in _cachedBackendDocuments(local, limit: limit))
      _resolvedInvoiceKey(document): document,
  };

  for (final document in remote) {
    merged[_resolvedInvoiceKey(document)] = document;
  }

  final values = merged.values.toList(growable: false)
    ..sort((left, right) => right.createdAtMs.compareTo(left.createdAtMs));
  if (values.length <= limit) {
    return values;
  }
  return values.take(limit).toList(growable: false);
}

class FacturaElectronicaRepository {
  FacturaElectronicaRepository._();

  static String _backendTagFromHeaders(Map<String, String> headers) {
    final instanceId = (headers['x-fullpos-instance'] ?? '').trim();
    final version = (headers['x-fullpos-version'] ?? '').trim();
    final commit = (headers['x-fullpos-commit'] ?? '').trim();

    final parts = <String>[];
    if (instanceId.isNotEmpty) parts.add('instance=$instanceId');
    if (version.isNotEmpty) parts.add('version=$version');
    if (commit.isNotEmpty) parts.add('commit=$commit');

    if (parts.isEmpty) return '';
    return ' backend(${parts.join(' ')})';
  }

  static bool _isPendingRemoteDoc(FacturaElectronicaModel document) {
    final status = (document.estadoDgii).trim().toUpperCase();
    return status == FacturaElectronicaModel.statusPending.toUpperCase();
  }

  static Future<FacturaElectronicaModel?> _queryRemoteResultForRecent({
    required ApiClient api,
    required Map<String, String> headers,
    required Map<String, String> locators,
    required FacturaElectronicaModel document,
  }) async {
    final trackId = (document.dgiiTrackId ?? '').trim();
    if (trackId.isEmpty) return null;

    final path =
        '/api/electronic-invoicing/outbound/result/by-rnc/${trackId.trim()}';
    try {
      await AppLogger.instance.logInfo(
        'FE recents dgii result query start trackId=$trackId ecf=${document.ecf ?? ''} localCode=${document.localCode}',
        module: 'electronic_invoicing',
      );
      final response = await api.get(
        path,
        headers: {...headers, 'x-request-id': newElectronicRequestId()},
        queryParameters: <String, String>{...locators, 'branchId': '0'},
        retry: false,
      );
      await AppLogger.instance.logInfo(
        'FE recents dgii result query done trackId=$trackId status=${response.statusCode}${_backendTagFromHeaders(response.headers)} response=${response.body}',
        module: 'electronic_invoicing',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final invoice = decoded['invoice'];
        if (invoice is Map) {
          final item = Map<String, dynamic>.from(invoice);
          return FacturaElectronicaModel(
            id: item['id'] as int?,
            saleId: (item['saleId'] as num?)?.toInt() ?? document.saleId,
            localCode:
                item['saleLocalCode']?.toString().trim().isNotEmpty == true
                ? item['saleLocalCode'].toString().trim()
                : document.localCode,
            ecf: item['ecf']?.toString().trim().isNotEmpty == true
                ? item['ecf'].toString().trim()
                : (document.ecf ?? '').trim(),
            tipoDocumento:
                item['documentTypeCode']?.toString().trim().isNotEmpty == true
                ? item['documentTypeCode'].toString().trim()
                : document.tipoDocumento,
            dgiiTrackId:
                item['dgiiTrackId']?.toString().trim().isNotEmpty == true
                ? item['dgiiTrackId'].toString().trim()
                : trackId,
            estadoDgii: _mapRemoteInvoiceStatus(item),
            codigoDgii: item['rejectionCode']?.toString(),
            mensajeDgii:
                item['rejectionMessage']?.toString().trim().isNotEmpty == true
                ? item['rejectionMessage'].toString()
                : item['lastError']?.toString(),
            estadoInterno: item['internalStatus']?.toString(),
            tipoDescriptivo: document.tipoDescriptivo,
            clienteNombre: document.clienteNombre,
            clienteRnc: document.clienteRnc,
            montoTotal: document.montoTotal,
            referenciaDocumento: document.referenciaDocumento,
            ambiente: document.ambiente,
            createdAtMs: document.createdAtMs,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            sentAtMs: document.sentAtMs,
            acknowledgedAtMs: document.acknowledgedAtMs,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<List<FacturaElectronicaModel>> loadRecentResolved({
    int limit = 40,
  }) async {
    final localRecent = await getRecent(limit: limit);
    final cachedRemoteRecent = _cachedBackendDocuments(
      localRecent,
      limit: limit,
    );
    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = buildElectronicCompanyLocators(
      sessionCompanyId: await SessionManager.companyId(),
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );

    if (locators.isEmpty) {
      return cachedRemoteRecent;
    }

    final api = ApiClient(
      baseUrl: CloudSyncService.instance.debugResolveCloudBaseUrl(settings),
    );
    final headers = <String, String>{};
    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey != null && cloudKey.isNotEmpty) {
      headers['x-cloud-key'] = cloudKey;
    }
    headers['x-request-id'] = newElectronicRequestId();

    try {
      final response = await api.get(
        '/api/electronic-invoicing/outbound/by-rnc',
        headers: headers,
        queryParameters: <String, String>{...locators, 'limit': '$limit'},
        retry: false,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cachedRemoteRecent;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return cachedRemoteRecent;
      }

      final docs = decoded
          .whereType<Map>()
          .map(
            (item) => FacturaElectronicaModel(
              id: item['id'] as int?,
              saleId: (item['saleId'] as num?)?.toInt() ?? 0,
              localCode:
                  item['saleLocalCode']?.toString().trim().isNotEmpty == true
                  ? item['saleLocalCode'].toString().trim()
                  : item['documentNumber']?.toString().trim() ?? '',
              ecf: item['documentNumber']?.toString().trim(),
              tipoDocumento:
                  item['documentTypeCode']?.toString().trim() ?? 'venta',
              dgiiTrackId: item['dgiiTrackId']?.toString().trim(),
              estadoDgii: _mapRemoteInvoiceStatus(item),
              codigoDgii: item['rejectionCode']?.toString(),
              mensajeDgii:
                  item['rejectionMessage']?.toString().trim().isNotEmpty == true
                  ? item['rejectionMessage'].toString()
                  : item['lastError']?.toString(),
              ambiente: null,
              montoTotal: (item['totalAmount'] as num?)?.toDouble() ?? 0.0,
              clienteNombre: item['customerName']?.toString(),
              clienteRnc: item['customerRnc']?.toString(),
              tipoDescriptivo: item['documentLabel']?.toString(),
              referenciaDocumento: item['referenceDocument']?.toString(),
              estadoInterno: item['internalStatus']?.toString(),
              createdAtMs:
                  DateTime.tryParse(
                    item['createdAt']?.toString() ?? '',
                  )?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch,
              updatedAtMs:
                  DateTime.tryParse(
                    item['createdAt']?.toString() ?? '',
                  )?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch,
            ),
          )
          .toList(growable: false);

      final rejected = docs
          .where((doc) {
            final status = (doc.estadoDgii).trim().toUpperCase();
            return status ==
                FacturaElectronicaModel.statusRejected.toUpperCase();
          })
          .take(5);
      for (final doc in rejected) {
        final code = (doc.codigoDgii ?? '').trim();
        final message = (doc.mensajeDgii ?? '').trim();
        if (code.isNotEmpty || message.isNotEmpty) {
          await AppLogger.instance.logWarn(
            'FE recents rejected ecf=${doc.ecf ?? ''} localCode=${doc.localCode} code=$code message=$message',
            module: 'electronic_invoicing',
          );
        }
      }

      final pendingWithTrack = docs
          .where(
            (doc) =>
                _isPendingRemoteDoc(doc) &&
                (doc.dgiiTrackId ?? '').trim().isNotEmpty,
          )
          .take(10)
          .toList(growable: false);

      final pendingWithoutTrack = docs
          .where(
            (doc) =>
                _isPendingRemoteDoc(doc) &&
                (doc.dgiiTrackId ?? '').trim().isEmpty,
          )
          .take(10)
          .toList(growable: false);

      if (pendingWithTrack.isNotEmpty) {
        await AppLogger.instance.logInfo(
          'FE recents pending docs detected count=${pendingWithTrack.length}',
          module: 'electronic_invoicing',
        );
      }

      if (pendingWithoutTrack.isNotEmpty) {
        await AppLogger.instance.logWarn(
          'FE recents pending docs missing trackId count=${pendingWithoutTrack.length}',
          module: 'electronic_invoicing',
        );
      }

      final refreshed = <String, FacturaElectronicaModel>{
        for (final doc in docs) _resolvedInvoiceKey(doc): doc,
      };

      for (final pendingDoc in pendingWithTrack) {
        final updated = await _queryRemoteResultForRecent(
          api: api,
          headers: headers,
          locators: locators,
          document: pendingDoc,
        );
        if (updated == null) continue;
        refreshed[_resolvedInvoiceKey(pendingDoc)] = updated;
      }

      final finalDocs = refreshed.values.toList(growable: false);

      for (final doc in finalDocs.where((item) => item.saleId > 0)) {
        await upsert(doc);
      }
      return _mergeResolvedDocuments(
        remote: finalDocs,
        local: cachedRemoteRecent,
        limit: limit,
      );
    } catch (_) {
      return cachedRemoteRecent;
    }
  }

  static Future<FacturaElectronicaModel?> getBySaleId(int saleId) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.facturaElectronica,
      where: 'sale_id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FacturaElectronicaModel.fromMap(rows.first);
  }

  static Future<List<FacturaElectronicaModel>> getRecent({
    int limit = 40,
  }) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.facturaElectronica,
      orderBy: 'created_at_ms DESC',
      limit: limit,
    );
    return rows.map(FacturaElectronicaModel.fromMap).toList();
  }

  static Future<Map<int, FacturaElectronicaModel>> getBySaleIds(
    Iterable<int> saleIds,
  ) async {
    final ids = saleIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) return <int, FacturaElectronicaModel>{};

    final db = await AppDb.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      DbTables.facturaElectronica,
      where: 'sale_id IN ($placeholders)',
      whereArgs: ids,
    );

    return {
      for (final row in rows)
        (row['sale_id'] as int): FacturaElectronicaModel.fromMap(row),
    };
  }

  static Future<Map<String, int>> getStatusSummary() async {
    final db = await AppDb.database;
    final rows = await db.rawQuery('''
      SELECT estado_dgii, COUNT(*) as total
      FROM ${DbTables.facturaElectronica}
      GROUP BY estado_dgii
    ''');

    final summary = <String, int>{};
    for (final row in rows) {
      final key =
          row['estado_dgii'] as String? ?? FacturaElectronicaModel.statusLocal;
      summary[key] = (row['total'] as int?) ?? 0;
    }
    return summary;
  }

  static Future<FacturaElectronicaModel> upsert(
    FacturaElectronicaModel model,
  ) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = model.copyWith(updatedAtMs: now);

    final existing = payload.saleId > 0
        ? await getBySaleId(payload.saleId)
        : null;
    if (existing == null) {
      final id = await db.insert(
        DbTables.facturaElectronica,
        payload.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return payload.copyWith(id: id);
    }

    await db.update(
      DbTables.facturaElectronica,
      payload.toMap(),
      where: 'sale_id = ?',
      whereArgs: [payload.saleId],
    );
    return payload.copyWith(id: existing.id);
  }
}

List<FacturaElectronicaModel> pickRecentElectronicCandidates({
  required List<FacturaElectronicaModel> orderedDocuments,
  required int limit,
  int? recentAfterMs,
}) {
  final threshold = recentAfterMs;
  final filtered = orderedDocuments
      .where((document) {
        if (threshold != null && document.createdAtMs < threshold) {
          return false;
        }
        return _isBackendPersistedDocument(document);
      })
      .toList(growable: false);

  if (filtered.length <= limit) return filtered;
  return filtered.take(limit).toList(growable: false);
}

String _resolvedElectronicDocumentKey(FacturaElectronicaModel document) {
  final ecf = (document.ecf ?? '').trim();
  if (ecf.isNotEmpty) return 'ecf:$ecf';

  final trackId = (document.dgiiTrackId ?? '').trim();
  if (trackId.isNotEmpty) return 'trk:$trackId';

  final localCode = document.localCode.trim();
  if (localCode.isNotEmpty) return 'local:$localCode';

  if (document.saleId > 0) {
    final kind = document.tipoDocumento.trim();
    return 'sale:${document.saleId}:$kind';
  }

  return 'doc:${document.hashCode}';
}

List<FacturaElectronicaModel> mergeRecentElectronicDocuments({
  required List<FacturaElectronicaModel> remote,
  required List<FacturaElectronicaModel> local,
  required int limit,
}) {
  final merged = <String, FacturaElectronicaModel>{};

  final localCandidates = pickRecentElectronicCandidates(
    orderedDocuments: (List<FacturaElectronicaModel>.from(local)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs))),
    limit: limit,
  );

  for (final document in localCandidates) {
    final estado = (document.estadoInterno ?? '').trim();
    final normalized = estado.isEmpty ? 'CACHE_ONLY' : estado;
    merged[_resolvedElectronicDocumentKey(document)] = estado == normalized
        ? document
        : document.copyWith(estadoInterno: normalized);
  }

  for (final document in remote) {
    merged[_resolvedElectronicDocumentKey(document)] = document;
  }

  final values = merged.values.toList(growable: false)
    ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  if (values.length <= limit) return values;
  return values.take(limit).toList(growable: false);
}

FacturaElectronicaModel _localOnlyFromSale(sales.SaleModel sale) {
  return FacturaElectronicaModel(
    saleId: sale.id ?? 0,
    localCode: sale.localCode,
    ecf: null,
    tipoDocumento: 'venta_local',
    dgiiTrackId: null,
    estadoDgii: FacturaElectronicaModel.statusLocal,
    estadoInterno: 'LOCAL_ONLY',
    montoTotal: sale.total,
    createdAtMs: sale.createdAtMs,
    updatedAtMs: sale.updatedAtMs,
    clienteNombre: sale.customerNameSnapshot,
    clienteRnc: sale.customerRncSnapshot,
  );
}

FacturaElectronicaModel? _findSaleElectronicDocument({
  required sales.SaleModel sale,
  required List<FacturaElectronicaModel> candidates,
}) {
  final saleId = sale.id;
  final localCode = sale.localCode.trim();
  final desiredType = (sale.electronicDocumentType ?? '').trim();

  FacturaElectronicaModel? byId(FacturaElectronicaModel doc) =>
      saleId != null && doc.saleId == saleId ? doc : null;

  FacturaElectronicaModel? byLocalCode(FacturaElectronicaModel doc) =>
      doc.localCode.trim() == localCode ? doc : null;

  FacturaElectronicaModel? byType(FacturaElectronicaModel doc) =>
      desiredType.isNotEmpty && doc.tipoDocumento.trim() == desiredType
      ? doc
      : null;

  if (desiredType.isNotEmpty) {
    for (final doc in candidates) {
      if (byType(doc) != null &&
          (byId(doc) != null || byLocalCode(doc) != null)) {
        return doc;
      }
    }
  }

  for (final doc in candidates) {
    if (byId(doc) != null) return doc;
  }
  for (final doc in candidates) {
    if (byLocalCode(doc) != null) return doc;
  }
  return null;
}

List<FacturaElectronicaModel> mergeRecentSalesDocuments({
  required List<sales.SaleModel> recentSales,
  required List<FacturaElectronicaModel> remoteElectronic,
  required List<FacturaElectronicaModel> localElectronic,
  required int limit,
}) {
  final merged = <FacturaElectronicaModel>[];

  for (final sale in recentSales) {
    if (merged.length >= limit) break;

    final enabled = sale.electronicInvoiceEnabled == 1;
    if (!enabled) {
      merged.add(_localOnlyFromSale(sale));
      continue;
    }

    final remote = _findSaleElectronicDocument(
      sale: sale,
      candidates: remoteElectronic,
    );
    if (remote != null) {
      merged.add(remote);
      continue;
    }

    final local = _findSaleElectronicDocument(
      sale: sale,
      candidates: localElectronic,
    );
    if (local != null) {
      merged.add(local);
      continue;
    }
  }

  return merged;
}
