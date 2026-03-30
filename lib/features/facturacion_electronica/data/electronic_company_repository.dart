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
    final payload = ElectronicCompanyModel(
      id: model.id,
      businessName: '',
      tradeName: '',
      rnc: '',
      emissionAddress: '',
      phone: '',
      email: '',
      environment: model.environment,
      apiToken: model.apiToken,
      certificateName: model.certificateName,
      automaticEmission: model.automaticEmission,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final persisted = <String, Object?>{
      'business_name': '',
      'trade_name': '',
      'rnc': '',
      'emission_address': '',
      'phone': '',
      'email': '',
      ...payload.toMap(),
    };

    final existing = await db.query(DbTables.electronicCompany, limit: 1);
    if (existing.isEmpty) {
      final id = await db.insert(DbTables.electronicCompany, persisted);
      return payload.copyWith(id: id);
    }

    final id = payload.id ?? existing.first['id'] as int?;
    await db.update(
      DbTables.electronicCompany,
      persisted,
      where: 'id = ?',
      whereArgs: [id],
    );
    return payload.copyWith(id: id);
  }
}