import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/business_settings_repository.dart';
import 'electronic_company_locator_helper.dart';
import 'models/factura_electronica_model.dart';

String _mapRemoteInvoiceStatus(Map<dynamic, dynamic> item) {
  final dgiiStatus = (item['dgiiStatus']?.toString() ?? '').trim().toUpperCase();
  switch (dgiiStatus) {
    case 'ACCEPTED':
    case 'ACCEPTED_CONDITIONAL':
      return FacturaElectronicaModel.statusAccepted;
    case 'REJECTED':
      return FacturaElectronicaModel.statusRejected;
    case 'IN_PROCESS':
    case 'SUBMITTED':
    case 'PENDING':
      return FacturaElectronicaModel.statusPending;
  }

  final internalStatus =
      (item['internalStatus']?.toString() ?? '').trim().toUpperCase();
  if (internalStatus == 'SUBMITTED' ||
      internalStatus == 'SIGNED' ||
      internalStatus == 'GENERATED') {
    return FacturaElectronicaModel.statusPending;
  }
  return FacturaElectronicaModel.statusLocal;
}

List<FacturaElectronicaModel> _markCacheOnly(
  List<FacturaElectronicaModel> documents,
) {
  return documents
      .map(
        (document) => document.copyWith(
          estadoDgii: FacturaElectronicaModel.statusLocal,
          estadoInterno: 'CACHE_ONLY',
        ),
      )
      .toList(growable: false);
}

class FacturaElectronicaRepository {
  FacturaElectronicaRepository._();

  static Future<List<FacturaElectronicaModel>> loadRecentResolved({
    int limit = 40,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = buildElectronicCompanyLocators(
      sessionCompanyId: await SessionManager.companyId(),
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );

    if (locators.isEmpty) {
      return _markCacheOnly(await getRecent(limit: limit));
    }

    final api = ApiClient(
      baseUrl: CloudSyncService.instance.debugResolveCloudBaseUrl(settings),
    );
    final headers = <String, String>{};
    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey != null && cloudKey.isNotEmpty) {
      headers['x-cloud-key'] = cloudKey;
    }

    try {
      final response = await api.get(
        '/api/electronic-invoicing/outbound/by-rnc',
        headers: headers,
        queryParameters: <String, String>{
          ...locators,
          'limit': '$limit',
        },
        retry: false,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _markCacheOnly(await getRecent(limit: limit));
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return _markCacheOnly(await getRecent(limit: limit));
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
              codigoDgii: null,
              mensajeDgii: null,
              ambiente: null,
              montoTotal:
                  (item['totalAmount'] as num?)?.toDouble() ?? 0.0,
              clienteNombre: item['customerName']?.toString(),
              clienteRnc: item['customerRnc']?.toString(),
              tipoDescriptivo: item['documentLabel']?.toString(),
              referenciaDocumento: item['referenceDocument']?.toString(),
              estadoInterno: item['internalStatus']?.toString(),
              createdAtMs:
                  DateTime.tryParse(item['createdAt']?.toString() ?? '')
                      ?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch,
              updatedAtMs:
                  DateTime.tryParse(item['createdAt']?.toString() ?? '')
                      ?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch,
            ),
          )
          .toList(growable: false);

      for (final doc in docs.where((item) => item.saleId > 0)) {
        await upsert(doc);
      }
      return docs;
    } catch (_) {
      return _markCacheOnly(await getRecent(limit: limit));
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

  static Future<List<FacturaElectronicaModel>> getRecent({int limit = 40}) async {
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
      final key = row['estado_dgii'] as String? ?? FacturaElectronicaModel.statusLocal;
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

    final existing = payload.saleId > 0 ? await getBySaleId(payload.saleId) : null;
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