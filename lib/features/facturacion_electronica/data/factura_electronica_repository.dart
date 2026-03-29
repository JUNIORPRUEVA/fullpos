import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'models/factura_electronica_model.dart';

class FacturaElectronicaRepository {
  FacturaElectronicaRepository._();

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

    final existing = await getBySaleId(payload.saleId);
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