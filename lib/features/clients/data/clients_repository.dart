import 'package:sqflite/sqflite.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../utils/phone_validator.dart';
import 'client_model.dart';

/// Repositorio para manejar operaciones CRUD de clientes
class ClientsRepository {
  ClientsRepository._();

  static void _validateRequired(ClientModel client) {
    final nombre = client.nombre.trim();
    final telefono = client.telefono?.trim();

    if (nombre.isEmpty) {
      throw ArgumentError('El nombre del cliente es obligatorio');
    }
    if (telefono == null || telefono.isEmpty) {
      throw ArgumentError('El teléfono del cliente es obligatorio');
    }

    // Validación consistente: debe poder normalizarse a +1XXXXXXXXXX.
    // (Acepta espacios/guiones/paréntesis, pero requiere 10 dígitos RD.)
    final normalized = PhoneValidator.normalizeRDPhone(telefono);
    if (normalized == null) {
      throw ArgumentError(
        'Teléfono inválido. Use 10 dígitos RD (ej: 809-555-1234)',
      );
    }
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

  /// Crea un nuevo cliente
  static Future<int> create(ClientModel client) async {
    _validateRequired(client);

    final rawPhone = client.telefono!.trim();
    final normalizedPhone = PhoneValidator.normalizeRDPhone(rawPhone);
    if (normalizedPhone == null) {
      throw ArgumentError(
        'Teléfono inválido. Use 10 dígitos RD (ej: 809-555-1234)',
      );
    }

    // Verificar que no exista cliente con el mismo teléfono
    final existente = await existsByPhone(rawPhone);
    if (existente) {
      final existingClient = await getByPhone(rawPhone);
      if (existingClient != null) {
        // Caso típico: el cliente existe pero está inactivo (no sale en listas filtradas).
        // Reactivar y actualizar datos en vez de bloquear.
        if (!existingClient.isActive) {
          final db = await AppDb.database;
          final now = DateTime.now().millisecondsSinceEpoch;

          final updated = existingClient.copyWith(
            nombre: client.nombre.trim(),
            direccion: client.direccion,
            rnc: client.rnc,
            cedula: client.cedula,
            isActive: true,
            // Mantener hasCredit existente para no perder configuración.
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

          return existingClient.id!;
        }

        // Cliente activo existe - este error solo debería verse si se llama desde código
        // (no desde el formulario, que ya verifica antes)
        throw ArgumentError(
          'Ya existe un cliente activo: ${existingClient.nombre}',
        );
      }

      // Esto no debería pasar (existsByPhone encontró algo pero getByPhone no)
      throw ArgumentError('Ya existe un cliente con este teléfono');
    }

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = (client.createdAtMs > 0) ? client.createdAtMs : now;
    final updatedAt = (client.updatedAtMs > 0) ? client.updatedAtMs : now;

    final clientData = client.copyWith(
      telefono: normalizedPhone, // Guardar teléfono normalizado
      createdAtMs: createdAt,
      updatedAtMs: updatedAt,
    );

    return await db.insert(
      DbTables.clients,
      clientData.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Actualiza un cliente existente
  static Future<int> update(ClientModel client) async {
    if (client.id == null) {
      throw ArgumentError('Client ID cannot be null for update');
    }

    _validateRequired(client);

    // Verificar que no exista otro cliente con el mismo teléfono
    final existe = await existsByPhone(client.telefono!, excludeId: client.id);
    if (existe) {
      throw ArgumentError(
        'Ya existe otro cliente con el número de teléfono '
        '${PhoneValidator.formatRDPhone(client.telefono!) ?? client.telefono}',
      );
    }

    // Normalizar el teléfono
    final telefonoNormalizado = PhoneValidator.normalizeRDPhone(
      client.telefono!,
    );

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final clientData = client.copyWith(
      telefono: telefonoNormalizado, // Guardar teléfono normalizado
      updatedAtMs: now,
    );

    return await db.update(
      DbTables.clients,
      clientData.toMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
  }

  /// Elimina un cliente (soft delete)
  static Future<int> delete(int id) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.clients,
      {'deleted_at_ms': now, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restaura un cliente eliminado
  static Future<int> restore(int id) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.clients,
      {'deleted_at_ms': null, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cambia el estado activo de un cliente
  static Future<int> toggleActive(int id, bool value) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.clients,
      {'is_active': value ? 1 : 0, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cambia el estado de crédito de un cliente
  static Future<int> toggleCredit(int id, bool value) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.clients,
      {'has_credit': value ? 1 : 0, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Busca clientes por nombre o teléfono
  static Future<List<ClientModel>> search(String query) async {
    return list(query: query);
  }

  /// Inserta un nuevo cliente (alias para create)
  static Future<int> insert(ClientModel client) async {
    return create(client);
  }
}
