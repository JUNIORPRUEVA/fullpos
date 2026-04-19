import 'package:sqflite/sqflite.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../utils/phone_validator.dart';
import '../utils/rnc_validator.dart';
import 'client_model.dart';

/// Repositorio para manejar operaciones CRUD de clientes
class ClientsRepository {
  ClientsRepository._();

  static void _validateRequired(ClientModel client) {
    final nombre = client.nombre.trim();
    final telefono = client.telefono?.trim();
    final rnc = client.rnc?.trim();

    if (nombre.isEmpty) {
      throw ArgumentError('El nombre del cliente es obligatorio');
    }

    final hasPhone = telefono != null && telefono.isNotEmpty;
    final hasRnc = rnc != null && rnc.isNotEmpty;

    if (!hasPhone && !hasRnc) {
      throw ArgumentError('Debe indicar al menos un teléfono o un RNC válido');
    }

    if (hasPhone) {
      final normalized = PhoneValidator.normalizeRDPhone(telefono);
      if (normalized == null) {
        throw ArgumentError(
          'Teléfono inválido. Use 10 dígitos RD (ej: 809-555-1234)',
        );
      }
    }

    if (hasRnc && !RncValidator.isValidBasic(rnc)) {
      throw ArgumentError('RNC inválido. Debe contener 9 dígitos');
    }
  }

  static Future<ClientModel> _restoreExistingClient(
    ClientModel existingClient,
    ClientModel incomingClient, {
    String? normalizedPhone,
    String? normalizedRnc,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existingClient.copyWith(
      nombre: incomingClient.nombre.trim(),
      direccion: incomingClient.direccion,
      rnc: normalizedRnc,
      cedula: incomingClient.cedula,
      isActive: true,
      hasCredit: existingClient.hasCredit,
      telefono: normalizedPhone,
      updatedAtMs: now,
    );

    await db.update(
      DbTables.clients,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [existingClient.id],
    );

    CloudSyncService.instance.scheduleClientsSyncSoon(
      reason: 'client_restored_on_create',
    );

    return updated;
  }

  /// Verifica si ya existe un cliente con el teléfono dado
  /// Excluye el cliente con el ID proporcionado (útil para ediciones)
  static Future<bool> existsByPhone(String phone, {int? excludeId}) async {
    final normalized = PhoneValidator.normalizeRDPhone(phone);
    if (normalized == null) return false;

    final db = await AppDb.database;
    final query = StringBuffer(
      'SELECT COUNT(*) as count FROM ${DbTables.clients} '
      'WHERE telefono = ? AND deleted_at_ms IS NULL',
    );

    final args = <dynamic>[normalized];

    if (excludeId != null) {
      query.write(' AND id != ?');
      args.add(excludeId);
    }

    final result = await db.rawQuery(query.toString(), args);
    final count = (result.first['count'] as int?) ?? 0;
    return count > 0;
  }

  static Future<bool> existsByRnc(String rnc, {int? excludeId}) async {
    final normalized = RncValidator.normalize(rnc);
    if (normalized == null) return false;

    final db = await AppDb.database;
    final query = StringBuffer(
      'SELECT COUNT(*) as count FROM ${DbTables.clients} '
      'WHERE rnc = ? AND deleted_at_ms IS NULL',
    );

    final args = <dynamic>[normalized];
    if (excludeId != null) {
      query.write(' AND id != ?');
      args.add(excludeId);
    }

    final result = await db.rawQuery(query.toString(), args);
    final count = (result.first['count'] as int?) ?? 0;
    return count > 0;
  }

  /// Crea un nuevo cliente
  static Future<int> create(ClientModel client) async {
    _validateRequired(client);

    final rawPhone = client.telefono?.trim() ?? '';
    final normalizedPhone = rawPhone.isEmpty
        ? null
        : PhoneValidator.normalizeRDPhone(rawPhone);
    final rawRnc = client.rnc?.trim() ?? '';
    final normalizedRnc = rawRnc.isEmpty ? null : RncValidator.normalize(rawRnc);

    final existingByPhone = normalizedPhone == null
        ? null
        : await getByPhone(normalizedPhone);
    final existingByRnc = normalizedRnc == null
        ? null
        : await getByRnc(normalizedRnc);

    if (existingByPhone != null &&
        existingByRnc != null &&
        existingByPhone.id != existingByRnc.id) {
      throw ArgumentError(
        'El teléfono y el RNC ya pertenecen a clientes distintos. Revise los datos antes de guardar.',
      );
    }

    final existingClient = existingByPhone ?? existingByRnc;
    if (existingClient != null) {
      if (!existingClient.isActive) {
        final restored = await _restoreExistingClient(
          existingClient,
          client,
          normalizedPhone: normalizedPhone,
          normalizedRnc: normalizedRnc,
        );
        return restored.id!;
      }

      final duplicateLabel = normalizedRnc != null
          ? 'RNC ${RncValidator.format(normalizedRnc) ?? normalizedRnc}'
          : 'teléfono ${PhoneValidator.formatRDPhone(normalizedPhone ?? '') ?? normalizedPhone ?? ''}';
      throw ArgumentError(
        'Ya existe un cliente activo con $duplicateLabel: ${existingClient.nombre}',
      );
    }

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = (client.createdAtMs > 0) ? client.createdAtMs : now;
    final updatedAt = (client.updatedAtMs > 0) ? client.updatedAtMs : now;

    final clientData = client.copyWith(
      telefono: normalizedPhone,
      rnc: normalizedRnc,
      createdAtMs: createdAt,
      updatedAtMs: updatedAt,
    );

    final id = await db.insert(
      DbTables.clients,
      clientData.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    CloudSyncService.instance.scheduleClientsSyncSoon(reason: 'client_created');
    return id;
  }

  /// Actualiza un cliente existente
  static Future<int> update(ClientModel client) async {
    if (client.id == null) {
      throw ArgumentError('Client ID cannot be null for update');
    }

    _validateRequired(client);

    final normalizedPhone = (client.telefono?.trim().isNotEmpty ?? false)
        ? PhoneValidator.normalizeRDPhone(client.telefono!.trim())
        : null;
    final normalizedRnc = (client.rnc?.trim().isNotEmpty ?? false)
        ? RncValidator.normalize(client.rnc!.trim())
        : null;

    if (normalizedPhone != null) {
      final existsPhone = await existsByPhone(normalizedPhone, excludeId: client.id);
      if (existsPhone) {
        throw ArgumentError(
          'Ya existe otro cliente con el número de teléfono '
          '${PhoneValidator.formatRDPhone(normalizedPhone) ?? normalizedPhone}',
        );
      }
    }

    if (normalizedRnc != null) {
      final existsRnc = await existsByRnc(normalizedRnc, excludeId: client.id);
      if (existsRnc) {
        throw ArgumentError(
          'Ya existe otro cliente con el RNC ${RncValidator.format(normalizedRnc) ?? normalizedRnc}',
        );
      }
    }

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final clientData = client.copyWith(
      telefono: normalizedPhone,
      rnc: normalizedRnc,
      updatedAtMs: now,
    );

    final rows = await db.update(
      DbTables.clients,
      clientData.toMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
    if (rows > 0) {
      CloudSyncService.instance.scheduleClientsSyncSoon(
        reason: 'client_updated',
      );
    }
    return rows;
  }

  /// Elimina un cliente (soft delete)
  static Future<int> delete(int id) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.update(
      DbTables.clients,
      {'deleted_at_ms': now, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows > 0) {
      CloudSyncService.instance.scheduleClientsSyncSoon(
        reason: 'client_deleted',
      );
    }
    return rows;
  }

  /// Restaura un cliente eliminado
  static Future<int> restore(int id) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.update(
      DbTables.clients,
      {'deleted_at_ms': null, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows > 0) {
      CloudSyncService.instance.scheduleClientsSyncSoon(
        reason: 'client_restored',
      );
    }
    return rows;
  }

  /// Cambia el estado activo de un cliente
  static Future<int> toggleActive(int id, bool value) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.update(
      DbTables.clients,
      {'is_active': value ? 1 : 0, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows > 0) {
      CloudSyncService.instance.scheduleClientsSyncSoon(
        reason: 'client_active_toggled',
      );
    }
    return rows;
  }

  /// Cambia el estado de crédito de un cliente
  static Future<int> toggleCredit(int id, bool value) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.update(
      DbTables.clients,
      {'has_credit': value ? 1 : 0, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows > 0) {
      CloudSyncService.instance.scheduleClientsSyncSoon(
        reason: 'client_credit_toggled',
      );
    }
    return rows;
  }

  /// Obtiene todos los clientes
  static Future<List<ClientModel>> getAll() async {
    return list(includeDeleted: false, orderBy: 'name');
  }

  /// Lista clientes con filtros avanzados
  static Future<List<ClientModel>> list({
    String? query,
    bool? isActive,
    bool? hasCredit,
    int? createdFromMs,
    int? createdToMs,
    bool includeDeleted = false,
    String orderBy = 'recent',
    int limit = 500,
  }) async {
    final db = await AppDb.database;

    // Construir WHERE clause
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    // Filtro de eliminados
    if (!includeDeleted) {
      whereClauses.add('deleted_at_ms IS NULL');
    }

    // Filtro de estado activo
    if (isActive != null) {
      whereClauses.add('is_active = ?');
      whereArgs.add(isActive ? 1 : 0);
    }

    // Filtro de crédito
    if (hasCredit != null) {
      whereClauses.add('has_credit = ?');
      whereArgs.add(hasCredit ? 1 : 0);
    }

    // Filtro de texto (nombre, teléfono, RNC, cédula)
    if (query != null && query.trim().isNotEmpty) {
      whereClauses.add(
        '(nombre LIKE ? OR telefono LIKE ? OR rnc LIKE ? OR cedula LIKE ?)',
      );
      final searchTerm = '%${query.trim()}%';
      whereArgs.addAll([searchTerm, searchTerm, searchTerm, searchTerm]);
    }

    // Filtro de rango de fechas
    if (createdFromMs != null) {
      whereClauses.add('created_at_ms >= ?');
      whereArgs.add(createdFromMs);
    }

    if (createdToMs != null) {
      whereClauses.add('created_at_ms <= ?');
      whereArgs.add(createdToMs);
    }

    // Construir ORDER BY
    String orderByClause;
    switch (orderBy) {
      case 'old':
        orderByClause = 'created_at_ms ASC';
        break;
      case 'name':
        orderByClause = 'nombre COLLATE NOCASE ASC';
        break;
      case 'recent':
      default:
        orderByClause = 'created_at_ms DESC';
    }

    // Ejecutar query
    final maps = await db.query(
      DbTables.clients,
      where: whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderByClause,
      limit: limit,
    );

    return maps.map((map) => ClientModel.fromMap(map)).toList();
  }

  /// Obtiene un cliente por ID
  static Future<ClientModel?> getById(int id) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.clients,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ClientModel.fromMap(maps.first);
  }

  /// Busca un cliente por teléfono
  static Future<ClientModel?> getByPhone(String phone) async {
    final normalized = PhoneValidator.normalizeRDPhone(phone);
    if (normalized == null) return null;

    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.clients,
      where: 'telefono = ? AND deleted_at_ms IS NULL',
      whereArgs: [normalized],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ClientModel.fromMap(maps.first);
  }

  static Future<ClientModel?> getByRnc(String rnc) async {
    final normalized = RncValidator.normalize(rnc);
    if (normalized == null) return null;

    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.clients,
      where: 'rnc = ? AND deleted_at_ms IS NULL',
      whereArgs: [normalized],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ClientModel.fromMap(maps.first);
  }

  /// Busca clientes por nombre o teléfono
  static Future<List<ClientModel>> search(String query) async {
    return list(query: query);
  }

  /// Inserta un nuevo cliente (alias para create)
  static Future<int> insert(ClientModel client) async {
    return create(client);
  }
}
