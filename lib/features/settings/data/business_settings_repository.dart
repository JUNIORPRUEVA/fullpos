import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db_hardening/db_hardening.dart';
import 'business_settings_model.dart';

/// Repositorio para la configuración del negocio
class BusinessSettingsRepository {
  static const String _tableName = 'business_settings';

  // Evita carreras durante init/migraciones.
  // Problema observado: múltiples cargas en paralelo pueden ejecutar
  // CREATE TABLE / ALTER TABLE simultáneamente.
  static Future<void>? _ensureInFlight;

  /// Lista de todas las columnas esperadas con sus definiciones
  static const Map<String, String> _expectedColumns = {
    'id': 'INTEGER PRIMARY KEY DEFAULT 1',
    'business_name': "TEXT NOT NULL DEFAULT 'FULLPOS'",
    'logo_path': 'TEXT',
    'phone': 'TEXT',
    'phone2': 'TEXT',
    'email': 'TEXT',
    'address': 'TEXT',
    'city': 'TEXT',
    'rnc': 'TEXT',
    'slogan': 'TEXT',
    'website': 'TEXT',
    'instagram_url': 'TEXT',
    'facebook_url': 'TEXT',
    'default_tax_rate': 'REAL DEFAULT 18.0',
    'tax_included_in_prices': 'INTEGER DEFAULT 1',
    'default_currency': "TEXT DEFAULT 'DOP'",
    'currency_symbol': "TEXT DEFAULT 'RD\$'",
    'receipt_header': "TEXT DEFAULT ''",
    'receipt_footer': "TEXT DEFAULT '¡Gracias por su compra!'",
    'show_logo_on_receipt': 'INTEGER DEFAULT 1',
    'print_receipt_automatically': 'INTEGER DEFAULT 0',
    'default_charge_output_mode': "TEXT DEFAULT 'ticket'",
    'enable_auto_backup': 'INTEGER DEFAULT 1',
    'enable_notifications': 'INTEGER DEFAULT 1',
    'enable_inventory_tracking': 'INTEGER DEFAULT 1',
    'enable_client_approval': 'INTEGER DEFAULT 0',
    'enable_data_encryption': 'INTEGER DEFAULT 1',
    'show_details_on_dashboard': 'INTEGER DEFAULT 1',
    'dark_mode_enabled': 'INTEGER DEFAULT 0',
    'session_timeout_minutes': 'INTEGER DEFAULT 30',
    'cloud_enabled': 'INTEGER DEFAULT 0',
    'cloud_provider': "TEXT DEFAULT 'custom'",
    'cloud_endpoint': 'TEXT',
    'cloud_bucket': 'TEXT',
    'cloud_api_key': 'TEXT',
    'cloud_allowed_roles': "TEXT DEFAULT '[\"admin\"]'",
    'cloud_owner_app_android_url': 'TEXT',
    'cloud_owner_app_ios_url': 'TEXT',
    'cloud_owner_username': 'TEXT',
    'cloud_company_id': 'TEXT',
    'created_at': 'TEXT DEFAULT CURRENT_TIMESTAMP',
    'updated_at': 'TEXT DEFAULT CURRENT_TIMESTAMP',
  };

  static Future<T> _withDb<T>(
    String stage,
    Future<T> Function(Database db) callback,
  ) => DbHardening.instance.runDbSafe(() async {
    final db = await AppDb.database;
    return callback(db);
  }, stage: stage);

  static Future<T> _withTable<T>(
    String stage,
    Future<T> Function(Database db) callback,
  ) => _withDb(stage, (db) async {
    await _ensureTable(db);
    return callback(db);
  });

  static Future<void> _ensureTable(Database db) {
    final existing = _ensureInFlight;
    if (existing != null) return existing;

    final future = _ensureTableImpl(db);
    _ensureInFlight = future.whenComplete(() {
      if (identical(_ensureInFlight, future)) {
        _ensureInFlight = null;
      }
    });
    return _ensureInFlight!;
  }

  static Future<void> _ensureTableImpl(Database db) async {
    final columns = _expectedColumns.entries
        .map((e) => '${e.key} ${e.value}')
        .join(',\n          ');

    // Idempotente: evita "table business_settings already exists".
    await db.execute('CREATE TABLE IF NOT EXISTS $_tableName ($columns)');

    // Insert inicial idempotente.
    await db.execute(
      "INSERT OR IGNORE INTO $_tableName (id, business_name, created_at, updated_at) VALUES (1, 'FULLPOS', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
    );

    await _migrateTableColumns(db);
  }

  /// Inicializar tabla de configuración del negocio
  static Future<void> initTable() async {
    await _withDb('business_settings_init', (db) => _ensureTable(db));
  }

  /// Migrar tabla agregando columnas faltantes
  static Future<void> _migrateTableColumns(DatabaseExecutor db) async {
    try {
      final effectiveDb = (db is Database && !db.isOpen)
          ? await AppDb.database
          : db;
      // Obtener columnas existentes
      final tableInfo = await effectiveDb.rawQuery(
        'PRAGMA table_info($_tableName)',
      );
      final existingColumns = tableInfo
          .map((row) => row['name'] as String)
          .toSet();

      // Agregar columnas faltantes
      for (final entry in _expectedColumns.entries) {
        if (!existingColumns.contains(entry.key) && entry.key != 'id') {
          try {
            // Extraer el tipo base de la definición
            final definition = entry.value;
            String columnDef = definition;

            // Para ALTER TABLE, necesitamos simplificar la definición
            if (definition.contains('DEFAULT')) {
              columnDef = definition;
            }

            await effectiveDb.execute(
              'ALTER TABLE $_tableName ADD COLUMN ${entry.key} $columnDef',
            );
            // ignore: avoid_print
            print('✅ Columna ${entry.key} agregada a $_tableName');
          } catch (e) {
            // ignore: avoid_print
            print('⚠️ No se pudo agregar columna ${entry.key}: $e');
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error migrando tabla $_tableName: $e');
      // Re-throw so the DB hardening helper can clear/reopen the handle.
      rethrow;
    }
  }

  /// Cargar configuración del negocio
  Future<BusinessSettings> loadSettings() {
    return _withTable('business_settings_load', (db) async {
      final results = await db.query(_tableName, where: 'id = 1');

      if (results.isEmpty) {
        // Si no hay configuración, crear una por defecto
        await db.insert(_tableName, {
          'id': 1,
          'business_name': 'FULLPOS',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        return BusinessSettings.defaultSettings;
      }

      final settings = BusinessSettings.fromMap(results.first);
      final hasCustomData =
          (settings.logoPath ?? '').trim().isNotEmpty ||
          (settings.phone ?? '').trim().isNotEmpty ||
          (settings.phone2 ?? '').trim().isNotEmpty ||
          (settings.email ?? '').trim().isNotEmpty ||
          (settings.address ?? '').trim().isNotEmpty ||
          (settings.city ?? '').trim().isNotEmpty ||
          (settings.rnc ?? '').trim().isNotEmpty ||
          (settings.slogan ?? '').trim().isNotEmpty ||
          (settings.website ?? '').trim().isNotEmpty ||
          (settings.instagramUrl ?? '').trim().isNotEmpty ||
          (settings.facebookUrl ?? '').trim().isNotEmpty;

      if (settings.businessName.trim() == 'Mi Negocio' && !hasCustomData) {
        final updated = settings.copyWith(businessName: 'FULLPOS');
        await saveSettings(updated);
        return updated;
      }

      return settings;
    });
  }

  /// Guardar configuración del negocio (solo columnas válidas)
  Future<void> saveSettings(BusinessSettings settings) {
    return _withTable('business_settings_save', (db) async {
      final tableInfo = await db.rawQuery('PRAGMA table_info($_tableName)');
      final existingColumns = tableInfo
          .map((row) => row['name'] as String)
          .toSet();

      final map = settings.toMap();
      map['updated_at'] = DateTime.now().toIso8601String();

      final filteredMap = <String, dynamic>{};
      for (final entry in map.entries) {
        if (existingColumns.contains(entry.key) && entry.key != 'id') {
          filteredMap[entry.key] = entry.value;
        }
      }

      await db.update(_tableName, filteredMap, where: 'id = ?', whereArgs: [1]);
    });
  }

  /// Actualizar un campo específico
  Future<void> updateField(String field, dynamic value) {
    return _withTable('business_settings_update_field', (db) async {
      await db.update(
        _tableName,
        {field: value, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [1],
      );
    });
  }

  /// Obtener tasa de impuesto por defecto
  Future<double> getDefaultTaxRate() async {
    final settings = await loadSettings();
    return settings.defaultTaxRate;
  }

  /// Resetear a valores por defecto
  Future<void> resetToDefault() async {
    await saveSettings(BusinessSettings.defaultSettings);
  }
}
