import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'models/electronic_company_model.dart';

class ElectronicCompanyRepository {
  ElectronicCompanyRepository._();

  static Future<ElectronicCompanyModel> getOrCreate() async {
    final db = await AppDb.database;
    final rows = await db.query(DbTables.electronicCompany, limit: 1);
    if (rows.isNotEmpty) {
      return ElectronicCompanyModel.fromMap(rows.first);
    }

    final defaults = ElectronicCompanyModel.defaults();
    final id = await db.insert(DbTables.electronicCompany, defaults.toMap());
    return defaults.copyWith(id: id);
  }

  static Future<ElectronicCompanyModel> save(ElectronicCompanyModel model) async {
    final db = await AppDb.database;
    final payload = model.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final existing = await db.query(DbTables.electronicCompany, limit: 1);
    if (existing.isEmpty) {
      final id = await db.insert(DbTables.electronicCompany, payload.toMap());
      return payload.copyWith(id: id);
    }

    final id = payload.id ?? existing.first['id'] as int?;
    await db.update(
      DbTables.electronicCompany,
      payload.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    return payload.copyWith(id: id);
  }
}