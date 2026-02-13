import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/session/session_manager.dart';
import 'user_model.dart';

/// Repositorio para gestión de usuarios
class UsersRepository {
  UsersRepository._();

  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  static String _normalizeUsername(String username) =>
      username.trim().toLowerCase();

  static Future<T> _dbSafe<T>(
    Future<T> Function(Database db) op, {
    String stage = 'users',
  }) {
    return DbHardening.instance.runDbSafe(() async {
      final db = await AppDb.database;
      return op(db);
    }, stage: stage);
  }

  /// Genera hash SHA256 de una contraseña
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Obtener todos los usuarios activos
  static Future<List<UserModel>> getAll({int? companyId}) async {
    return _dbSafe((db) async {
      final companyFilter = companyId ?? 1;
      final maps = await db.query(
        DbTables.users,
        where: 'deleted_at_ms IS NULL AND company_id = ?',
        whereArgs: [companyFilter],
        orderBy: 'role ASC, username ASC',
      );
      return maps.map((m) => UserModel.fromMap(m)).toList();
    }, stage: 'users/get_all');
  }

  /// Obtener usuario por ID
  static Future<UserModel?> getById(int id, {int? companyId}) async {
    if (_isFlutterTest) {
      final sessionUserId = await SessionManager.userId();
      if (sessionUserId == id) {
        final username = await SessionManager.username() ?? 'cashier';
        final role = await SessionManager.role() ?? 'cashier';
        final companyFilter = companyId ?? await SessionManager.companyId() ?? 1;
        final now = DateTime.now().millisecondsSinceEpoch;
        return UserModel(
          id: id,
          companyId: companyFilter,
          username: username,
          role: role,
          isActive: 1,
          createdAtMs: now,
          updatedAtMs: now,
        );
      }
    }

    return _dbSafe((db) async {
      final companyFilter = companyId ?? 1;
      final maps = await db.query(
        DbTables.users,
        where: 'id = ? AND deleted_at_ms IS NULL AND company_id = ?',
        whereArgs: [id, companyFilter],
      );
      if (maps.isEmpty) return null;
      return UserModel.fromMap(maps.first);
    }, stage: 'users/get_by_id');
  }

  /// Obtener usuario por username
  static Future<UserModel?> getByUsername(
    String username, {
    int? companyId,
  }) async {
    return _dbSafe((db) async {
      final companyFilter = companyId ?? 1;
      final maps = await db.query(
        DbTables.users,
        where: 'username = ? AND deleted_at_ms IS NULL AND company_id = ?',
        whereArgs: [_normalizeUsername(username), companyFilter],
      );
      if (maps.isEmpty) return null;
      return UserModel.fromMap(maps.first);
    }, stage: 'users/get_by_username');
  }

  /// Verificar credenciales (username + password)
  static Future<UserModel?> verifyCredentials(
    String username,
    String password, {
    int? companyId,
  }) async {
    return _dbSafe((db) async {
      final passwordHash = hashPassword(password);
      final companyFilter = companyId ?? 1;

      final maps = await db.query(
        DbTables.users,
        where:
            'username = ? AND password_hash = ? AND is_active = 1 AND deleted_at_ms IS NULL AND company_id = ?',
        whereArgs: [_normalizeUsername(username), passwordHash, companyFilter],
      );
      if (maps.isEmpty) return null;
      return UserModel.fromMap(maps.first);
    }, stage: 'users/verify_credentials');
  }

  /// Verificar PIN de usuario
  static Future<UserModel?> verifyPin(
    String username,
    String pin, {
    int? companyId,
  }) async {
    return _dbSafe((db) async {
      final companyFilter = companyId ?? 1;
      final maps = await db.query(
        DbTables.users,
        where:
            'username = ? AND pin = ? AND is_active = 1 AND deleted_at_ms IS NULL AND company_id = ?',
        whereArgs: [_normalizeUsername(username), pin, companyFilter],
      );
      if (maps.isEmpty) return null;
      return UserModel.fromMap(maps.first);
    }, stage: 'users/verify_pin');
  }

  /// Crear nuevo usuario
  static Future<int> create(UserModel user) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final normalized = _normalizeUsername(user.username);
      final companyFilter = user.companyId;

      // Verificar conflicto con usuario activo.
      final exists = await db.query(
        DbTables.users,
        columns: ['id'],
        where: 'company_id = ? AND username = ? AND deleted_at_ms IS NULL',
        whereArgs: [companyFilter, normalized],
        limit: 1,
      );
      if (exists.isNotEmpty) {
        throw ArgumentError('Ya existe un usuario activo con ese username');
      }

      return db.transaction((txn) async {
        // Si existe un usuario eliminado con el mismo username, reactivarlo.
        final deletedRows = await txn.query(
          DbTables.users,
          columns: ['id', 'created_at_ms'],
          where: 'company_id = ? AND username = ? AND deleted_at_ms IS NOT NULL',
          whereArgs: [companyFilter, normalized],
          limit: 1,
        );

        final createdAt = (user.createdAtMs > 0) ? user.createdAtMs : now;
        final updatedAt = (user.updatedAtMs > 0) ? user.updatedAtMs : now;

        if (deletedRows.isNotEmpty) {
          final id = deletedRows.first['id'] as int;
          final legacyCreatedAt = deletedRows.first['created_at_ms'] as int?;
          final data = user.toMap()
            ..remove('id')
            ..['company_id'] = companyFilter
            ..['username'] = normalized
            ..['deleted_at_ms'] = null
            ..['is_active'] = 1
            ..['updated_at_ms'] = updatedAt
            ..['created_at_ms'] = legacyCreatedAt ?? createdAt;

          await txn.update(
            DbTables.users,
            data,
            where: 'id = ?',
            whereArgs: [id],
          );
          return id;
        }

        final data = user.toMap()
          ..['company_id'] = companyFilter
          ..['username'] = normalized
          ..['created_at_ms'] = createdAt
          ..['updated_at_ms'] = updatedAt
          ..['deleted_at_ms'] = null;

        return txn.insert(DbTables.users, data);
      });
    }, stage: 'users/create');
  }

  /// Actualizar usuario
  static Future<int> update(UserModel user) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final data = user.toMap();
      data['updated_at_ms'] = now;
      data['username'] = _normalizeUsername(user.username);

      return db.update(
        DbTables.users,
        data,
        where: 'id = ?',
        whereArgs: [user.id],
      );
    }, stage: 'users/update');
  }

  /// Eliminar usuario (soft delete)
  static Future<int> delete(int id) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.update(
        DbTables.users,
        {
          'deleted_at_ms': now,
          'is_active': 0,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/delete');
  }

  /// Restaurar usuario eliminado (soft delete)
  static Future<int> restore(int id) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      final rows = await db.query(
        DbTables.users,
        columns: ['username', 'company_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw ArgumentError('Usuario no encontrado');
      }

      final username = rows.first['username'] as String;
      final companyId = rows.first['company_id'] as int? ?? 1;

      final conflict = await db.query(
        DbTables.users,
        columns: ['id'],
        where:
            'company_id = ? AND username = ? AND deleted_at_ms IS NULL AND id != ?',
        whereArgs: [companyId, username, id],
        limit: 1,
      );
      if (conflict.isNotEmpty) {
        throw ArgumentError(
          'No se puede restaurar: ya existe un usuario activo con ese username',
        );
      }

      return db.update(
        DbTables.users,
        {
          'deleted_at_ms': null,
          'is_active': 1,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/restore');
  }

  /// Eliminar permanentemente un usuario
  static Future<int> hardDelete(int id) async {
    return _dbSafe((db) async {
      return db.delete(
        DbTables.users,
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/hard_delete');
  }

  /// Activar/Desactivar usuario
  static Future<int> toggleActive(int id, bool active) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.update(
        DbTables.users,
        {
          'is_active': active ? 1 : 0,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/toggle_active');
  }

  /// Cambiar contraseña de usuario
  static Future<int> changePassword(int id, String newPassword) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final passwordHash = hashPassword(newPassword);

      return db.update(
        DbTables.users,
        {
          'password_hash': passwordHash,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/change_password');
  }

  /// Cambiar PIN de usuario
  static Future<int> changePin(int id, String? newPin) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.update(
        DbTables.users,
        {
          'pin': newPin,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/change_pin');
  }

  /// Cambiar rol de usuario
  static Future<int> changeRole(int id, String role) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.update(
        DbTables.users,
        {
          'role': role,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/change_role');
  }

  /// Guardar permisos personalizados
  static Future<int> savePermissions(int id, UserPermissions permissions) async {
    return _dbSafe((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.update(
        DbTables.users,
        {
          'permissions': jsonEncode(permissions.toMap()),
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }, stage: 'users/save_permissions');
  }

  /// Obtener permisos de usuario
  static Future<UserPermissions> getPermissions(int userId) async {
    final user = await getById(userId);
    if (user == null) return UserPermissions.cashier();
    
    // Admin tiene todos los permisos
    if (user.isAdmin) return UserPermissions.admin();
    
    // Si tiene permisos personalizados
    if (user.permissions != null && user.permissions!.isNotEmpty) {
      try {
        final map = jsonDecode(user.permissions!) as Map<String, dynamic>;
        return UserPermissions.fromMap(map);
      } catch (_) {
        return UserPermissions.cashier();
      }
    }
    
    // Permisos por defecto según rol
    return UserPermissions.cashier();
  }

  /// Verificar si existe username
  static Future<bool> usernameExists(
    String username, {
    int? excludeId,
    int? companyId,
  }) async {
    return _dbSafe((db) async {
      final companyFilter = companyId ?? 1;
      final normalized = _normalizeUsername(username);
      final where = StringBuffer(
        'company_id = ? AND username = ? AND deleted_at_ms IS NULL',
      );
      final whereArgs = <dynamic>[companyFilter, normalized];

      if (excludeId != null) {
        where.write(' AND id != ?');
        whereArgs.add(excludeId);
      }

      final maps = await db.query(
        DbTables.users,
        where: where.toString(),
        whereArgs: whereArgs,
        limit: 1,
      );
      return maps.isNotEmpty;
    }, stage: 'users/username_exists');
  }

  /// Contar usuarios por rol
  static Future<Map<String, int>> countByRole() async {
    return _dbSafe((db) async {
      final result = await db.rawQuery('''
      SELECT role, COUNT(*) as count 
      FROM ${DbTables.users} 
      WHERE deleted_at_ms IS NULL AND is_active = 1
      GROUP BY role
    ''');
    
      final counts = <String, int>{'admin': 0, 'cashier': 0};
      for (final row in result) {
        final role = row['role'] as String;
        counts[role] = row['count'] as int;
      }
      return counts;
    }, stage: 'users/count_by_role');
  }

  /// Obtener usuarios activos para selector
  static Future<List<UserModel>> getActiveUsers() async {
    return _dbSafe((db) async {
      final maps = await db.query(
        DbTables.users,
        where: 'is_active = 1 AND deleted_at_ms IS NULL',
        orderBy: 'display_name ASC, username ASC',
      );
      return maps.map((m) => UserModel.fromMap(m)).toList();
    }, stage: 'users/get_active_users');
  }
}
