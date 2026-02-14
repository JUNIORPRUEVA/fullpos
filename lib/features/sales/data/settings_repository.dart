import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'business_info_model.dart';
import 'app_settings_model.dart';
import 'user_model.dart';

/// Repositorio para configuración general
class SettingsRepository {
  SettingsRepository._();

  // ===== BUSINESS INFO =====

  /// Obtiene la información del negocio (solo hay 1 registro)
  static Future<BusinessInfoModel> getBusinessInfo() async {
    final db = await AppDb.database;
    final maps = await db.query(DbTables.businessInfo, limit: 1);

    if (maps.isEmpty) {
      // Retornar valores por defecto si no existe
      final now = DateTime.now().millisecondsSinceEpoch;
      return BusinessInfoModel(
        id: null,
        name: 'FULLPOS',
        rnc: '',
        address: '',
        phone: '',
        slogan: '',
        updatedAtMs: now,
      );
    }

    final info = BusinessInfoModel.fromMap(maps.first);
    final hasCustomData =
        (info.phone ?? '').trim().isNotEmpty ||
        (info.address ?? '').trim().isNotEmpty ||
        (info.rnc ?? '').trim().isNotEmpty ||
        (info.slogan ?? '').trim().isNotEmpty;
    if (info.name.trim() == 'Mi Negocio' && !hasCustomData) {
      final updated = info.copyWith(
        name: 'FULLPOS',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await updateBusinessInfo(updated);
      return updated;
    }

    return info;
  }

  /// Actualiza la información del negocio
  static Future<void> updateBusinessInfo(BusinessInfoModel info) async {
    final db = await AppDb.database;

    final existing = await db.query(DbTables.businessInfo, limit: 1);

    if (existing.isEmpty) {
      await db.insert(DbTables.businessInfo, info.toMap());
    } else {
      await db.update(
        DbTables.businessInfo,
        info.toMap(),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  // ===== APP SETTINGS =====

  /// Obtiene la configuración de la app (solo hay 1 registro)
  static Future<AppSettingsModel> getAppSettings() async {
    final db = await AppDb.database;
    final maps = await db.query(DbTables.appSettings, limit: 1);

    if (maps.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return AppSettingsModel(
        id: null,
        itbisEnabledDefault: true,
        fiscalEnabledDefault: false,
        itbisRate: 0.18,
        ticketSize: '80mm',
        updatedAtMs: now,
      );
    }

    return AppSettingsModel.fromMap(maps.first);
  }

  /// Actualiza la configuración
  static Future<void> updateAppSettings(AppSettingsModel settings) async {
    final db = await AppDb.database;

    final existing = await db.query(DbTables.appSettings, limit: 1);

    if (existing.isEmpty) {
      await db.insert(DbTables.appSettings, settings.toMap());
    } else {
      await db.update(
        DbTables.appSettings,
        settings.toMap(),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  // ===== USERS =====

  /// Lista todos los usuarios
  static Future<List<UserModel>> getAllUsers() async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.users,
      where: 'is_active = 1',
      orderBy: 'username ASC',
    );
    return maps.map((m) => UserModel.fromMap(m)).toList();
  }

  /// Obtiene un usuario por ID
  static Future<UserModel?> getUserById(int id) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.users,
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isEmpty ? null : UserModel.fromMap(maps.first);
  }

  /// Valida credenciales de usuario
  static Future<UserModel?> validateUser(String username, String pin) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.users,
      where: 'username = ? AND pin = ? AND is_active = 1',
      whereArgs: [username, pin],
    );
    return maps.isEmpty ? null : UserModel.fromMap(maps.first);
  }

  /// Crea un nuevo usuario
  static Future<int> createUser(UserModel user) async {
    final db = await AppDb.database;
    return await db.insert(DbTables.users, user.toMap());
  }

  /// Actualiza un usuario
  static Future<int> updateUser(UserModel user) async {
    final db = await AppDb.database;
    return await db.update(
      DbTables.users,
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  /// Desactiva un usuario
  static Future<int> deactivateUser(int id) async {
    final db = await AppDb.database;
    return await db.update(
      DbTables.users,
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
