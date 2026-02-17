import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../backup/backup_zip.dart';
import '../config/app_config.dart';
import '../database/migrations/migration_safety.dart';
import '../utils/color_utils.dart';
import 'db_init.dart';
import 'tables.dart';

/// Singleton para manejar la base de datos SQLite de la aplicación
class AppDb {
  AppDb._();

  static Database? _database;
  // Evita aperturas concurrentes que pueden dejar conexiones huérfanas y provocar
  // "database is locked" (común en desktop/FFI).
  static Future<Database>? _opening;
  static String? _dbPathOverride;
  static const String _productionDbName = 'fullpos.db';
  static const String _testDbName = 'fullpos_test.db';

  // Catalogo demo (categorias y productos).
  static const List<String> demoCategoryNames = [
    'Taladros recargables',
    'Taladros eléctricos',
    'Cajas de herramientas',
    'Juegos de cubos',
    'Tubería PVC',
    'Electricidad',
    'Plomería',
    'Medición',
    'Seguridad',
    'Adhesivos y sellantes',
  ];

  static const String demoProductCodePrefix = 'DEMO-';

  // Bump para forzar upgrade en PCs con DB creada sin columnas nuevas.
  static const int _dbVersion = 29;

  /// FULLPOS DB HARDENING: exponer versión del esquema.
  static int get schemaVersion => _dbVersion;

  // Por defecto usamos SIEMPRE la DB de producción.
  // Si necesitas simular migraciones localmente, ejecuta en debug con:
  // `--dart-define=USE_TEST_DB=true`
  static bool get isUsingTestDb =>
      !kReleaseMode &&
      const bool.fromEnvironment('USE_TEST_DB', defaultValue: false);

  static String get dbFileName =>
      isUsingTestDb ? _testDbName : _productionDbName;

  /// Snapshot síncrono del estado de la DB (para diagnósticos/logs).
  ///
  /// No abre la base de datos ni hace I/O.
  static Map<String, Object?> diagnosticsSnapshot() {
    final db = _database;
    return <String, Object?>{
      'dbFileName': dbFileName,
      'isUsingTestDb': isUsingTestDb,
      'schemaVersion': _dbVersion,
      'isOpen': db?.isOpen ?? false,
      'isOpening': _opening != null,
      if (_dbPathOverride != null) 'pathOverride': _dbPathOverride,
    };
  }

  /// Obtiene la instancia de la base de datos
  static Future<Database> get database async {
    DbInit.ensureInitialized();
    // Fast-path: ya abierta y válida.
    final existing = _database;
    if (existing != null) {
      if (existing.isOpen) return existing;
      _database = null;
    }

    // Si ya hay una apertura en curso, esperar esa misma.
    final inFlight = _opening;
    if (inFlight != null) {
      final db = await inFlight;
      // Nota: en escenarios raros (p.ej. backup) puede cerrarse justo después de abrir.
      if (db.isOpen) return db;
    }

    // Iniciar apertura única.
    final future = _initDatabase();
    _opening = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } finally {
      // Solo limpiar si seguimos siendo la apertura registrada.
      if (identical(_opening, future)) {
        _opening = null;
      }
    }
  }

  /// Inicializa la base de datos
  static Future<Database> _initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final primaryPath = join(docsDir.path, dbFileName);
    final path = await _resolveDbPath();
    if (path != primaryPath) {
      await _copyDbIfMissing(sourcePath: primaryPath, targetPath: path);
    }

    final dbFile = File(path);
    Directory? preMigrationBackupDir;
    int? existingUserVersion;

    if (await dbFile.exists()) {
      Database? ro;
      try {
        ro = await openDatabase(path, readOnly: true, singleInstance: false);
        final rows = await ro.rawQuery('PRAGMA user_version');
        existingUserVersion = rows.isNotEmpty
            ? (rows.first['user_version'] as int?)
            : null;
      } catch (_) {
        // Ignorar: si falla lectura read-only, seguimos con el openDatabase normal.
      } finally {
        try {
          await ro?.close();
        } catch (_) {
          // Ignorar.
        }
      }
    }

    if (existingUserVersion != null && existingUserVersion < _dbVersion) {
      try {
        preMigrationBackupDir = await MigrationSafety.createPreMigrationBackup(
          dbPath: path,
          oldVersion: existingUserVersion,
          newVersion: _dbVersion,
        );
      } catch (_) {
        // No bloquear apertura por fallo de pre-backup.
        preMigrationBackupDir = null;
      }
    }

    try {
      return await _openMainDatabase(path);
    } catch (error) {
      if (_isReadOnlyError(error) && path == primaryPath) {
        final supportDir = await getApplicationSupportDirectory();
        final fallbackPath = join(supportDir.path, dbFileName);
        _dbPathOverride = fallbackPath;
        await _copyDbIfMissing(
          sourcePath: primaryPath,
          targetPath: fallbackPath,
        );
        return await _openMainDatabase(fallbackPath);
      }

      // 1) Si tenemos backup pre-migración, intentar restaurar y REINTENTAR abrir.
      if (preMigrationBackupDir != null) {
        try {
          await close();
          await MigrationSafety.restorePreMigrationBackup(
            backupDir: preMigrationBackupDir,
            dbPath: path,
          );
          return await _openMainDatabase(
            path,
            singleInstance: false,
            timeout: const Duration(seconds: 5),
          );
        } catch (_) {
          // Si falla, seguimos con otras estrategias.
        }
      }

      // 2) Auto-repair SOLO para errores que parecen corrupción.
      if (_isCorruptionError(error)) {
        try {
          await close();
        } catch (_) {}

        // 2a) Intentar restaurar desde el backup ZIP más reciente.
        final restored = await _tryRestoreFromLatestBackupZip(dbPath: path);
        if (restored) {
          try {
            return await _openMainDatabase(
              path,
              singleInstance: false,
              timeout: const Duration(seconds: 5),
            );
          } catch (_) {
            // Si aún falla, caer a cuarentena.
          }
        }

        // 2b) Si no hay backup, poner DB en cuarentena y recrear una nueva.
        final quarantined = await _quarantineDbFiles(dbPath: path);
        if (quarantined) {
          try {
            return await _openMainDatabase(
              path,
              singleInstance: false,
              timeout: const Duration(seconds: 5),
            );
          } catch (_) {
            // Si vuelve a fallar, dejamos que propague.
          }
        }
      }

      rethrow;
    }
  }

  static bool _isCorruptionError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('database disk image is malformed') ||
        message.contains('file is not a database') ||
        message.contains('not a database') ||
        message.contains('malformed');
  }

  static Future<Database> _openMainDatabase(
    String path, {
    bool singleInstance = true,
    Duration? timeout,
  }) async {
    final future = openDatabase(
      path,
      version: _dbVersion,
      singleInstance: singleInstance,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // Defensa: algunas instalaciones pueden tener la versión actual
        // pero carecer de columnas por una migración fallida/interrumpida.
        await _ensureSchemaIntegrity(db);
        await _syncDemoCatalog(db);
      },
    );
    return timeout == null ? future : future.timeout(timeout);
  }

  static Future<bool> _tryRestoreFromLatestBackupZip({
    required String dbPath,
  }) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final baseDir = Directory(join(docsDir.path, 'FULLPOS_BACKUPS'));
      if (!await baseDir.exists()) return false;

      final zips = baseDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.zip'))
          .toList(growable: false);
      if (zips.isEmpty) return false;

      zips.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final zip = zips.first;

      final tempDir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final extractDir = Directory(
        join(tempDir.path, 'fullpos_db_repair_$stamp'),
      );
      if (!await extractDir.exists()) await extractDir.create(recursive: true);

      try {
        await BackupZip.extractZip(
          zipPath: zip.path,
          outDirPath: extractDir.path,
        );

        final extractedDb = File(join(extractDir.path, 'db', dbFileName));
        if (!await extractedDb.exists()) return false;

        // Antes de sobrescribir, mover la DB actual a cuarentena.
        await _quarantineDbFiles(dbPath: dbPath);

        await _deleteIfExists(File(dbPath));
        await extractedDb.copy(dbPath);

        // Restaurar WAL/SHM si vienen en el backup, o borrar los destinos.
        final extractedWal = File(
          join(extractDir.path, 'db', '$dbFileName-wal'),
        );
        final extractedShm = File(
          join(extractDir.path, 'db', '$dbFileName-shm'),
        );
        final destWal = File('$dbPath-wal');
        final destShm = File('$dbPath-shm');

        if (await extractedWal.exists()) {
          await _deleteIfExists(destWal);
          await extractedWal.copy(destWal.path);
        } else {
          await _deleteIfExists(destWal);
        }

        if (await extractedShm.exists()) {
          await _deleteIfExists(destShm);
          await extractedShm.copy(destShm.path);
        } else {
          await _deleteIfExists(destShm);
        }

        // Validar integridad del DB restaurado (best-effort).
        final ok = await _verifyDbIntegrity(dbPath);
        return ok ?? true;
      } finally {
        try {
          if (await extractDir.exists()) {
            await extractDir.delete(recursive: true);
          }
        } catch (_) {
          // Ignorar.
        }
      }
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _quarantineDbFiles({required String dbPath}) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final qDir = Directory(
        join(docsDir.path, 'FULLPOS_BACKUPS', 'quarantine', 'db_$stamp'),
      );
      if (!await qDir.exists()) await qDir.create(recursive: true);

      Future<void> moveIfExists(String fromPath, String toName) async {
        final from = File(fromPath);
        if (!await from.exists()) return;
        final to = File(join(qDir.path, toName));
        try {
          await from.rename(to.path);
        } catch (_) {
          try {
            await from.copy(to.path);
            await _deleteIfExists(from);
          } catch (_) {
            // Ignorar.
          }
        }
      }

      await moveIfExists(dbPath, dbFileName);
      await moveIfExists('$dbPath-wal', '$dbFileName-wal');
      await moveIfExists('$dbPath-shm', '$dbFileName-shm');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignorar.
    }
  }

  static Future<bool?> _verifyDbIntegrity(String dbPath) async {
    try {
      DbInit.ensureInitialized();
      final db = await openDatabase(
        dbPath,
        readOnly: false,
        singleInstance: false,
      ).timeout(const Duration(seconds: 5));
      final res = await db
          .rawQuery('PRAGMA integrity_check;')
          .timeout(const Duration(seconds: 5));
      await db.close().timeout(const Duration(seconds: 2));
      final msg = (res.isNotEmpty ? (res.first.values.first) : null)
          ?.toString()
          .toLowerCase();
      return msg == 'ok';
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> databasePath() async => _resolveDbPath();

  static Future<String> _resolveDbPath() async {
    if (_dbPathOverride != null) return _dbPathOverride!;
    final docsDir = await getApplicationDocumentsDirectory();
    final primaryPath = join(docsDir.path, dbFileName);
    if (await _canWriteToPath(primaryPath)) {
      _dbPathOverride = primaryPath;
      return primaryPath;
    }
    final supportDir = await getApplicationSupportDirectory();
    final fallbackPath = join(supportDir.path, dbFileName);
    _dbPathOverride = fallbackPath;
    return fallbackPath;
  }

  static Future<bool> _canWriteToPath(String path) async {
    final file = File(path);
    final dir = file.parent;
    try {
      if (await file.exists()) {
        final handle = await file.open(mode: FileMode.append);
        await handle.close();
        return true;
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File(join(dir.path, '.fullpos_write_probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _copyDbIfMissing({
    required String sourcePath,
    required String targetPath,
  }) async {
    try {
      final source = File(sourcePath);
      final target = File(targetPath);
      if (!await source.exists()) return;
      if (await target.exists()) return;
      await target.parent.create(recursive: true);
      await source.copy(target.path);
    } catch (_) {
      // Ignorar.
    }
  }

  static bool _isReadOnlyError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    // sqflite/sqflite_ffi incluye metadatos como "readOnly: false" en el error.
    // Eso NO significa que sea un error de permisos; evitar falsos positivos.
    if (lower.contains('readonly: true') || lower.contains('readonly: false')) {
      // No retornamos true solo por aparecer este campo.
    }

    // Señales típicas de SQLite cuando el archivo realmente es solo lectura.
    if (lower.contains('attempt to write a readonly database')) return true;
    if (lower.contains('attempt to write a read-only database')) return true;
    if (lower.contains('sqlite_readonly') || lower.contains('sqlitereadonly')) {
      return true;
    }
    if (lower.contains('read-only file system')) return true;

    // Match conservador: palabra "readonly" como token, pero NO "readOnly:".
    if (lower.contains('readonly:')) return false;
    if (RegExp(r'\breadonly\b').hasMatch(lower)) return true;
    if (RegExp(r'\bread only\b').hasMatch(lower)) return true;

    return false;
  }

  static Future<void> _onConfigure(Database db) async {
    // Configuración recomendada para reducir riesgo de corrupción y asegurar integridad.
    // En algunos entornos puede fallar; no debe romper la app.
    try {
      await db.execute('PRAGMA foreign_keys = ON;');
    } catch (_) {}
    try {
      await db.execute('PRAGMA journal_mode = WAL;');
    } catch (_) {}
    try {
      await db.execute('PRAGMA synchronous = NORMAL;');
    } catch (_) {}
    try {
      // FULLPOS DB HARDENING: reducir errores "database is locked".
      await db.execute('PRAGMA busy_timeout = 5000;');
    } catch (_) {}
  }

  /// Solo para pruebas: cierra y elimina la base de datos para arrancar limpio
  static Future<void> resetForTests() async {
    await close();
    _dbPathOverride = null;
    final docsDir = await getApplicationDocumentsDirectory();
    final path = join(docsDir.path, dbFileName);
    final supportDir = await getApplicationSupportDirectory();
    final fallbackPath = join(supportDir.path, dbFileName);
    try {
      await deleteDatabase(path);
    } catch (_) {
      // Ignorar fallos al borrar en entorno de prueba
    }
    try {
      await deleteDatabase(fallbackPath);
    } catch (_) {
      // Ignorar
    }
  }

  /// DEBUG-ONLY: crea una DB "vieja" en el archivo de test (sin tocar la real).
  ///
  /// - Solo afecta a `fullpos_test.db` (cuando `kDebugMode == true`).
  /// - Crea el esquema actual y luego simula `stock_movements` legacy SIN `user_id`.
  /// - Fuerza `PRAGMA user_version = 20` para que al abrir con versión 21 corra onUpgrade.
  static Future<void> resetTestDbToLegacySchema() async {
    if (!kDebugMode) return;

    await close();

    final docsDir = await getApplicationDocumentsDirectory();
    final path = join(docsDir.path, _testDbName);

    try {
      await deleteDatabase(path);
    } catch (_) {
      // Ignorar
    }

    // Crear DB con esquema actual.
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );

    // Asegurar un producto dummy para poder probar "Agregar stock".
    final now = DateTime.now().millisecondsSinceEpoch;
    final productCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${DbTables.products}'),
        ) ??
        0;
    if (productCount == 0) {
      await db.insert(DbTables.products, {
        'code': 'TEST-001',
        'name': 'Producto Test',
        'image_path': null,
        'image_url': null,
        'placeholder_color_hex': ColorUtils.generateDeterministicColorHex(
          'Producto Test',
        ),
        'placeholder_type': 'color',
        'category_id': null,
        'supplier_id': null,
        'purchase_price': 0.0,
        'sale_price': 0.0,
        'stock': 10.0,
        'stock_min': 0.0,
        'is_active': 1,
        'deleted_at_ms': null,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
    }

    // Re-crear stock_movements SIN user_id (simula esquema viejo).
    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE ${DbTables.stockMovements} RENAME TO ${DbTables.stockMovements}__legacy_tmp',
      );

      await txn.execute('''
        CREATE TABLE ${DbTables.stockMovements} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          quantity REAL NOT NULL,
          note TEXT,
          created_at_ms INTEGER NOT NULL,
          FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
        )
      ''');

      await txn.execute('''
        INSERT INTO ${DbTables.stockMovements} (id, product_id, type, quantity, note, created_at_ms)
        SELECT id, product_id, type, quantity, note, created_at_ms
        FROM ${DbTables.stockMovements}__legacy_tmp
      ''');

      await txn.execute('DROP TABLE ${DbTables.stockMovements}__legacy_tmp');

      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_stock_movements_product
        ON ${DbTables.stockMovements}(product_id)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_stock_movements_type
        ON ${DbTables.stockMovements}(type)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_stock_movements_created
        ON ${DbTables.stockMovements}(created_at_ms)
      ''');
    });

    // Insertar un movimiento dummy opcional.
    final productId =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT id FROM ${DbTables.products} ORDER BY id ASC LIMIT 1',
          ),
        ) ??
        1;
    final movementCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${DbTables.stockMovements}'),
        ) ??
        0;
    if (movementCount == 0) {
      await db.insert(DbTables.stockMovements, {
        'product_id': productId,
        'type': 'input',
        'quantity': 1.0,
        'note': 'Legacy dummy',
        'created_at_ms': now,
      });
    }

    // Forzar versión vieja para que onUpgrade corra al reabrir.
    await db.execute('PRAGMA user_version = 20');
    await db.close();
  }

  /// DEBUG: verifica por PRAGMA si existe la columna user_id.
  static Future<bool> verifyStockMovementsColumns() async {
    final db = await database;
    final info = await db.rawQuery(
      'PRAGMA table_info(${DbTables.stockMovements})',
    );
    final columns = info.map((row) => row['name']).whereType<String>().toSet();
    final ok = columns.contains('user_id');
    // ignore: avoid_print
    print(
      ok
          ? 'OK: stock_movements tiene columna user_id'
          : 'ERROR: stock_movements NO tiene columna user_id. Columns=$columns',
    );
    return ok;
  }

  /// DEBUG: diagnóstico general para detectar problemas de esquema/corrupción.
  static Future<Map<String, dynamic>> runDbDiagnostics() async {
    final db = await database;

    final dbList = await db.rawQuery('PRAGMA database_list');
    final dbPath =
        (dbList.isNotEmpty ? (dbList.first['file'] as String?) : null) ?? '';

    final userVersionRow = await db.rawQuery('PRAGMA user_version');
    final userVersion =
        (userVersionRow.isNotEmpty
            ? (userVersionRow.first['user_version'] as int?)
            : null) ??
        -1;

    String integrity = 'unknown';
    try {
      final res = await db.rawQuery('PRAGMA integrity_check');
      integrity =
          (res.isNotEmpty ? (res.first.values.first as String?) : null) ??
          'unknown';
    } catch (e) {
      integrity = 'error: $e';
    }

    int fkIssuesCount = 0;
    try {
      final fk = await db.rawQuery('PRAGMA foreign_key_check');
      fkIssuesCount = fk.length;
    } catch (_) {
      fkIssuesCount = -1;
    }

    int foreignKeysEnabled = 0;
    try {
      final fkOn = await db.rawQuery('PRAGMA foreign_keys');
      foreignKeysEnabled =
          (fkOn.isNotEmpty ? (fkOn.first.values.first as int?) : null) ?? 0;
    } catch (_) {
      foreignKeysEnabled = -1;
    }

    final missingTables = <String>{};
    final missingColumns = <String>{};
    final warnings = <String>[];

    Future<void> requireColumn(String table, String column) async {
      if (!await _tableExists(db, table)) {
        missingTables.add(table);
        return;
      }
      final cols = await _getTableColumns(db, table);
      if (!cols.contains(column)) missingColumns.add('$table.$column');
    }

    final allTables = <String>[
      DbTables.appConfig,
      DbTables.clients,
      DbTables.categories,
      DbTables.suppliers,
      DbTables.products,
      DbTables.stockMovements,
      DbTables.purchaseOrders,
      DbTables.purchaseOrderItems,
      DbTables.sales,
      DbTables.saleItems,
      DbTables.returns,
      DbTables.returnItems,
      DbTables.businessInfo,
      DbTables.appSettings,
      DbTables.ncfBooks,
      DbTables.customersNcfUsage,
      DbTables.users,
      DbTables.cashSessions,
      DbTables.cashMovements,
      DbTables.posTickets,
      DbTables.posTicketItems,
      DbTables.tempCarts,
      DbTables.tempCartItems,
      DbTables.quotes,
      DbTables.quoteItems,
      DbTables.printerSettings,
      DbTables.creditPayments,
      DbTables.layawayPayments,
      DbTables.companies,
      DbTables.terminals,
      DbTables.userPermissions,
      DbTables.overrideTokens,
      DbTables.overrideRequests,
      DbTables.auditLog,
      DbTables.backupHistory,
      DbTables.dangerActionsLog,
      DbTables.pawn,
      DbTables.services,
    ];

    int existingTablesCount = 0;
    for (final t in allTables) {
      if (await _tableExists(db, t)) {
        existingTablesCount++;
      } else {
        missingTables.add(t);
      }
    }

    // Columnas críticas (para evitar errores como el de stock).
    await requireColumn(DbTables.stockMovements, 'user_id');
    await requireColumn(DbTables.stockMovements, 'product_id');
    await requireColumn(DbTables.stockMovements, 'type');
    await requireColumn(DbTables.stockMovements, 'quantity');
    await requireColumn(DbTables.stockMovements, 'created_at_ms');
    await requireColumn(DbTables.products, 'reserved_stock');
    await requireColumn(DbTables.users, 'company_id');
    await requireColumn(DbTables.overrideTokens, 'token_hash');
    await requireColumn(DbTables.overrideTokens, 'company_id');
    await requireColumn(DbTables.auditLog, 'company_id');

    if (userVersion != -1 && userVersion < _dbVersion) {
      warnings.add(
        'DB user_version=$userVersion < app_version=$_dbVersion (migración pendiente)',
      );
    }
    if (foreignKeysEnabled == 0) {
      warnings.add('PRAGMA foreign_keys=OFF (recomendado ON)');
    }

    final ok =
        integrity.trim().toLowerCase() == 'ok' &&
        missingTables.isEmpty &&
        missingColumns.isEmpty &&
        (fkIssuesCount == 0 || fkIssuesCount == -1);

    // ignore: avoid_print
    print(
      'DB DIAGNOSTICS ok=$ok file=$dbFileName user_version=$userVersion path=$dbPath integrity=$integrity foreign_keys=$foreignKeysEnabled fk_issues=$fkIssuesCount tables=$existingTablesCount/${allTables.length} missing_tables=$missingTables missing_columns=$missingColumns warnings=$warnings',
    );

    return {
      'ok': ok,
      'dbFile': dbFileName,
      'dbPath': dbPath,
      'userVersion': userVersion,
      'appVersion': _dbVersion,
      'integrity': integrity,
      'foreignKeysEnabled': foreignKeysEnabled,
      'foreignKeyIssues': fkIssuesCount,
      'tablesExpected': allTables.length,
      'tablesExisting': existingTablesCount,
      'missingTables': missingTables.toList()..sort(),
      'missingColumns': missingColumns.toList()..sort(),
      'warnings': warnings,
    };
  }

  /// Crea las tablas en la primera ejecución
  static Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await _createFullSchema(txn);
      await _syncDemoCatalog(txn);
    });
  }

  /// Maneja actualizaciones de esquema
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await db.transaction((txn) async {
      await _applyUpgrade(txn, oldVersion, newVersion);
    });
  }

  static Future<void> _applyUpgrade(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('DB UPGRADE oldVersion=$oldVersion newVersion=$newVersion');
    }
    if (oldVersion < 2) {
      // Migración de v1 a v2: agregar campos a tabla clients
      await db.execute('''
        ALTER TABLE ${DbTables.clients}
        ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1
      ''');

      await db.execute('''
        ALTER TABLE ${DbTables.clients}
        ADD COLUMN has_credit INTEGER NOT NULL DEFAULT 0
      ''');

      await db.execute('''
        ALTER TABLE ${DbTables.clients}
        ADD COLUMN deleted_at_ms INTEGER
      ''');

      // Crear índices nuevos
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_clients_created_at 
        ON ${DbTables.clients}(created_at_ms)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_clients_is_active 
        ON ${DbTables.clients}(is_active)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_clients_has_credit 
        ON ${DbTables.clients}(has_credit)
      ''');
    }

    if (oldVersion < 3) {
      // Migración de v2 a v3: agregar módulo de productos

      // === Tabla de Categorías ===
      await db.execute('''
        CREATE TABLE ${DbTables.categories} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          deleted_at_ms INTEGER,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_categories_name 
        ON ${DbTables.categories}(name)
      ''');

      await db.execute('''
        CREATE INDEX idx_categories_is_active 
        ON ${DbTables.categories}(is_active)
      ''');

      // === Tabla de Suplidores ===
      await db.execute('''
        CREATE TABLE ${DbTables.suppliers} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          note TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          deleted_at_ms INTEGER,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_suppliers_name 
        ON ${DbTables.suppliers}(name)
      ''');

      await db.execute('''
        CREATE INDEX idx_suppliers_phone 
        ON ${DbTables.suppliers}(phone)
      ''');

      await db.execute('''
        CREATE INDEX idx_suppliers_is_active 
        ON ${DbTables.suppliers}(is_active)
      ''');

      // === Tabla de Productos ===
      await db.execute('''
        CREATE TABLE ${DbTables.products} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT NOT NULL,
          name TEXT NOT NULL,
          image_path TEXT,
          image_url TEXT,
          placeholder_color_hex TEXT,
          placeholder_type TEXT NOT NULL DEFAULT 'image',
          category_id INTEGER,
          supplier_id INTEGER,
          purchase_price REAL NOT NULL DEFAULT 0.0,
          sale_price REAL NOT NULL DEFAULT 0.0,
          stock REAL NOT NULL DEFAULT 0.0,
          reserved_stock REAL NOT NULL DEFAULT 0.0,
          stock_min REAL NOT NULL DEFAULT 0.0,
          is_active INTEGER NOT NULL DEFAULT 1,
          deleted_at_ms INTEGER,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          FOREIGN KEY (category_id) REFERENCES ${DbTables.categories}(id),
          FOREIGN KEY (supplier_id) REFERENCES ${DbTables.suppliers}(id)
        )
      ''');

      await db.execute('''
      CREATE UNIQUE INDEX idx_products_code_active 
      ON ${DbTables.products}(code)
      WHERE deleted_at_ms IS NULL
    ''');

      await db.execute('''
        CREATE INDEX idx_products_name 
        ON ${DbTables.products}(name)
      ''');

      await db.execute('''
        CREATE INDEX idx_products_category 
        ON ${DbTables.products}(category_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_products_supplier 
        ON ${DbTables.products}(supplier_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_products_is_active 
        ON ${DbTables.products}(is_active)
      ''');

      // === Tabla de Movimientos de Stock ===
      await db.execute('''
        CREATE TABLE ${DbTables.stockMovements} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          quantity REAL NOT NULL,
          note TEXT,
          user_id INTEGER,
          created_at_ms INTEGER NOT NULL,
          FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id),
          FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_stock_movements_product 
        ON ${DbTables.stockMovements}(product_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_stock_movements_type 
        ON ${DbTables.stockMovements}(type)
      ''');

      await db.execute('''
        CREATE INDEX idx_stock_movements_created 
        ON ${DbTables.stockMovements}(created_at_ms)
      ''');
    }

    if (oldVersion < 4) {
      // Migración de v3 a v4: Módulo de ventas completo + configuración fiscal

      // === Información del Negocio ===
      await db.execute('''
        CREATE TABLE ${DbTables.businessInfo} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL DEFAULT 'FULLTECH, SRL',
          phone TEXT,
          address TEXT,
          rnc TEXT,
          slogan TEXT,
          updated_at_ms INTEGER NOT NULL
        )
      ''');

      // Insertar datos por defecto
      await db.insert(DbTables.businessInfo, {
        'name': 'FULLTECH, SRL',
        'phone': '',
        'address': '',
        'rnc': '',
        'slogan': 'FULLPOS',
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });

      // === Configuración de la Aplicación ===
      await db.execute('''
        CREATE TABLE ${DbTables.appSettings} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          itbis_enabled_default INTEGER NOT NULL DEFAULT 1,
          fiscal_enabled_default INTEGER NOT NULL DEFAULT 0,
          itbis_rate REAL NOT NULL DEFAULT 0.18,
          ticket_size TEXT NOT NULL DEFAULT '80mm',
          updated_at_ms INTEGER NOT NULL
        )
      ''');

      // Insertar configuración por defecto
      await db.insert(DbTables.appSettings, {
        'itbis_enabled_default': 1,
        'fiscal_enabled_default': 0,
        'itbis_rate': 0.18,
        'ticket_size': '80mm',
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });

      // === Libros de NCF (Talonarios) ===
      await db.execute('''
        CREATE TABLE ${DbTables.ncfBooks} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          series TEXT,
          from_n INTEGER NOT NULL,
          to_n INTEGER NOT NULL,
          next_n INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          expires_at_ms INTEGER,
          note TEXT,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          deleted_at_ms INTEGER
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_ncf_type_active 
        ON ${DbTables.ncfBooks}(type, is_active)
      ''');

      // === Uso de NCF por clientes ===
      await db.execute('''
        CREATE TABLE ${DbTables.customersNcfUsage} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          ncf_book_id INTEGER NOT NULL,
          ncf_full TEXT NOT NULL UNIQUE,
          created_at_ms INTEGER NOT NULL,
          FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
          FOREIGN KEY (ncf_book_id) REFERENCES ${DbTables.ncfBooks}(id)
        )
      ''');

      // === Usuarios ===
      await db.execute('''
        CREATE TABLE ${DbTables.users} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER NOT NULL DEFAULT 1,
          username TEXT NOT NULL,
          pin TEXT,
          role TEXT NOT NULL DEFAULT 'cashier',
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          deleted_at_ms INTEGER
        )
      ''');

      await db.execute('''
        CREATE UNIQUE INDEX idx_users_username_active
        ON ${DbTables.users}(company_id, username)
        WHERE deleted_at_ms IS NULL
      ''');

      // Usuario admin por defecto
      await db.insert(DbTables.users, {
        'company_id': 1,
        'username': 'admin',
        'pin': null,
        'role': 'admin',
        'is_active': 1,
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });

      // === Sesiones de Caja ===
      await db.execute('''
        CREATE TABLE ${DbTables.cashSessions} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          opened_by_user_id INTEGER NOT NULL,
          opened_at_ms INTEGER NOT NULL,
          initial_amount REAL NOT NULL DEFAULT 0,
          closed_at_ms INTEGER,
          closed_by_user_id INTEGER,
          note TEXT,
          FOREIGN KEY (opened_by_user_id) REFERENCES ${DbTables.users}(id),
          FOREIGN KEY (closed_by_user_id) REFERENCES ${DbTables.users}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_cash_session_open 
        ON ${DbTables.cashSessions}(opened_at_ms)
      ''');

      // === Movimientos de Caja ===
      await db.execute('''
        CREATE TABLE ${DbTables.cashMovements} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          note TEXT,
          created_at_ms INTEGER NOT NULL,
          FOREIGN KEY (session_id) REFERENCES ${DbTables.cashSessions}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_cash_movement_session 
        ON ${DbTables.cashMovements}(session_id)
      ''');

      // === Ventas ===
      await db.execute('''
        CREATE TABLE ${DbTables.sales} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          local_code TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'completed',
          customer_id INTEGER,
          customer_name_snapshot TEXT,
          customer_phone_snapshot TEXT,
          customer_rnc_snapshot TEXT,
          itbis_enabled INTEGER NOT NULL DEFAULT 1,
          itbis_rate REAL NOT NULL DEFAULT 0.18,
          discount_total REAL NOT NULL DEFAULT 0,
          subtotal REAL NOT NULL DEFAULT 0,
          itbis_amount REAL NOT NULL DEFAULT 0,
          total REAL NOT NULL DEFAULT 0,
          payment_method TEXT,
          paid_amount REAL NOT NULL DEFAULT 0,
          change_amount REAL NOT NULL DEFAULT 0,
          credit_interest_rate REAL NOT NULL DEFAULT 0,
          credit_term_days INTEGER,
          credit_due_date_ms INTEGER,
          credit_installments INTEGER,
          credit_note TEXT,
          fiscal_enabled INTEGER NOT NULL DEFAULT 0,
          ncf_full TEXT UNIQUE,
          ncf_type TEXT,
          session_id INTEGER,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          deleted_at_ms INTEGER,
          FOREIGN KEY (customer_id) REFERENCES ${DbTables.clients}(id),
          FOREIGN KEY (session_id) REFERENCES ${DbTables.cashSessions}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_sales_created 
        ON ${DbTables.sales}(created_at_ms)
      ''');

      await db.execute('''
        CREATE INDEX idx_sales_kind 
        ON ${DbTables.sales}(kind)
      ''');

      await db.execute('''
        CREATE INDEX idx_sales_customer 
        ON ${DbTables.sales}(customer_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_sales_local_code 
        ON ${DbTables.sales}(local_code)
      ''');

      // === Items de Venta ===
      await db.execute('''
        CREATE TABLE ${DbTables.saleItems} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          product_id INTEGER,
          product_code_snapshot TEXT NOT NULL,
          product_name_snapshot TEXT NOT NULL,
          qty REAL NOT NULL,
          unit_price REAL NOT NULL,
          purchase_price_snapshot REAL NOT NULL DEFAULT 0,
          discount_line REAL NOT NULL DEFAULT 0,
          total_line REAL NOT NULL,
          created_at_ms INTEGER NOT NULL,
          FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
          FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_sale_items_sale 
        ON ${DbTables.saleItems}(sale_id)
      ''');

      // === Devoluciones ===
      await db.execute('''
        CREATE TABLE ${DbTables.returns} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          original_sale_id INTEGER NOT NULL,
          return_sale_id INTEGER NOT NULL,
          note TEXT,
          created_at_ms INTEGER NOT NULL,
          FOREIGN KEY (original_sale_id) REFERENCES ${DbTables.sales}(id),
          FOREIGN KEY (return_sale_id) REFERENCES ${DbTables.sales}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_returns_original 
        ON ${DbTables.returns}(original_sale_id)
      ''');
    }

    if (oldVersion < 6) {
      // Migración de v5 a v6: Tablas de cotizaciones y tickets POS

      // === Tickets POS (carritos pendientes) ===
      await db.execute('''
        CREATE TABLE ${DbTables.posTickets} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ticket_name TEXT NOT NULL,
          user_id INTEGER,
          client_id INTEGER,
          itbis_enabled INTEGER NOT NULL DEFAULT 1,
          itbis_rate REAL NOT NULL DEFAULT 0.18,
          discount_total REAL NOT NULL DEFAULT 0,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
          FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_pos_tickets_user 
        ON ${DbTables.posTickets}(user_id)
      ''');

      // === Items de Tickets POS ===
      await db.execute('''
        CREATE TABLE ${DbTables.posTicketItems} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ticket_id INTEGER NOT NULL,
          product_id INTEGER,
          product_code_snapshot TEXT NOT NULL,
          product_name_snapshot TEXT NOT NULL,
          description TEXT NOT NULL,
          qty REAL NOT NULL,
          price REAL NOT NULL,
          cost REAL NOT NULL DEFAULT 0,
          discount_line REAL NOT NULL DEFAULT 0,
          total_line REAL NOT NULL,
          FOREIGN KEY (ticket_id) REFERENCES ${DbTables.posTickets}(id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_pos_ticket_items_ticket 
        ON ${DbTables.posTicketItems}(ticket_id)
      ''');

      // === Cotizaciones ===
      await db.execute('''
        CREATE TABLE ${DbTables.quotes} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_id INTEGER NOT NULL,
          user_id INTEGER,
          ticket_name TEXT,
          subtotal REAL NOT NULL,
          itbis_enabled INTEGER NOT NULL DEFAULT 1,
          itbis_rate REAL NOT NULL DEFAULT 0.18,
          itbis_amount REAL NOT NULL DEFAULT 0,
          discount_total REAL NOT NULL DEFAULT 0,
          total REAL NOT NULL,
          status TEXT NOT NULL DEFAULT 'OPEN',
          notes TEXT,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
          FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_quotes_client 
        ON ${DbTables.quotes}(client_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_quotes_status 
        ON ${DbTables.quotes}(status)
      ''');

      await db.execute('''
        CREATE INDEX idx_quotes_created 
        ON ${DbTables.quotes}(created_at_ms)
      ''');

      // === Items de Cotizaciones ===
      await db.execute('''
        CREATE TABLE ${DbTables.quoteItems} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quote_id INTEGER NOT NULL,
          product_id INTEGER,
          product_code_snapshot TEXT,
          product_name_snapshot TEXT NOT NULL,
          description TEXT NOT NULL,
          qty REAL NOT NULL,
          unit_price REAL NOT NULL DEFAULT 0,
          price REAL NOT NULL,
          cost REAL NOT NULL DEFAULT 0,
          discount_line REAL NOT NULL DEFAULT 0,
          total_line REAL NOT NULL,
          FOREIGN KEY (quote_id) REFERENCES ${DbTables.quotes}(id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_quote_items_quote 
        ON ${DbTables.quoteItems}(quote_id)
      ''');
    }

    if (oldVersion < 7) {
      // Migración de v6 a v7: Configuración de impresora, pagos de crédito y devoluciones mejoradas

      // === Configuración de Impresora ===
      await db.execute('''
        CREATE TABLE ${DbTables.printerSettings} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          selected_printer_name TEXT,
          paper_width_mm INTEGER NOT NULL DEFAULT 80,
          chars_per_line INTEGER NOT NULL DEFAULT 48,
          auto_print_on_payment INTEGER NOT NULL DEFAULT 0,
          show_itbis INTEGER NOT NULL DEFAULT 1,
          show_ncf INTEGER NOT NULL DEFAULT 1,
          show_cashier INTEGER NOT NULL DEFAULT 1,
          show_client INTEGER NOT NULL DEFAULT 1,
          show_payment_method INTEGER NOT NULL DEFAULT 1,
          show_discounts INTEGER NOT NULL DEFAULT 1,
          show_code INTEGER NOT NULL DEFAULT 1,
          show_datetime INTEGER NOT NULL DEFAULT 1,
          header_business_name TEXT DEFAULT 'FULLPOS',
          header_rnc TEXT,
          header_address TEXT,
          header_phone TEXT,
          footer_message TEXT DEFAULT 'Gracias por su compra',
          warranty_policy TEXT NOT NULL DEFAULT '',
          left_margin INTEGER NOT NULL DEFAULT 0,
          right_margin INTEGER NOT NULL DEFAULT 0,
          auto_cut INTEGER NOT NULL DEFAULT 1,
          section_separator_style TEXT NOT NULL DEFAULT 'single',
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
      ''');

      // Insertar configuración por defecto
      await db.insert(DbTables.printerSettings, {
        'selected_printer_name': null,
        'paper_width_mm': 80,
        'chars_per_line': 48,
        'auto_print_on_payment': 0,
        'show_itbis': 1,
        'show_ncf': 1,
        'show_cashier': 1,
        'show_client': 1,
        'show_payment_method': 1,
        'show_discounts': 1,
        'show_code': 1,
        'show_datetime': 1,
        'header_business_name': 'FULLPOS',
        'header_rnc': '',
        'header_address': '',
        'header_phone': '',
        'footer_message': 'Gracias por su compra',
        'warranty_policy': '',
        'left_margin': 0,
        'right_margin': 0,
        'auto_cut': 1,
        'section_separator_style': 'single',
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });

      // === Pagos de Crédito ===
      await db.execute('''
        CREATE TABLE ${DbTables.creditPayments} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          client_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          method TEXT NOT NULL DEFAULT 'cash',
          note TEXT,
          created_at_ms INTEGER NOT NULL,
          user_id INTEGER,
          FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
          FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
          FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_credit_payments_sale 
        ON ${DbTables.creditPayments}(sale_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_credit_payments_client 
        ON ${DbTables.creditPayments}(client_id)
      ''');

      await db.execute('''
          CREATE INDEX idx_credit_payments_created 
          ON ${DbTables.creditPayments}(created_at_ms)
        ''');

      await db.execute('''
          CREATE TABLE ${DbTables.layawayPayments} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            client_id INTEGER,
            amount REAL NOT NULL,
            method TEXT NOT NULL DEFAULT 'cash',
            note TEXT,
            created_at_ms INTEGER NOT NULL,
            user_id INTEGER,
            FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
            FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
            FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
          )
        ''');

      await db.execute('''
          CREATE INDEX idx_layaway_payments_sale
          ON ${DbTables.layawayPayments}(sale_id)
        ''');

      await db.execute('''
          CREATE INDEX idx_layaway_payments_client
          ON ${DbTables.layawayPayments}(client_id)
        ''');

      await db.execute('''
          CREATE INDEX idx_layaway_payments_created
          ON ${DbTables.layawayPayments}(created_at_ms)
        ''');

      // === Ítems de Devoluciones (detalles de qué se devuelve) ===
      await db.execute('''
        CREATE TABLE ${DbTables.returnItems} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          return_id INTEGER NOT NULL,
          sale_item_id INTEGER,
          product_id INTEGER,
          description TEXT NOT NULL,
          qty REAL NOT NULL,
          price REAL NOT NULL,
          total REAL NOT NULL,
          FOREIGN KEY (return_id) REFERENCES ${DbTables.returns}(id) ON DELETE CASCADE,
          FOREIGN KEY (sale_item_id) REFERENCES ${DbTables.saleItems}(id),
          FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_return_items_return 
        ON ${DbTables.returnItems}(return_id)
      ''');
    }

    if (oldVersion < 8) {
      // Migración de v7 a v8: Mejora completa del módulo de caja

      // Agregar campos faltantes a cash_sessions
      await db.execute('''
        ALTER TABLE ${DbTables.cashSessions}
        ADD COLUMN user_name TEXT NOT NULL DEFAULT 'admin'
      ''');

      await db.execute('''
        ALTER TABLE ${DbTables.cashSessions}
        ADD COLUMN closing_amount REAL
      ''');

      await db.execute('''
        ALTER TABLE ${DbTables.cashSessions}
        ADD COLUMN expected_cash REAL
      ''');

      await db.execute('''
        ALTER TABLE ${DbTables.cashSessions}
        ADD COLUMN difference REAL
      ''');

      await db.execute('''
        ALTER TABLE ${DbTables.cashSessions}
        ADD COLUMN status TEXT NOT NULL DEFAULT 'OPEN'
      ''');

      // Actualizar sesiones existentes cerradas
      await db.execute('''
        UPDATE ${DbTables.cashSessions}
        SET status = 'CLOSED'
        WHERE closed_at_ms IS NOT NULL
      ''');

      // Crear índices adicionales para cash_sessions
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_cash_session_status 
        ON ${DbTables.cashSessions}(status)
      ''');

      // Agregar campos a cash_movements
      await db.execute('''
        ALTER TABLE ${DbTables.cashMovements}
        ADD COLUMN reason TEXT NOT NULL DEFAULT 'Movimiento de caja'
      ''');

      await db.execute('''
        ALTER TABLE ${DbTables.cashMovements}
        ADD COLUMN user_id INTEGER NOT NULL DEFAULT 1
      ''');

      // Crear índice por fecha en cash_movements
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_cash_movement_created 
        ON ${DbTables.cashMovements}(created_at_ms)
      ''');

      // Agregar cash_session_id a sales si no existe (verificar primero)
      // SQLite no tiene IF NOT EXISTS para columnas, usamos PRAGMA
      final salesColumns = await db.rawQuery(
        "PRAGMA table_info(${DbTables.sales})",
      );
      final hasSessionId = salesColumns.any(
        (col) => col['name'] == 'cash_session_id',
      );

      if (!hasSessionId) {
        await db.execute('''
          ALTER TABLE ${DbTables.sales}
          ADD COLUMN cash_session_id INTEGER REFERENCES ${DbTables.cashSessions}(id)
        ''');

        // Copiar session_id a cash_session_id para datos existentes
        await db.execute('''
          UPDATE ${DbTables.sales}
          SET cash_session_id = session_id
          WHERE session_id IS NOT NULL
        ''');
      }

      // Crear índice para cash_session_id en sales
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sales_cash_session 
        ON ${DbTables.sales}(cash_session_id)
      ''');
    }

    if (oldVersion < 9) {
      // Migración v8 a v9: Campos adicionales para impresora

      // Agregar campo copies
      await db.execute('''
        ALTER TABLE ${DbTables.printerSettings}
        ADD COLUMN copies INTEGER NOT NULL DEFAULT 1
      ''');

      // Agregar campo header_extra
      await db.execute('''
        ALTER TABLE ${DbTables.printerSettings}
        ADD COLUMN header_extra TEXT
      ''');

      // Agregar campo itbis_rate
      await db.execute('''
        ALTER TABLE ${DbTables.printerSettings}
        ADD COLUMN itbis_rate REAL NOT NULL DEFAULT 0.18
      ''');
    }

    if (oldVersion < 10) {
      // Migración v9 a v10: Campos adicionales para usuarios

      // Agregar campo display_name
      await db.execute('''
        ALTER TABLE ${DbTables.users}
        ADD COLUMN display_name TEXT
      ''');

      // Agregar campo permissions (JSON string)
      await db.execute('''
        ALTER TABLE ${DbTables.users}
        ADD COLUMN permissions TEXT
      ''');
    }

    if (oldVersion < 11) {
      // Migración v10 a v11: Agregar campo password para autenticación
      await db.execute('''
        ALTER TABLE ${DbTables.users}
        ADD COLUMN password_hash TEXT
      ''');

      // Actualizar usuario admin con password por defecto: admin123
      // Hash SHA256 de "admin123"
      await db.update(
        DbTables.users,
        {
          'password_hash':
              '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
        },
        where: 'username = ?',
        whereArgs: ['admin'],
      );
    }

    if (oldVersion < 12) {
      // Migración v11 a v12: Corregir hash de contraseña del admin
      // El hash anterior era incorrecto, este es el hash correcto de "admin123"
      await db.update(
        DbTables.users,
        {
          'password_hash':
              '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
        },
        where: 'username = ?',
        whereArgs: ['admin'],
      );
    }

    if (oldVersion < 13) {
      await _ensureSchemaIntegrity(db);
    }

    if (oldVersion < 16) {
      await _ensureSchemaIntegrity(db);
    }

    if (oldVersion < 19) {
      try {
        await db.execute('''
          ALTER TABLE ${DbTables.purchaseOrders}
          ADD COLUMN purchase_date_ms INTEGER
        ''');
      } catch (_) {
        // Columna ya existe
      }
    }

    if (oldVersion < 20) {
      try {
        // ignore: avoid_print
        print('Applying migration: add user_id to stock_movements');
        await db.execute('''
          ALTER TABLE ${DbTables.stockMovements}
          ADD COLUMN user_id INTEGER
        ''');
      } catch (_) {
        // Columna ya existe
      }
    }

    // v21: asegurar nuevamente (caso típico: DB creada en v20 sin user_id)
    if (oldVersion < 21) {
      try {
        // ignore: avoid_print
        print('Applying migration: add user_id to stock_movements');
        await db.execute('''
          ALTER TABLE ${DbTables.stockMovements}
          ADD COLUMN user_id INTEGER
        ''');
      } catch (_) {
        // Columna ya existe
      }
    }

    if (oldVersion < 22) {
      await _addColumnIfMissing(db, DbTables.products, 'image_url', 'TEXT');
      await _addColumnIfMissing(
        db,
        DbTables.products,
        'placeholder_color_hex',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.products,
        'placeholder_type',
        "TEXT NOT NULL DEFAULT 'image'",
      );

      try {
        final rows = await db.query(
          DbTables.products,
          columns: [
            'id',
            'name',
            'image_path',
            'image_url',
            'placeholder_color_hex',
            'placeholder_type',
            'category_id',
          ],
        );

        for (final row in rows) {
          final id = row['id'] as int?;
          if (id == null) continue;
          final name = (row['name'] as String? ?? '').trim();
          final imagePath = (row['image_path'] as String? ?? '').trim();
          final imageUrl = (row['image_url'] as String? ?? '').trim();
          final existingColor = (row['placeholder_color_hex'] as String? ?? '')
              .trim();
          final hasImage = imagePath.isNotEmpty || imageUrl.isNotEmpty;
          final categoryId = row['category_id'] as int?;
          final color = existingColor.isNotEmpty
              ? existingColor
              : ColorUtils.generateDeterministicColorHex(
                  name.isEmpty ? 'PRODUCT' : name,
                  categoryId: categoryId,
                );
          final placeholderType = hasImage ? 'image' : 'color';

          await db.update(
            DbTables.products,
            {
              'placeholder_type': placeholderType,
              'placeholder_color_hex': color,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      } catch (_) {
        // No bloquear migraciÃ³n si falla el backfill
      }
    }

    if (oldVersion < 23) {
      await _ensureSecurityTables(db);
    }

    if (oldVersion < 24) {
      await _ensureBackupTables(db);
      await _ensureProductCodeIndex(db);
    }

    if (oldVersion < 25) {
      await _migrateProductsCodeUniqueToPartial(db);
    }

    if (oldVersion < 26) {
      // Idempotente: si la app se cierra a mitad de migración, la columna puede
      // existir aunque user_version siga siendo < 26. Evita "duplicate column".
      await _addColumnIfMissing(
        db,
        DbTables.sales,
        'credit_interest_rate',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.sales,
        'credit_term_days',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbTables.sales,
        'credit_due_date_ms',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbTables.sales,
        'credit_installments',
        'INTEGER',
      );
      await _addColumnIfMissing(db, DbTables.sales, 'credit_note', 'TEXT');
    }

    if (oldVersion < 27) {
      // Idempotente: si la app se cierra a mitad de migración, reserved_stock
      // puede existir aunque user_version siga siendo < 27.
      await _addColumnIfMissing(
        db,
        DbTables.products,
        'reserved_stock',
        'REAL NOT NULL DEFAULT 0.0',
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbTables.layawayPayments} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          client_id INTEGER,
          amount REAL NOT NULL,
          method TEXT NOT NULL DEFAULT 'cash',
          note TEXT,
          created_at_ms INTEGER NOT NULL,
          user_id INTEGER,
          FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
          FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
          FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
        )
      ''');

      await _createIndexIfMissing(
        db,
        'idx_layaway_payments_sale',
        DbTables.layawayPayments,
        'sale_id',
      );
      await _createIndexIfMissing(
        db,
        'idx_layaway_payments_client',
        DbTables.layawayPayments,
        'client_id',
      );
      await _createIndexIfMissing(
        db,
        'idx_layaway_payments_created',
        DbTables.layawayPayments,
        'created_at_ms',
      );
    }

    if (oldVersion < 28) {
      // Migración v28:
      // - Permitir reutilizar usernames de usuarios eliminados (soft delete).
      // - Defensa extra para productos en instalaciones "desalineadas".
      await _migrateUsersUsernameUniqueToPartial(db);
      await _migrateProductsCodeUniqueToPartial(db);
    }

    if (oldVersion < 29) {
      // Migración v29:
      // - Default controlado del switch de NCF (comprobante fiscal) en ventas.
      await _addColumnIfMissing(
        db,
        DbTables.appSettings,
        'fiscal_enabled_default',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }

    // v17+: normalizar esquema siempre que haya upgrade
    if (oldVersion < newVersion) {
      await _ensureSchemaIntegrity(db);
    }
  }

  /// Sincroniza catálogo demo:
  /// - Inserta 10 categorías y 50 productos demo si no hay datos.
  /// - Borra demos cuando existan categorías o productos reales.
  /// - Si se eliminan todos los reales, reaparecen los demos.
  static Future<void> _syncDemoCatalog(DatabaseExecutor db) async {
    final demoCats = (await db.query(
      DbTables.categories,
      columns: ['id', 'name'],
      where:
          'name IN (${List.filled(demoCategoryNames.length, '?').join(',')}) AND deleted_at_ms IS NULL',
      whereArgs: demoCategoryNames,
    )).map((e) => e['id']).whereType<int>().toSet();

    final nonDemoCatsCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${DbTables.categories} WHERE deleted_at_ms IS NULL AND name NOT IN (${List.filled(demoCategoryNames.length, '?').join(',')})',
            demoCategoryNames,
          ),
        ) ??
        0;

    final demoProductsCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM ${DbTables.products} WHERE code LIKE '$demoProductCodePrefix%' AND deleted_at_ms IS NULL",
          ),
        ) ??
        0;

    final nonDemoProductsCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM ${DbTables.products} WHERE code NOT LIKE '$demoProductCodePrefix%' AND deleted_at_ms IS NULL",
          ),
        ) ??
        0;

    // Si hay productos reales, limpiar productos demo.
    if (nonDemoProductsCount > 0 && demoProductsCount > 0) {
      await deleteDemoProducts(db);
    }

    // Si hay categorías reales, limpiar categorías demo.
    if (nonDemoCatsCount > 0 && demoCats.isNotEmpty) {
      await deleteDemoCategories(db);
    }

    // Si no hay productos reales, reactivar demos existentes (si estaban soft-delete).
    if (nonDemoProductsCount == 0) {
      final demoRowsCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM ${DbTables.products} WHERE code LIKE '$demoProductCodePrefix%'",
            ),
          ) ??
          0;
      if (demoRowsCount > 0) {
        await restoreDemoProducts(db);
      }
    }

    // Si no hay categorías reales, reactivar demo categorías existentes.
    if (nonDemoCatsCount == 0) {
      final demoCatRowsCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM ${DbTables.categories} WHERE name IN (${List.filled(demoCategoryNames.length, '?').join(',')})',
              demoCategoryNames,
            ),
          ) ??
          0;
      if (demoCatRowsCount > 0) {
        await restoreDemoCategories(db);
      }
    }

    // Recalcular totales tras limpieza.
    final totalProducts =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${DbTables.products} WHERE deleted_at_ms IS NULL',
          ),
        ) ??
        0;
    final totalCategories =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${DbTables.categories} WHERE deleted_at_ms IS NULL',
          ),
        ) ??
        0;

    // Si no hay categorías (reales o demo), crear las demo.
    final shouldCreateDemoCategories =
        nonDemoCatsCount == 0 && totalCategories == 0;

    // Insertar categorías demo si corresponde.
    final now = DateTime.now().millisecondsSinceEpoch;
    final categoryIds = <String, int>{};
    if (shouldCreateDemoCategories) {
      for (final name in demoCategoryNames) {
        await db.insert(DbTables.categories, {
          'name': name,
          'is_active': 1,
          'deleted_at_ms': null,
          'created_at_ms': now,
          'updated_at_ms': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final rows = await db.query(
          DbTables.categories,
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        if (rows.isNotEmpty && rows.first['id'] != null) {
          categoryIds[name] = rows.first['id'] as int;
        }
      }
    } else {
      // Si hay categorías reales, solo reusar IDs demo existentes si quedan.
      for (final name in demoCategoryNames) {
        final rows = await db.query(
          DbTables.categories,
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        if (rows.isNotEmpty && rows.first['id'] != null) {
          categoryIds[name] = rows.first['id'] as int;
        }
      }
    }

    // Si hay productos reales, no crear productos demo.
    if (totalProducts > 0) {
      return;
    }

    // Insertar productos demo.
    final demos = _demoProducts();
    final batch = db.batch();
    for (var i = 0; i < demos.length; i++) {
      final p = demos[i];
      batch.insert(DbTables.products, {
        'code': p['code'],
        'name': p['name'],
        'image_url': p['imageUrl'],
        'placeholder_type': 'image',
        'placeholder_color_hex': null,
        'category_id': categoryIds[p['category']],
        'supplier_id': null,
        'purchase_price': p['purchasePrice'],
        'sale_price': p['salePrice'],
        'stock': p['stock'],
        'stock_min': p['stockMin'],
        'is_active': 1,
        'deleted_at_ms': null,
        'created_at_ms': now + i,
        'updated_at_ms': now + i,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> deleteDemoProducts(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbTables.products,
      {'deleted_at_ms': now, 'updated_at_ms': now, 'is_active': 0},
      where: "code LIKE '$demoProductCodePrefix%' AND deleted_at_ms IS NULL",
    );
  }

  static Future<void> restoreDemoProducts(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(DbTables.products, {
      'deleted_at_ms': null,
      'updated_at_ms': now,
      'is_active': 1,
    }, where: "code LIKE '$demoProductCodePrefix%'");
  }

  static Future<void> syncDemoCatalog(DatabaseExecutor db) async {
    await _syncDemoCatalog(db);
  }

  static Future<void> deleteDemoCategories(
    DatabaseExecutor db, {
    int? keepCategoryId,
  }) async {
    final where = StringBuffer(
      'name IN (${List.filled(demoCategoryNames.length, '?').join(',')})',
    );
    final args = <dynamic>[...demoCategoryNames];
    if (keepCategoryId != null) {
      where.write(' AND id != ?');
      args.add(keepCategoryId);
    }

    final demoCategoryRows = await db.query(
      DbTables.categories,
      columns: ['id'],
      where: where.toString(),
      whereArgs: args,
    );
    final demoCategoryIds = demoCategoryRows
        .map((row) => row['id'])
        .whereType<int>()
        .toList();

    if (demoCategoryIds.isNotEmpty) {
      final placeholders = List.filled(demoCategoryIds.length, '?').join(',');
      await db.update(
        DbTables.products,
        {'category_id': null},
        where: 'category_id IN ($placeholders)',
        whereArgs: demoCategoryIds,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbTables.categories,
      {'deleted_at_ms': now, 'updated_at_ms': now, 'is_active': 0},
      where: where.toString(),
      whereArgs: args,
    );
  }

  static Future<void> restoreDemoCategories(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbTables.categories,
      {'deleted_at_ms': null, 'updated_at_ms': now, 'is_active': 1},
      where:
          'name IN (${List.filled(demoCategoryNames.length, '?').join(',')})',
      whereArgs: demoCategoryNames,
    );
  }

  /// Catálogo demo de herramientas (50 items) repartido en 10 categorías.
  static List<Map<String, dynamic>> _demoProducts() {
    final base = [
      {
        'name': 'Taladro recargable 20V',
        'purchasePrice': 2200.0,
        'salePrice': 3200.0,
        'stock': 12.0,
        'stockMin': 2.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[0],
        'category': 'Taladros recargables',
      },
      {
        'name': 'Taladro percutor eléctrico 1/2"',
        'purchasePrice': 1800.0,
        'salePrice': 2800.0,
        'stock': 10.0,
        'stockMin': 2.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[1],
        'category': 'Taladros eléctricos',
      },
      {
        'name': 'Caja de herramientas 19"',
        'purchasePrice': 760.0,
        'salePrice': 1150.0,
        'stock': 14.0,
        'stockMin': 2.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[2],
        'category': 'Cajas de herramientas',
      },
      {
        'name': 'Juego de cubos 94 piezas',
        'purchasePrice': 2400.0,
        'salePrice': 3400.0,
        'stock': 8.0,
        'stockMin': 2.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[3],
        'category': 'Juegos de cubos',
      },
      {
        'name': 'Tubo PVC 1" x 3m',
        'purchasePrice': 220.0,
        'salePrice': 420.0,
        'stock': 60.0,
        'stockMin': 10.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[4],
        'category': 'Tubería PVC',
      },
      {
        'name': 'Rollo cable THHN #12 100m',
        'purchasePrice': 3200.0,
        'salePrice': 4300.0,
        'stock': 6.0,
        'stockMin': 2.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[5],
        'category': 'Electricidad',
      },
      {
        'name': 'Llave inglesa plomero 14"',
        'purchasePrice': 480.0,
        'salePrice': 780.0,
        'stock': 20.0,
        'stockMin': 3.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[6],
        'category': 'Plomería',
      },
      {
        'name': 'Cinta métrica 8m',
        'purchasePrice': 250.0,
        'salePrice': 420.0,
        'stock': 40.0,
        'stockMin': 5.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[7],
        'category': 'Medición',
      },
      {
        'name': 'Guantes de trabajo cuero',
        'purchasePrice': 120.0,
        'salePrice': 250.0,
        'stock': 45.0,
        'stockMin': 6.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[8],
        'category': 'Seguridad',
      },
      {
        'name': 'Silicón blanco 280ml',
        'purchasePrice': 140.0,
        'salePrice': 260.0,
        'stock': 70.0,
        'stockMin': 10.0,
        'imageUrl': AppConfig.demoUnsplashImageUrls[9],
        'category': 'Adhesivos y sellantes',
      },
    ];

    final products = <Map<String, dynamic>>[];
    for (var i = 0; i < 50; i++) {
      final b = base[i % base.length];
      final idx = (i + 1).toString().padLeft(3, '0');
      products.add({
        'code': 'DEMO-$idx',
        'name': b['name'],
        'purchasePrice': b['purchasePrice'],
        'salePrice': b['salePrice'],
        'stock': b['stock'],
        'stockMin': b['stockMin'],
        'imageUrl': b['imageUrl'],
        'category': b['category'],
      });
    }
    return products;
  }

  /// Crea todo el esquema en su versión más reciente (v18)
  static Future<void> _createFullSchema(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Configuración de la app
    await db.execute('''
      CREATE TABLE ${DbTables.appConfig} (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    // Clientes
    await db.execute('''
      CREATE TABLE ${DbTables.clients} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        telefono TEXT,
        direccion TEXT,
        rnc TEXT,
        cedula TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        has_credit INTEGER NOT NULL DEFAULT 0,
        deleted_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_clients_telefono 
      ON ${DbTables.clients}(telefono)
    ''');
    await db.execute('''
      CREATE INDEX idx_clients_created_at 
      ON ${DbTables.clients}(created_at_ms)
    ''');
    await db.execute('''
      CREATE INDEX idx_clients_is_active 
      ON ${DbTables.clients}(is_active)
    ''');
    await db.execute('''
      CREATE INDEX idx_clients_has_credit 
      ON ${DbTables.clients}(has_credit)
    ''');

    // Categorías
    await db.execute('''
      CREATE TABLE ${DbTables.categories} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        deleted_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_categories_name 
      ON ${DbTables.categories}(name)
    ''');
    await db.execute('''
      CREATE INDEX idx_categories_is_active 
      ON ${DbTables.categories}(is_active)
    ''');

    // Suplidores
    await db.execute('''
      CREATE TABLE ${DbTables.suppliers} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        note TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        deleted_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_suppliers_name 
      ON ${DbTables.suppliers}(name)
    ''');
    await db.execute('''
      CREATE INDEX idx_suppliers_phone 
      ON ${DbTables.suppliers}(phone)
    ''');
    await db.execute('''
      CREATE INDEX idx_suppliers_is_active 
      ON ${DbTables.suppliers}(is_active)
    ''');

    // Productos
    await db.execute('''
      CREATE TABLE ${DbTables.products} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        image_path TEXT,
        image_url TEXT,
        placeholder_color_hex TEXT,
        placeholder_type TEXT NOT NULL DEFAULT 'image',
        category_id INTEGER,
        supplier_id INTEGER,
        purchase_price REAL NOT NULL DEFAULT 0.0,
        sale_price REAL NOT NULL DEFAULT 0.0,
        stock REAL NOT NULL DEFAULT 0.0,
        reserved_stock REAL NOT NULL DEFAULT 0.0,
        stock_min REAL NOT NULL DEFAULT 0.0,
        is_active INTEGER NOT NULL DEFAULT 1,
        deleted_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY (category_id) REFERENCES ${DbTables.categories}(id),
        FOREIGN KEY (supplier_id) REFERENCES ${DbTables.suppliers}(id)
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_products_code_active 
      ON ${DbTables.products}(code)
      WHERE deleted_at_ms IS NULL
    ''');
    await db.execute('''
      CREATE INDEX idx_products_name 
      ON ${DbTables.products}(name)
    ''');
    await db.execute('''
      CREATE INDEX idx_products_category 
      ON ${DbTables.products}(category_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_products_supplier 
      ON ${DbTables.products}(supplier_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_products_is_active 
      ON ${DbTables.products}(is_active)
    ''');

    // Movimientos de stock
    await db.execute('''
      CREATE TABLE ${DbTables.stockMovements} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        note TEXT,
        user_id INTEGER,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_stock_movements_product 
      ON ${DbTables.stockMovements}(product_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_stock_movements_type 
      ON ${DbTables.stockMovements}(type)
    ''');
    await db.execute('''
      CREATE INDEX idx_stock_movements_created 
      ON ${DbTables.stockMovements}(created_at_ms)
    ''');

    // Compras / Órdenes de compra
    await db.execute('''
      CREATE TABLE ${DbTables.purchaseOrders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDIENTE',
        subtotal REAL NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        is_auto INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        received_at_ms INTEGER,
        purchase_date_ms INTEGER,
        FOREIGN KEY (supplier_id) REFERENCES ${DbTables.suppliers}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_compras_ordenes_supplier
      ON ${DbTables.purchaseOrders}(supplier_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_compras_ordenes_status
      ON ${DbTables.purchaseOrders}(status)
    ''');
    await db.execute('''
      CREATE INDEX idx_compras_ordenes_created
      ON ${DbTables.purchaseOrders}(created_at_ms)
    ''');

    await db.execute('''
      CREATE TABLE ${DbTables.purchaseOrderItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        qty REAL NOT NULL,
        unit_cost REAL NOT NULL,
        total_line REAL NOT NULL,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES ${DbTables.purchaseOrders}(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_compras_detalle_order
      ON ${DbTables.purchaseOrderItems}(order_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_compras_detalle_product
      ON ${DbTables.purchaseOrderItems}(product_id)
    ''');

    // Información del negocio
    await db.execute('''
      CREATE TABLE ${DbTables.businessInfo} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL DEFAULT 'FULLTECH, SRL',
        phone TEXT,
        address TEXT,
        rnc TEXT,
        slogan TEXT,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.insert(DbTables.businessInfo, {
      'name': 'FULLTECH, SRL',
      'phone': '',
      'address': '',
      'rnc': '',
      'slogan': 'FULLPOS',
      'updated_at_ms': now,
    });

    // Configuración de aplicación
    await db.execute('''
      CREATE TABLE ${DbTables.appSettings} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itbis_enabled_default INTEGER NOT NULL DEFAULT 1,
        fiscal_enabled_default INTEGER NOT NULL DEFAULT 0,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        ticket_size TEXT NOT NULL DEFAULT '80mm',
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.insert(DbTables.appSettings, {
      'itbis_enabled_default': 1,
      'fiscal_enabled_default': 0,
      'itbis_rate': 0.18,
      'ticket_size': '80mm',
      'updated_at_ms': now,
    });

    // Libros de NCF
    await db.execute('''
      CREATE TABLE ${DbTables.ncfBooks} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        series TEXT,
        from_n INTEGER NOT NULL,
        to_n INTEGER NOT NULL,
        next_n INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        expires_at_ms INTEGER,
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_ncf_type_active 
      ON ${DbTables.ncfBooks}(type, is_active)
    ''');

    // Usuarios
    await db.execute('''
      CREATE TABLE ${DbTables.users} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL DEFAULT 1,
        username TEXT NOT NULL,
        pin TEXT,
        role TEXT NOT NULL DEFAULT 'cashier',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        display_name TEXT,
        permissions TEXT,
        password_hash TEXT
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_users_username_active
      ON ${DbTables.users}(company_id, username)
      WHERE deleted_at_ms IS NULL
    ''');
    await db.insert(DbTables.users, {
      'company_id': 1,
      'username': 'admin',
      'pin': null,
      'role': 'admin',
      'is_active': 1,
      'display_name': 'Admin',
      'permissions': null,
      'password_hash':
          '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
      'created_at_ms': now,
      'updated_at_ms': now,
      'deleted_at_ms': null,
    });

    // Sesiones de caja
    await db.execute('''
      CREATE TABLE ${DbTables.cashSessions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_by_user_id INTEGER NOT NULL,
        user_name TEXT NOT NULL DEFAULT 'admin',
        opened_at_ms INTEGER NOT NULL,
        initial_amount REAL NOT NULL DEFAULT 0,
        closing_amount REAL,
        expected_cash REAL,
        difference REAL,
        closed_at_ms INTEGER,
        closed_by_user_id INTEGER,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'OPEN',
        FOREIGN KEY (opened_by_user_id) REFERENCES ${DbTables.users}(id),
        FOREIGN KEY (closed_by_user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_cash_session_open 
      ON ${DbTables.cashSessions}(opened_at_ms)
    ''');
    await db.execute('''
      CREATE INDEX idx_cash_session_status 
      ON ${DbTables.cashSessions}(status)
    ''');

    // Movimientos de caja
    await db.execute('''
      CREATE TABLE ${DbTables.cashMovements} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        reason TEXT NOT NULL DEFAULT 'Movimiento de caja',
        user_id INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (session_id) REFERENCES ${DbTables.cashSessions}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_cash_movement_session 
      ON ${DbTables.cashMovements}(session_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_cash_movement_created 
      ON ${DbTables.cashMovements}(created_at_ms)
    ''');

    // Ventas
    await db.execute('''
      CREATE TABLE ${DbTables.sales} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_code TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        customer_id INTEGER,
        customer_name_snapshot TEXT,
        customer_phone_snapshot TEXT,
        customer_rnc_snapshot TEXT,
        itbis_enabled INTEGER NOT NULL DEFAULT 1,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        discount_total REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        itbis_amount REAL NOT NULL DEFAULT 0,
          total REAL NOT NULL DEFAULT 0,
          payment_method TEXT,
          paid_amount REAL NOT NULL DEFAULT 0,
          change_amount REAL NOT NULL DEFAULT 0,
          credit_interest_rate REAL NOT NULL DEFAULT 0,
          credit_term_days INTEGER,
          credit_due_date_ms INTEGER,
          credit_installments INTEGER,
          credit_note TEXT,
          fiscal_enabled INTEGER NOT NULL DEFAULT 0,
          ncf_full TEXT UNIQUE,
          ncf_type TEXT,
        session_id INTEGER,
        cash_session_id INTEGER REFERENCES ${DbTables.cashSessions}(id),
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY (customer_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (session_id) REFERENCES ${DbTables.cashSessions}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_sales_created 
      ON ${DbTables.sales}(created_at_ms)
    ''');
    await db.execute('''
      CREATE INDEX idx_sales_kind 
      ON ${DbTables.sales}(kind)
    ''');
    await db.execute('''
      CREATE INDEX idx_sales_customer 
      ON ${DbTables.sales}(customer_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_sales_local_code 
      ON ${DbTables.sales}(local_code)
    ''');
    await db.execute('''
      CREATE INDEX idx_sales_cash_session 
      ON ${DbTables.sales}(cash_session_id)
    ''');

    // Uso de NCF
    await db.execute('''
      CREATE TABLE ${DbTables.customersNcfUsage} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        ncf_book_id INTEGER NOT NULL,
        ncf_full TEXT NOT NULL UNIQUE,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
        FOREIGN KEY (ncf_book_id) REFERENCES ${DbTables.ncfBooks}(id)
      )
    ''');

    // Items de venta
    await db.execute('''
      CREATE TABLE ${DbTables.saleItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER,
        product_code_snapshot TEXT NOT NULL,
        product_name_snapshot TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        purchase_price_snapshot REAL NOT NULL DEFAULT 0,
        discount_line REAL NOT NULL DEFAULT 0,
        total_line REAL NOT NULL,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_sale_items_sale 
      ON ${DbTables.saleItems}(sale_id)
    ''');

    // Devoluciones
    await db.execute('''
      CREATE TABLE ${DbTables.returns} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_sale_id INTEGER NOT NULL,
        return_sale_id INTEGER NOT NULL,
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (original_sale_id) REFERENCES ${DbTables.sales}(id),
        FOREIGN KEY (return_sale_id) REFERENCES ${DbTables.sales}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_returns_original 
      ON ${DbTables.returns}(original_sale_id)
    ''');

    // Tickets POS
    await db.execute('''
      CREATE TABLE ${DbTables.posTickets} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_name TEXT NOT NULL,
        user_id INTEGER,
        client_id INTEGER,
        itbis_enabled INTEGER NOT NULL DEFAULT 1,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        discount_total REAL NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_pos_tickets_user 
      ON ${DbTables.posTickets}(user_id)
    ''');

    await db.execute('''
      CREATE TABLE ${DbTables.posTicketItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_id INTEGER NOT NULL,
        product_id INTEGER,
        product_code_snapshot TEXT NOT NULL,
        product_name_snapshot TEXT NOT NULL,
        description TEXT NOT NULL,
        qty REAL NOT NULL,
        price REAL NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        discount_line REAL NOT NULL DEFAULT 0,
        total_line REAL NOT NULL,
        FOREIGN KEY (ticket_id) REFERENCES ${DbTables.posTickets}(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_pos_ticket_items_ticket 
      ON ${DbTables.posTicketItems}(ticket_id)
    ''');

    // Carritos temporales
    await db.execute('''
      CREATE TABLE ${DbTables.tempCarts} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        user_id INTEGER,
        client_id INTEGER,
        discount REAL NOT NULL DEFAULT 0,
        itbis_enabled INTEGER NOT NULL DEFAULT 1,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        fiscal_enabled INTEGER NOT NULL DEFAULT 0,
        discount_total_type TEXT,
        discount_total_value REAL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbTables.tempCartItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cart_id INTEGER NOT NULL,
        product_id INTEGER,
        product_code_snapshot TEXT NOT NULL,
        product_name_snapshot TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        purchase_price_snapshot REAL NOT NULL DEFAULT 0,
        discount_line REAL NOT NULL DEFAULT 0,
        total_line REAL NOT NULL,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (cart_id) REFERENCES ${DbTables.tempCarts}(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_temp_cart_items_cart
      ON ${DbTables.tempCartItems}(cart_id)
    ''');

    // Cotizaciones
    await db.execute('''
      CREATE TABLE ${DbTables.quotes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER NOT NULL,
        user_id INTEGER,
        ticket_name TEXT,
        subtotal REAL NOT NULL,
        itbis_enabled INTEGER NOT NULL DEFAULT 1,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        itbis_amount REAL NOT NULL DEFAULT 0,
        discount_total REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'OPEN',
        notes TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_quotes_client 
      ON ${DbTables.quotes}(client_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_quotes_status 
      ON ${DbTables.quotes}(status)
    ''');
    await db.execute('''
      CREATE INDEX idx_quotes_created 
      ON ${DbTables.quotes}(created_at_ms)
    ''');

    await db.execute('''
      CREATE TABLE ${DbTables.quoteItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quote_id INTEGER NOT NULL,
        product_id INTEGER,
        product_code_snapshot TEXT,
        product_name_snapshot TEXT NOT NULL,
        description TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        price REAL NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        discount_line REAL NOT NULL DEFAULT 0,
        total_line REAL NOT NULL,
        FOREIGN KEY (quote_id) REFERENCES ${DbTables.quotes}(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_quote_items_quote 
      ON ${DbTables.quoteItems}(quote_id)
    ''');

    // Configuración de impresora
    await db.execute('''
      CREATE TABLE ${DbTables.printerSettings} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        selected_printer_name TEXT,
        printer_name TEXT NOT NULL DEFAULT '',
        paper_width_mm INTEGER NOT NULL DEFAULT 80,
        chars_per_line INTEGER NOT NULL DEFAULT 48,
        auto_print_on_payment INTEGER NOT NULL DEFAULT 0,
        show_itbis INTEGER NOT NULL DEFAULT 1,
        show_ncf INTEGER NOT NULL DEFAULT 1,
        show_cashier INTEGER NOT NULL DEFAULT 1,
        show_client INTEGER NOT NULL DEFAULT 1,
        show_payment_method INTEGER NOT NULL DEFAULT 1,
        show_discounts INTEGER NOT NULL DEFAULT 1,
        show_code INTEGER NOT NULL DEFAULT 1,
        show_datetime INTEGER NOT NULL DEFAULT 1,
        header_business_name TEXT DEFAULT 'FULLPOS',
        header_rnc TEXT,
        header_address TEXT,
        header_phone TEXT,
        footer_message TEXT DEFAULT 'Gracias por su compra',
        warranty_policy TEXT NOT NULL DEFAULT '',
        left_margin INTEGER NOT NULL DEFAULT 0,
        right_margin INTEGER NOT NULL DEFAULT 0,
        auto_cut INTEGER NOT NULL DEFAULT 1,
        copies INTEGER NOT NULL DEFAULT 1,
        header_extra TEXT,
        section_separator_style TEXT NOT NULL DEFAULT 'single',
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.insert(DbTables.printerSettings, {
      'selected_printer_name': null,
      'printer_name': '',
      'paper_width_mm': 80,
      'chars_per_line': 48,
      'auto_print_on_payment': 0,
      'show_itbis': 1,
      'show_ncf': 1,
      'show_cashier': 1,
      'show_client': 1,
      'show_payment_method': 1,
      'show_discounts': 1,
      'show_code': 1,
      'show_datetime': 1,
      'header_business_name': 'FULLPOS',
      'header_rnc': '',
      'header_address': '',
      'header_phone': '',
      'footer_message': 'Gracias por su compra',
      'warranty_policy': '',
      'left_margin': 0,
      'right_margin': 0,
      'auto_cut': 1,
      'copies': 1,
      'header_extra': null,
      'section_separator_style': 'single',
      'itbis_rate': 0.18,
      'created_at_ms': now,
      'updated_at_ms': now,
    });

    // Pagos de crédito
    await db.execute('''
      CREATE TABLE ${DbTables.creditPayments} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        client_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL DEFAULT 'cash',
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        user_id INTEGER,
        FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
        FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_credit_payments_sale 
      ON ${DbTables.creditPayments}(sale_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_credit_payments_client 
      ON ${DbTables.creditPayments}(client_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_credit_payments_created 
      ON ${DbTables.creditPayments}(created_at_ms)
    ''');

    // Ítems de devoluciones
    await db.execute('''
      CREATE TABLE ${DbTables.returnItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        sale_item_id INTEGER,
        product_id INTEGER,
        description TEXT NOT NULL,
        qty REAL NOT NULL,
        price REAL NOT NULL,
        total REAL NOT NULL,
        FOREIGN KEY (return_id) REFERENCES ${DbTables.returns}(id) ON DELETE CASCADE,
        FOREIGN KEY (sale_item_id) REFERENCES ${DbTables.saleItems}(id),
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_return_items_return 
      ON ${DbTables.returnItems}(return_id)
    ''');

    await _ensureSecurityTables(db);
    await _ensureBackupTables(db);
  }

  static Future<void> _ensureSecurityTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.companies} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        rnc TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_name
      ON ${DbTables.companies}(LOWER(name))
    ''');
    final companiesCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${DbTables.companies}'),
        ) ??
        0;
    if (companiesCount == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(DbTables.companies, {
        'name': 'EMPRESA PRINCIPAL',
        'rnc': null,
        'is_active': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.terminals} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        name TEXT,
        last_seen_ms INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        UNIQUE(device_id),
        FOREIGN KEY (company_id) REFERENCES ${DbTables.companies}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.userPermissions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        action_code TEXT NOT NULL,
        allowed INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        UNIQUE (company_id, user_id, action_code),
        FOREIGN KEY (company_id) REFERENCES ${DbTables.companies}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_permissions_user
      ON ${DbTables.userPermissions}(user_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.overrideTokens} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        action_code TEXT NOT NULL,
        resource_type TEXT,
        resource_id TEXT,
        token_hash TEXT NOT NULL,
        payload_signature TEXT,
        method TEXT NOT NULL,
        nonce TEXT NOT NULL,
        requested_by_user_id INTEGER NOT NULL,
        approved_by_user_id INTEGER,
        terminal_id TEXT,
        expires_at_ms INTEGER NOT NULL,
        used_at_ms INTEGER,
        used_by_user_id INTEGER,
        result TEXT,
        meta TEXT,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (company_id) REFERENCES ${DbTables.companies}(id),
        FOREIGN KEY (requested_by_user_id) REFERENCES ${DbTables.users}(id),
        FOREIGN KEY (approved_by_user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_override_tokens_company
      ON ${DbTables.overrideTokens}(company_id, action_code, expires_at_ms)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.overrideRequests} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        action_code TEXT NOT NULL,
        resource_type TEXT,
        resource_id TEXT,
        requested_by_user_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        terminal_id TEXT,
        approved_by_user_id INTEGER,
        token_hash TEXT,
        expires_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        resolved_at_ms INTEGER,
        meta TEXT,
        FOREIGN KEY (company_id) REFERENCES ${DbTables.companies}(id),
        FOREIGN KEY (requested_by_user_id) REFERENCES ${DbTables.users}(id),
        FOREIGN KEY (approved_by_user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_override_requests_company
      ON ${DbTables.overrideRequests}(company_id, status)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.auditLog} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        action_code TEXT NOT NULL,
        resource_type TEXT,
        resource_id TEXT,
        requested_by_user_id INTEGER,
        approved_by_user_id INTEGER,
        method TEXT,
        result TEXT NOT NULL,
        terminal_id TEXT,
        meta TEXT,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (company_id) REFERENCES ${DbTables.companies}(id),
        FOREIGN KEY (requested_by_user_id) REFERENCES ${DbTables.users}(id),
        FOREIGN KEY (approved_by_user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_audit_company_action
      ON ${DbTables.auditLog}(company_id, action_code, created_at_ms)
    ''');
  }

  static Future<void> _ensureBackupTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.backupHistory} (
        id TEXT PRIMARY KEY,
        empresa_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        mode TEXT NOT NULL,
        status TEXT NOT NULL,
        file_path TEXT,
        cloud_backup_id TEXT,
        size_bytes INTEGER,
        checksum_sha256 TEXT,
        db_version INTEGER NOT NULL,
        app_version TEXT NOT NULL,
        notes TEXT,
        error_message TEXT,
        device_id TEXT,
        usuario_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_backup_history_empresa
      ON ${DbTables.backupHistory}(empresa_id, created_at)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.dangerActionsLog} (
        id TEXT PRIMARY KEY,
        empresa_id TEXT NOT NULL,
        usuario_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        confirmed_by_phrase TEXT NOT NULL,
        result TEXT NOT NULL,
        error_message TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_danger_actions_empresa
      ON ${DbTables.dangerActionsLog}(empresa_id, created_at)
    ''');
  }

  static Future<void> _ensureProductCodeIndex(DatabaseExecutor db) async {
    try {
      await db.execute('DROP INDEX IF EXISTS idx_products_code');
    } catch (_) {
      // Ignore
    }
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_products_code_active
      ON ${DbTables.products}(code)
      WHERE deleted_at_ms IS NULL
    ''');
  }

  static Future<void> _ensureUsersUsernameIndex(DatabaseExecutor db) async {
    // Único entre usuarios activos (soft delete): (company_id, username)
    // donde deleted_at_ms IS NULL.
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_active
      ON ${DbTables.users}(company_id, username)
      WHERE deleted_at_ms IS NULL
    ''');
  }

  /// Migración v28: permitir reutilizar usernames de usuarios eliminados.
  ///
  /// Históricamente, `users.username` tenía `UNIQUE` a nivel de columna, lo cual
  /// impedía crear un usuario con el mismo username después de un soft delete.
  ///
  /// Esta migración reconstruye `users` SIN el `UNIQUE` de columna y crea el
  /// índice único parcial `idx_users_username_active`.
  static Future<void> _migrateUsersUsernameUniqueToPartial(
    DatabaseExecutor db,
  ) async {
    if (db is! Database) return;
    final database = db;

    if (!await _tableExists(database, DbTables.users)) return;

    await database.execute('PRAGMA foreign_keys = OFF;');
    try {
      await database.transaction((txn) async {
        // Si ya no existe el autoindex del UNIQUE de columna, asumimos migrado.
        try {
          final autoIdx = await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='sqlite_autoindex_users_1'",
          );
          if (autoIdx.isEmpty) {
            // En instalaciones antiguas puede faltar company_id; lo agregamos antes de indexar.
            try {
              await _addColumnIfMissing(
                txn,
                DbTables.users,
                'company_id',
                'INTEGER NOT NULL DEFAULT 1',
              );
            } catch (_) {
              // Ignorar
            }
            await _ensureUsersUsernameIndex(txn);
            return;
          }
        } catch (_) {
          // Si falla detección, seguimos con reconstrucción.
        }

        // Limpiar índices por si existen.
        try {
          await txn.execute('DROP INDEX IF EXISTS idx_users_username_active');
        } catch (_) {}

        const legacyTable = 'users__legacy_v28';
        await txn.execute(
          'ALTER TABLE ${DbTables.users} RENAME TO $legacyTable',
        );

        final legacyCols = await _getTableColumns(txn, legacyTable);
        final now = DateTime.now().millisecondsSinceEpoch;

        await txn.execute('''
          CREATE TABLE ${DbTables.users} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER NOT NULL DEFAULT 1,
            username TEXT NOT NULL,
            pin TEXT,
            role TEXT NOT NULL DEFAULT 'cashier',
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            deleted_at_ms INTEGER,
            display_name TEXT,
            permissions TEXT,
            password_hash TEXT
          )
        ''');

        String colOrDefault(String col, String def) =>
            legacyCols.contains(col) ? col : def;

        await txn.execute('''
          INSERT INTO ${DbTables.users} (
            id,
            company_id,
            username,
            pin,
            role,
            is_active,
            created_at_ms,
            updated_at_ms,
            deleted_at_ms,
            display_name,
            permissions,
            password_hash
          )
          SELECT
            ${colOrDefault('id', 'NULL')},
            ${colOrDefault('company_id', '1')},
            ${colOrDefault('username', "''")},
            ${colOrDefault('pin', 'NULL')},
            ${colOrDefault('role', "'cashier'")},
            ${colOrDefault('is_active', '1')},
            ${colOrDefault('created_at_ms', '$now')},
            ${colOrDefault('updated_at_ms', '$now')},
            ${colOrDefault('deleted_at_ms', 'NULL')},
            ${colOrDefault('display_name', 'NULL')},
            ${colOrDefault('permissions', 'NULL')},
            ${colOrDefault('password_hash', 'NULL')}
          FROM $legacyTable
        ''');

        await txn.execute('DROP TABLE $legacyTable');

        // Normalizar usernames (lowercase + trim) para consistencia.
        try {
          await txn.execute('''
            UPDATE ${DbTables.users}
            SET username = LOWER(TRIM(username))
          ''');
        } catch (_) {
          // Ignorar
        }

        // Resolver duplicados activos (si quedaron por normalización)
        // manteniendo el menor id como canonical y soft-delete al resto.
        try {
          final dups = await txn.rawQuery('''
            SELECT company_id, username, MIN(id) AS keep_id, COUNT(*) AS c
            FROM ${DbTables.users}
            WHERE deleted_at_ms IS NULL
            GROUP BY company_id, username
            HAVING c > 1
          ''');
          for (final row in dups) {
            final companyId = row['company_id'] as int? ?? 1;
            final username = (row['username'] as String?) ?? '';
            final keepId = row['keep_id'] as int?;
            if (keepId == null || username.trim().isEmpty) continue;
            await txn.update(
              DbTables.users,
              {'deleted_at_ms': now, 'is_active': 0, 'updated_at_ms': now},
              where:
                  'company_id = ? AND username = ? AND deleted_at_ms IS NULL AND id != ?',
              whereArgs: [companyId, username, keepId],
            );
          }
        } catch (_) {
          // Ignorar
        }

        await _ensureUsersUsernameIndex(txn);
      });
    } finally {
      try {
        await database.execute('PRAGMA foreign_keys = ON;');
      } catch (_) {}
    }
  }

  /// Migración v25: permitir reutilizar códigos de productos eliminados.
  ///
  /// Históricamente, `products.code` tenía `UNIQUE` a nivel de columna, lo cual
  /// impedía crear un producto con el mismo código después de un soft delete.
  ///
  /// Esta migración reconstruye la tabla `products` SIN el `UNIQUE` de columna y
  /// mantiene la unicidad solo para registros activos con el índice parcial
  /// `idx_products_code_active` (WHERE deleted_at_ms IS NULL).
  static Future<void> _migrateProductsCodeUniqueToPartial(
    DatabaseExecutor db,
  ) async {
    // Esta migración requiere operaciones DDL (rename/recreate). Aseguramos tener Database.
    if (db is! Database) return;
    final database = db;

    if (!await _tableExists(database, DbTables.products)) return;

    const indexNames = <String>[
      'idx_products_code_active',
      'idx_products_name',
      'idx_products_category',
      'idx_products_supplier',
      'idx_products_is_active',
      'idx_products_code',
    ];

    await database.execute('PRAGMA foreign_keys = OFF;');
    try {
      await database.transaction((txn) async {
        for (final idx in indexNames) {
          try {
            await txn.execute('DROP INDEX IF EXISTS $idx');
          } catch (_) {
            // Ignorar
          }
        }

        // Si ya no existe el autoindex del UNIQUE de columna, asumimos que ya está migrado.
        try {
          final autoIdx = await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='sqlite_autoindex_products_1'",
          );
          if (autoIdx.isEmpty) {
            await _ensureProductCodeIndex(txn);
            await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_name ON ${DbTables.products}(name)',
            );
            await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_category ON ${DbTables.products}(category_id)',
            );
            await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_supplier ON ${DbTables.products}(supplier_id)',
            );
            await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_is_active ON ${DbTables.products}(is_active)',
            );
            return;
          }
        } catch (_) {
          // Si falla detección, seguimos con reconstrucción.
        }

        const legacyTable = 'products__legacy_v25';
        await txn.execute(
          'ALTER TABLE ${DbTables.products} RENAME TO $legacyTable',
        );

        await txn.execute('''
          CREATE TABLE ${DbTables.products} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            name TEXT NOT NULL,
            image_path TEXT,
            image_url TEXT,
            placeholder_color_hex TEXT,
            placeholder_type TEXT NOT NULL DEFAULT 'image',
            category_id INTEGER,
            supplier_id INTEGER,
            purchase_price REAL NOT NULL DEFAULT 0.0,
            sale_price REAL NOT NULL DEFAULT 0.0,
            stock REAL NOT NULL DEFAULT 0.0,
            reserved_stock REAL NOT NULL DEFAULT 0.0,
            stock_min REAL NOT NULL DEFAULT 0.0,
            is_active INTEGER NOT NULL DEFAULT 1,
            deleted_at_ms INTEGER,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            FOREIGN KEY (category_id) REFERENCES ${DbTables.categories}(id),
            FOREIGN KEY (supplier_id) REFERENCES ${DbTables.suppliers}(id)
          )
        ''');

        final legacyCols = await txn.rawQuery(
          'PRAGMA table_info($legacyTable)',
        );
        final legacyNames = <String>{
          for (final c in legacyCols)
            if (c['name'] is String) (c['name'] as String),
        };

        String colOrDefault(String col, String defaultSql) {
          return legacyNames.contains(col) ? col : defaultSql;
        }

        final now = DateTime.now().millisecondsSinceEpoch;

        await txn.execute('''
          INSERT INTO ${DbTables.products} (
            id,
            code,
            name,
            image_path,
            image_url,
            placeholder_color_hex,
            placeholder_type,
            category_id,
            supplier_id,
            purchase_price,
            sale_price,
            stock,
            reserved_stock,
            stock_min,
            is_active,
            deleted_at_ms,
            created_at_ms,
            updated_at_ms
          )
          SELECT
            ${colOrDefault('id', 'NULL')},
            ${colOrDefault('code', "''")},
            ${colOrDefault('name', "''")},
            ${colOrDefault('image_path', 'NULL')},
            ${colOrDefault('image_url', 'NULL')},
            ${colOrDefault('placeholder_color_hex', 'NULL')},
            ${colOrDefault('placeholder_type', "'image'")},
            ${colOrDefault('category_id', 'NULL')},
            ${colOrDefault('supplier_id', 'NULL')},
            ${colOrDefault('purchase_price', '0.0')},
            ${colOrDefault('sale_price', '0.0')},
            ${colOrDefault('stock', '0.0')},
            ${colOrDefault('reserved_stock', '0.0')},
            ${colOrDefault('stock_min', '0.0')},
            ${colOrDefault('is_active', '1')},
            ${colOrDefault('deleted_at_ms', 'NULL')},
            ${colOrDefault('created_at_ms', '$now')},
            ${colOrDefault('updated_at_ms', '$now')}
          FROM $legacyTable
        ''');

        await txn.execute('DROP TABLE $legacyTable');

        await _ensureProductCodeIndex(txn);
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_name ON ${DbTables.products}(name)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_category ON ${DbTables.products}(category_id)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_supplier ON ${DbTables.products}(supplier_id)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_is_active ON ${DbTables.products}(is_active)',
        );
      });
    } finally {
      try {
        await database.execute('PRAGMA foreign_keys = ON;');
      } catch (_) {
        // Ignorar
      }
    }
  }

  /// Normaliza tablas y columnas clave en bases existentes
  static Future<void> ensureSchema(DatabaseExecutor db) =>
      _ensureSchemaIntegrity(db);

  static Future<void> _ensureSchemaIntegrity(DatabaseExecutor db) async {
    await _ensureSecurityTables(db);
    await _ensureBackupTables(db);
    await _ensureProductCodeIndex(db);
    // Crear tablas críticas si faltan
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.users} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL DEFAULT 1,
        username TEXT NOT NULL,
        pin TEXT,
        role TEXT NOT NULL DEFAULT 'cashier',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        display_name TEXT,
        permissions TEXT,
        password_hash TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.cashSessions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_by_user_id INTEGER NOT NULL,
        user_name TEXT NOT NULL DEFAULT 'admin',
        opened_at_ms INTEGER NOT NULL,
        initial_amount REAL NOT NULL DEFAULT 0,
        closing_amount REAL,
        expected_cash REAL,
        difference REAL,
        closed_at_ms INTEGER,
        closed_by_user_id INTEGER,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'OPEN',
        FOREIGN KEY (opened_by_user_id) REFERENCES ${DbTables.users}(id),
        FOREIGN KEY (closed_by_user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.cashMovements} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        reason TEXT NOT NULL DEFAULT 'Movimiento de caja',
        user_id INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (session_id) REFERENCES ${DbTables.cashSessions}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.sales} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_code TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        customer_id INTEGER,
        customer_name_snapshot TEXT,
        customer_phone_snapshot TEXT,
        customer_rnc_snapshot TEXT,
        itbis_enabled INTEGER NOT NULL DEFAULT 1,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        discount_total REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        itbis_amount REAL NOT NULL DEFAULT 0,
          total REAL NOT NULL DEFAULT 0,
          payment_method TEXT,
          paid_amount REAL NOT NULL DEFAULT 0,
          change_amount REAL NOT NULL DEFAULT 0,
          credit_interest_rate REAL NOT NULL DEFAULT 0,
          credit_term_days INTEGER,
          credit_due_date_ms INTEGER,
          credit_installments INTEGER,
          credit_note TEXT,
          fiscal_enabled INTEGER NOT NULL DEFAULT 0,
          ncf_full TEXT UNIQUE,
          ncf_type TEXT,
        session_id INTEGER,
        cash_session_id INTEGER REFERENCES ${DbTables.cashSessions}(id),
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY (customer_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (session_id) REFERENCES ${DbTables.cashSessions}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.printerSettings} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        selected_printer_name TEXT,
        paper_width_mm INTEGER NOT NULL DEFAULT 80,
        chars_per_line INTEGER NOT NULL DEFAULT 48,
        auto_print_on_payment INTEGER NOT NULL DEFAULT 0,
        show_itbis INTEGER NOT NULL DEFAULT 1,
        show_ncf INTEGER NOT NULL DEFAULT 1,
        show_cashier INTEGER NOT NULL DEFAULT 1,
        show_client INTEGER NOT NULL DEFAULT 1,
        show_payment_method INTEGER NOT NULL DEFAULT 1,
        show_discounts INTEGER NOT NULL DEFAULT 1,
        show_code INTEGER NOT NULL DEFAULT 1,
        show_datetime INTEGER NOT NULL DEFAULT 1,
        header_business_name TEXT DEFAULT 'FULLPOS',
        header_rnc TEXT,
        header_address TEXT,
        header_phone TEXT,
        footer_message TEXT DEFAULT 'Gracias por su compra',
        left_margin INTEGER NOT NULL DEFAULT 0,
        right_margin INTEGER NOT NULL DEFAULT 0,
        auto_cut INTEGER NOT NULL DEFAULT 1,
        copies INTEGER NOT NULL DEFAULT 1,
        header_extra TEXT,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.creditPayments} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        client_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL DEFAULT 'cash',
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        user_id INTEGER,
        FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
        FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await _createIndexIfMissing(
      db,
      'idx_credit_payments_sale',
      DbTables.creditPayments,
      'sale_id',
    );
    await _createIndexIfMissing(
      db,
      'idx_credit_payments_client',
      DbTables.creditPayments,
      'client_id',
    );
    await _createIndexIfMissing(
      db,
      'idx_credit_payments_created',
      DbTables.creditPayments,
      'created_at_ms',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.layawayPayments} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        client_id INTEGER,
        amount REAL NOT NULL,
        method TEXT NOT NULL DEFAULT 'cash',
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        user_id INTEGER,
        FOREIGN KEY (sale_id) REFERENCES ${DbTables.sales}(id),
        FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');
    await _createIndexIfMissing(
      db,
      'idx_layaway_payments_sale',
      DbTables.layawayPayments,
      'sale_id',
    );
    await _createIndexIfMissing(
      db,
      'idx_layaway_payments_client',
      DbTables.layawayPayments,
      'client_id',
    );
    await _createIndexIfMissing(
      db,
      'idx_layaway_payments_created',
      DbTables.layawayPayments,
      'created_at_ms',
    );

    // Compras / Órdenes de compra (tablas nuevas, no tocan tablas existentes)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.purchaseOrders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDIENTE',
        subtotal REAL NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        is_auto INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        received_at_ms INTEGER,
        purchase_date_ms INTEGER,
        FOREIGN KEY (supplier_id) REFERENCES ${DbTables.suppliers}(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.purchaseOrderItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        qty REAL NOT NULL,
        unit_cost REAL NOT NULL,
        total_line REAL NOT NULL,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES ${DbTables.purchaseOrders}(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');
    await _createIndexIfMissing(
      db,
      'idx_compras_ordenes_supplier',
      DbTables.purchaseOrders,
      'supplier_id',
    );
    await _createIndexIfMissing(
      db,
      'idx_compras_ordenes_status',
      DbTables.purchaseOrders,
      'status',
    );
    await _createIndexIfMissing(
      db,
      'idx_compras_ordenes_created',
      DbTables.purchaseOrders,
      'created_at_ms',
    );
    await _createIndexIfMissing(
      db,
      'idx_compras_detalle_order',
      DbTables.purchaseOrderItems,
      'order_id',
    );
    await _createIndexIfMissing(
      db,
      'idx_compras_detalle_product',
      DbTables.purchaseOrderItems,
      'product_id',
    );

    // cash_sessions
    if (await _tableExists(db, DbTables.cashSessions)) {
      await _addColumnIfMissing(
        db,
        DbTables.cashSessions,
        'user_name',
        "TEXT NOT NULL DEFAULT 'admin'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.cashSessions,
        'closing_amount',
        'REAL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.cashSessions,
        'expected_cash',
        'REAL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.cashSessions,
        'difference',
        'REAL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.cashSessions,
        'status',
        "TEXT NOT NULL DEFAULT 'OPEN'",
      );
      await _createIndexIfMissing(
        db,
        'idx_cash_session_open',
        DbTables.cashSessions,
        'opened_at_ms',
      );
      await _createIndexIfMissing(
        db,
        'idx_cash_session_status',
        DbTables.cashSessions,
        'status',
      );
      await db.execute('''
        UPDATE ${DbTables.cashSessions}
        SET status = 'CLOSED'
        WHERE closed_at_ms IS NOT NULL AND (status IS NULL OR status = '')
      ''');
    }

    // cash_movements
    if (await _tableExists(db, DbTables.cashMovements)) {
      await _addColumnIfMissing(
        db,
        DbTables.cashMovements,
        'reason',
        "TEXT NOT NULL DEFAULT 'Movimiento de caja'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.cashMovements,
        'user_id',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _createIndexIfMissing(
        db,
        'idx_cash_movement_session',
        DbTables.cashMovements,
        'session_id',
      );
      await _createIndexIfMissing(
        db,
        'idx_cash_movement_created',
        DbTables.cashMovements,
        'created_at_ms',
      );
    }

    // sales
    if (await _tableExists(db, DbTables.sales)) {
      final addedCashSessionId = await _addColumnIfMissing(
        db,
        DbTables.sales,
        'cash_session_id',
        'INTEGER REFERENCES ${DbTables.cashSessions}(id)',
      );
      if (addedCashSessionId) {
        await db.execute('''
          UPDATE ${DbTables.sales}
          SET cash_session_id = session_id
          WHERE session_id IS NOT NULL
        ''');
      }
      await _createIndexIfMissing(
        db,
        'idx_sales_cash_session',
        DbTables.sales,
        'cash_session_id',
      );
    }

    // printer_settings
    if (await _tableExists(db, DbTables.printerSettings)) {
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'printer_name',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'selected_printer_name',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'paper_width_mm',
        'INTEGER NOT NULL DEFAULT 80',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'chars_per_line',
        'INTEGER NOT NULL DEFAULT 48',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'auto_print_on_payment',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'auto_open_drawer_on_charge_without_ticket',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_itbis',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_ncf',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_cashier',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_client',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_payment_method',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_discounts',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_code',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_datetime',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'header_business_name',
        "TEXT DEFAULT 'FULLPOS'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'header_rnc',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'header_address',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'header_phone',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'footer_message',
        "TEXT DEFAULT 'Gracias por su compra'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'warranty_policy',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'left_margin',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'right_margin',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'auto_cut',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'copies',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'header_extra',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'itbis_rate',
        'REAL NOT NULL DEFAULT 0.18',
      );
      // === Nuevos campos para estilo de ticket ===
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'font_family',
        "TEXT NOT NULL DEFAULT 'arialBlack'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'font_size',
        "TEXT NOT NULL DEFAULT 'normal'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_logo',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'logo_size',
        'INTEGER NOT NULL DEFAULT 60',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_business_data',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'show_subtotal_itbis_total',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'auto_height',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'top_margin',
        'INTEGER NOT NULL DEFAULT 8',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'bottom_margin',
        'INTEGER NOT NULL DEFAULT 8',
      );
      // === Niveles de espaciado configurables (1-10) ===
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'font_size_level',
        'INTEGER NOT NULL DEFAULT 5',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'line_spacing_level',
        'INTEGER NOT NULL DEFAULT 5',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'section_spacing_level',
        'INTEGER NOT NULL DEFAULT 5',
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'section_separator_style',
        "TEXT NOT NULL DEFAULT 'single'",
      );
      // === Alineación de elementos ===
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'header_alignment',
        "TEXT NOT NULL DEFAULT 'center'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'details_alignment',
        "TEXT NOT NULL DEFAULT 'left'",
      );
      await _addColumnIfMissing(
        db,
        DbTables.printerSettings,
        'totals_alignment',
        "TEXT NOT NULL DEFAULT 'right'",
      );
      final printerRows =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM ${DbTables.printerSettings}',
            ),
          ) ??
          0;
      if (printerRows == 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert(DbTables.printerSettings, {
          'selected_printer_name': null,
          'printer_name': '',
          'paper_width_mm': 80,
          'chars_per_line': 48,
          'auto_print_on_payment': 0,
          'auto_open_drawer_on_charge_without_ticket': 0,
          'show_itbis': 1,
          'show_ncf': 1,
          'show_cashier': 1,
          'show_client': 1,
          'show_payment_method': 1,
          'show_discounts': 1,
          'show_code': 1,
          'show_datetime': 1,
          'header_business_name': 'FULLPOS',
          'header_rnc': '',
          'header_address': '',
          'header_phone': '',
          'footer_message': '¡Gracias por su preferencia!',
          'warranty_policy': '',
          'left_margin': 0,
          'right_margin': 0,
          'auto_cut': 1,
          'copies': 1,
          'header_extra': null,
          'itbis_rate': 0.18,
          // Nuevos campos con plantilla profesional
          'font_family': 'arialBlack',
          'font_size': 'normal',
          'show_logo': 1,
          'logo_size': 60,
          'show_business_data': 1,
          'show_subtotal_itbis_total': 1,
          'auto_height': 1,
          'top_margin': 8,
          'bottom_margin': 8,
          'font_size_level': 5,
          'line_spacing_level': 5,
          'section_spacing_level': 5,
          'section_separator_style': 'single',
          'created_at_ms': now,
          'updated_at_ms': now,
        });
      }
      await db.execute('''
        UPDATE ${DbTables.printerSettings}
        SET printer_name = COALESCE(printer_name, ''),
            copies = COALESCE(copies, 1),
          auto_open_drawer_on_charge_without_ticket = COALESCE(auto_open_drawer_on_charge_without_ticket, 0),
            itbis_rate = COALESCE(itbis_rate, 0.18),
            warranty_policy = COALESCE(warranty_policy, ''),
            font_family = COALESCE(font_family, 'arialBlack'),
            font_size = COALESCE(font_size, 'normal'),
            show_logo = COALESCE(show_logo, 1),
            logo_size = COALESCE(logo_size, 60),
            show_business_data = COALESCE(show_business_data, 1),
            show_subtotal_itbis_total = COALESCE(show_subtotal_itbis_total, 1),
            auto_height = COALESCE(auto_height, 1),
            top_margin = COALESCE(top_margin, 8),
            bottom_margin = COALESCE(bottom_margin, 8),
            font_size_level = COALESCE(font_size_level, 5),
            line_spacing_level = COALESCE(line_spacing_level, 5),
            section_spacing_level = COALESCE(section_spacing_level, 5),
            section_separator_style = COALESCE(section_separator_style, 'single'),
            header_alignment = COALESCE(header_alignment, 'center'),
            details_alignment = COALESCE(details_alignment, 'left'),
            totals_alignment = COALESCE(totals_alignment, 'right')
      ''');
    }

    // products
    if (await _tableExists(db, DbTables.products)) {
      await _addColumnIfMissing(db, DbTables.products, 'image_path', 'TEXT');
      await _addColumnIfMissing(db, DbTables.products, 'image_url', 'TEXT');
      await _addColumnIfMissing(
        db,
        DbTables.products,
        'reserved_stock',
        'REAL NOT NULL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.products,
        'placeholder_color_hex',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.products,
        'placeholder_type',
        "TEXT NOT NULL DEFAULT 'image'",
      );
    }

    // pos_tickets (tickets pendientes)
    if (await _tableExists(db, DbTables.posTickets)) {
      // Asegurar que existen todas las columnas necesarias
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'ticket_name',
        'TEXT NOT NULL DEFAULT ""',
      );
      await _addColumnIfMissing(db, DbTables.posTickets, 'user_id', 'INTEGER');
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'client_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'local_code',
        'TEXT NOT NULL DEFAULT ""',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'itbis_enabled',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'itbis_rate',
        'REAL NOT NULL DEFAULT 0.18',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'discount_total',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'created_at_ms',
        'INTEGER NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTickets,
        'updated_at_ms',
        'INTEGER NOT NULL',
      );
      // Crear índices si faltan
      await _createIndexIfMissing(
        db,
        'idx_pos_tickets_user',
        DbTables.posTickets,
        'user_id',
      );
      await _createIndexIfMissing(
        db,
        'idx_pos_tickets_client',
        DbTables.posTickets,
        'client_id',
      );
      await _createIndexIfMissing(
        db,
        'idx_pos_tickets_local_code',
        DbTables.posTickets,
        'local_code',
      );
      await _createIndexIfMissing(
        db,
        'idx_pos_tickets_created',
        DbTables.posTickets,
        'created_at_ms',
      );
    }

    // pos_ticket_items (items de tickets pendientes)
    if (await _tableExists(db, DbTables.posTicketItems)) {
      // Asegurar que existen todas las columnas necesarias
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'ticket_id',
        'INTEGER NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'product_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'product_code_snapshot',
        'TEXT NOT NULL DEFAULT ""',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'product_name_snapshot',
        'TEXT NOT NULL DEFAULT ""',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'description',
        'TEXT NOT NULL DEFAULT ""',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'qty',
        'REAL NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'price',
        'REAL NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'cost',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'discount_line',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.posTicketItems,
        'total_line',
        'REAL NOT NULL',
      );
      // Crear índice si falta
      await _createIndexIfMissing(
        db,
        'idx_pos_ticket_items_ticket',
        DbTables.posTicketItems,
        'ticket_id',
      );
    }

    // temp_carts (carritos temporales)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.tempCarts} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        user_id INTEGER,
        client_id INTEGER,
        discount REAL NOT NULL DEFAULT 0,
        itbis_enabled INTEGER NOT NULL DEFAULT 1,
        itbis_rate REAL NOT NULL DEFAULT 0.18,
        fiscal_enabled INTEGER NOT NULL DEFAULT 0,
        discount_total_type TEXT,
        discount_total_value REAL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY (client_id) REFERENCES ${DbTables.clients}(id),
        FOREIGN KEY (user_id) REFERENCES ${DbTables.users}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.tempCartItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cart_id INTEGER NOT NULL,
        product_id INTEGER,
        product_code_snapshot TEXT NOT NULL,
        product_name_snapshot TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        purchase_price_snapshot REAL NOT NULL DEFAULT 0,
        discount_line REAL NOT NULL DEFAULT 0,
        total_line REAL NOT NULL,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (cart_id) REFERENCES ${DbTables.tempCarts}(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES ${DbTables.products}(id)
      )
    ''');

    await _createIndexIfMissing(
      db,
      'idx_temp_cart_items_cart',
      DbTables.tempCartItems,
      'cart_id',
    );

    // quotes
    if (await _tableExists(db, DbTables.quotes)) {
      // Agregar todas las columnas faltantes de quotes
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'user_id',
        'INTEGER REFERENCES ${DbTables.users}(id)',
      );
      await _addColumnIfMissing(db, DbTables.quotes, 'ticket_name', 'TEXT');
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'itbis_enabled',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'itbis_rate',
        'REAL NOT NULL DEFAULT 0.18',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'itbis_amount',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'discount_total',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'status',
        "TEXT NOT NULL DEFAULT 'OPEN'",
      );
      await _addColumnIfMissing(db, DbTables.quotes, 'notes', 'TEXT');
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'created_at_ms',
        'INTEGER NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quotes,
        'updated_at_ms',
        'INTEGER NOT NULL',
      );
      // Crear índices si faltan
      await _createIndexIfMissing(
        db,
        'idx_quotes_client',
        DbTables.quotes,
        'client_id',
      );
      await _createIndexIfMissing(
        db,
        'idx_quotes_status',
        DbTables.quotes,
        'status',
      );
      await _createIndexIfMissing(
        db,
        'idx_quotes_created',
        DbTables.quotes,
        'created_at_ms',
      );
    }

    // quote_items (items de cotizaciones)
    if (await _tableExists(db, DbTables.quoteItems)) {
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'product_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'product_code_snapshot',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'product_name_snapshot',
        'TEXT NOT NULL DEFAULT ""',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'description',
        'TEXT NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'qty',
        'REAL NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'unit_price',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'price',
        'REAL NOT NULL',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'cost',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'discount_line',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbTables.quoteItems,
        'total_line',
        'REAL NOT NULL',
      );

      // Backfill para compatibilidad entre esquemas antiguos/nuevos.
      // Algunos builds antiguos tenían unit_price NOT NULL y el código insertaba price.
      await db.execute('''
        UPDATE ${DbTables.quoteItems}
        SET unit_price = COALESCE(unit_price, price, 0)
      ''');
      await db.execute('''
        UPDATE ${DbTables.quoteItems}
        SET price = COALESCE(price, unit_price, 0)
      ''');
      await _createIndexIfMissing(
        db,
        'idx_quote_items_quote',
        DbTables.quoteItems,
        'quote_id',
      );
    }

    // users
    if (await _tableExists(db, DbTables.users)) {
      await _addColumnIfMissing(
        db,
        DbTables.users,
        'company_id',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(db, DbTables.users, 'display_name', 'TEXT');
      await _addColumnIfMissing(db, DbTables.users, 'permissions', 'TEXT');
      await _addColumnIfMissing(db, DbTables.users, 'password_hash', 'TEXT');
      final adminCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM ${DbTables.users} WHERE username = ?',
              ['admin'],
            ),
          ) ??
          0;
      if (adminCount == 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert(DbTables.users, {
          'company_id': 1,
          'username': 'admin',
          'pin': null,
          'role': 'admin',
          'is_active': 1,
          'created_at_ms': now,
          'updated_at_ms': now,
          'display_name': 'Admin',
          'permissions': null,
          'password_hash':
              '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
          'deleted_at_ms': null,
        });
      }
      await db.execute('''
        UPDATE ${DbTables.users}
        SET display_name = COALESCE(display_name, username)
      ''');
      await db.update(
        DbTables.users,
        {
          'password_hash':
              '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
        },
        where: 'username = ? AND (password_hash IS NULL OR password_hash = ?)',
        whereArgs: ['admin', ''],
      );
      await _ensureUsersUsernameIndex(db);
    }

    // stock_movements
    if (await _tableExists(db, DbTables.stockMovements)) {
      try {
        await _addColumnIfMissing(
          db,
          DbTables.stockMovements,
          'user_id',
          'INTEGER',
        );
      } catch (_) {
        // No romper apertura por integridad.
      }
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return result.isNotEmpty;
  }

  static Future<Set<String>> _getTableColumns(
    DatabaseExecutor db,
    String table,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name']).whereType<String>().toSet();
  }

  static Future<bool> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    if (!await _tableExists(db, table)) return false;
    final columns = await _getTableColumns(db, table);
    final existing = columns
        .map((c) => c.trim().toLowerCase())
        .where((c) => c.isNotEmpty)
        .toSet();
    final key = column.trim().toLowerCase();
    if (existing.contains(key)) return false;
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
      return true;
    } on DatabaseException catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('duplicate column name')) return false;
      rethrow;
    }
  }

  static Future<void> _createIndexIfMissing(
    DatabaseExecutor db,
    String indexName,
    String table,
    String columns,
  ) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS $indexName ON $table($columns)',
    );
  }

  /// Cierra la base de datos
  static Future<void> close() async {
    // Si hay apertura en curso, esperar para cerrar el handle correcto.
    final inFlight = _opening;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Ignorar: si falló la apertura, no hay nada que cerrar.
      }
    }

    final db = _database;
    _database = null;
    if (db == null) return;
    try {
      // Importante: sqflite_ffi puede lanzar "Bad state: This database has already been closed"
      // si llamamos close() dos veces. Hacerlo idempotente evita freezes.
      if (db.isOpen) {
        await db.close();
      }
    } catch (_) {
      // Ignorar: en entornos FFI la DB puede ya estar cerrada.
    }
  }
}
