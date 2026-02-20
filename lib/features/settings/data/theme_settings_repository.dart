import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/session/session_manager.dart';
import 'theme_settings_model.dart';

/// Repositorio para persistir el tema como **overrides por compañía (tenant)**.
///
/// - SystemDefaultTheme: [ThemeSettings.defaultSettings] (inmutable, shipped).
/// - CustomerThemeOverrides: overrides guardados por `company_id`.
/// - finalTheme = merge(default, overrides).
///
/// Importante: **Nunca** escribe sobre el tema default; solo guarda el diff.
class ThemeSettingsRepository {
  static const String _tableName = 'company_theme_overrides';
  static const String _colCompanyId = 'company_id';
  static const String _colOverridesJson = 'overrides_json';
  static const String _colUpdatedAtMs = 'updated_at_ms';

  // Legacy (pre multi-tenant): tema completo en SharedPreferences.
  static const String _legacyThemeKey = 'theme_settings';

  static Future<void>? _ensureInFlight;

  Future<int> _resolveCompanyId(int? companyId) async {
    if (companyId != null) return companyId;
    return (await SessionManager.companyId()) ?? 1;
  }

  Future<T> _withDb<T>(String stage, Future<T> Function(Database db) action) {
    return DbHardening.instance.runDbSafe(() async {
      final db = await AppDb.database;
      return action(db);
    }, stage: stage);
  }

  Future<void> _ensureTable(Database db) {
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

  Future<void> _ensureTableImpl(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        $_colCompanyId INTEGER PRIMARY KEY,
        $_colOverridesJson TEXT NOT NULL,
        $_colUpdatedAtMs INTEGER NOT NULL
      )
    ''');
  }

  Map<String, dynamic> _computeOverrides({
    required ThemeSettings base,
    required ThemeSettings current,
  }) {
    final baseMap = base.toMap();
    final currentMap = current.toMap();
    final overrides = <String, dynamic>{};

    for (final entry in currentMap.entries) {
      final baseValue = baseMap[entry.key];
      if (baseValue != entry.value) {
        overrides[entry.key] = entry.value;
      }
    }
    return overrides;
  }

  ThemeSettings _merge({
    required ThemeSettings base,
    required Map<String, dynamic> overrides,
  }) {
    if (overrides.isEmpty) return base;
    final merged = <String, dynamic>{...base.toMap(), ...overrides};
    return ThemeSettings.fromMap(merged);
  }

  bool _isLegacyTealGold(ThemeSettings settings) {
    return settings.primaryColor.value == 0xFF00796B &&
        settings.accentColor.value == 0xFFD4AF37;
  }

  Future<String?> _readLegacyThemeJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_legacyThemeKey);
  }

  Future<void> _removeLegacyThemeJson() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyThemeKey);
  }

  Future<Map<String, dynamic>?> _tryParseLegacyThemeToOverrides() async {
    final jsonStr = await _readLegacyThemeJson();
    if (jsonStr == null) return null;

    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      final loaded = ThemeSettings.fromMap(map);
      if (_isLegacyTealGold(loaded)) return <String, dynamic>{};
      return _computeOverrides(
        base: ThemeSettings.defaultSettings,
        current: loaded,
      );
    } catch (_) {
      return null;
    }
  }

  /// Cargar el tema final (default + overrides) para la compañía actual.
  Future<ThemeSettings> loadThemeSettings({int? companyId}) async {
    // Seguridad de marca: antes de login no aplicamos overrides de cliente.
    // Esto evita que pantallas de autenticación/licencia (branding fijo)
    // hereden colores personalizados por tenant.
    if (!await SessionManager.isLoggedIn()) {
      return ThemeSettings.defaultSettings;
    }

    final effectiveCompanyId = await _resolveCompanyId(companyId);

    return _withDb('theme_load', (db) async {
      await _ensureTable(db);

      final rows = await db.query(
        _tableName,
        columns: [_colOverridesJson],
        where: '$_colCompanyId = ?',
        whereArgs: [effectiveCompanyId],
        limit: 1,
      );

      Map<String, dynamic> overrides = <String, dynamic>{};
      if (rows.isNotEmpty) {
        final rawJson = (rows.first[_colOverridesJson] as String?) ?? '{}';
        try {
          final decoded = json.decode(rawJson);
          if (decoded is Map<String, dynamic>) {
            overrides = decoded;
          }
        } catch (_) {
          overrides = <String, dynamic>{};
        }
      } else {
        // Migración legacy: solo para company_id=1 (históricamente era global).
        if (effectiveCompanyId == 1) {
          final legacyOverrides = await _tryParseLegacyThemeToOverrides();
          if (legacyOverrides != null && legacyOverrides.isNotEmpty) {
            await _saveOverrides(
              db,
              companyId: effectiveCompanyId,
              overrides: legacyOverrides,
            );
            await _removeLegacyThemeJson();
            overrides = legacyOverrides;
          } else if (legacyOverrides != null && legacyOverrides.isEmpty) {
            // Legacy detectado como paleta antigua: limpiamos key para evitar reintentos.
            await _removeLegacyThemeJson();
          }
        }
      }

      return _merge(base: ThemeSettings.defaultSettings, overrides: overrides);
    });
  }

  Future<void> _saveOverrides(
    Database db, {
    required int companyId,
    required Map<String, dynamic> overrides,
  }) async {
    final jsonStr = json.encode(overrides);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert(_tableName, {
      _colCompanyId: companyId,
      _colOverridesJson: jsonStr,
      _colUpdatedAtMs: nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Guarda overrides (diff vs default) para la compañía actual.
  Future<bool> saveThemeSettings(
    ThemeSettings settings, {
    int? companyId,
  }) async {
    final effectiveCompanyId = await _resolveCompanyId(companyId);
    final overrides = _computeOverrides(
      base: ThemeSettings.defaultSettings,
      current: settings,
    );

    return _withDb('theme_save', (db) async {
      await _ensureTable(db);
      if (overrides.isEmpty) {
        await db.delete(
          _tableName,
          where: '$_colCompanyId = ?',
          whereArgs: [effectiveCompanyId],
        );
        return true;
      }
      await _saveOverrides(
        db,
        companyId: effectiveCompanyId,
        overrides: overrides,
      );
      return true;
    });
  }

  /// Resetear a valores por defecto (borra overrides) para la compañía actual.
  Future<bool> resetToDefault({int? companyId}) async {
    final effectiveCompanyId = await _resolveCompanyId(companyId);
    return _withDb('theme_reset', (db) async {
      await _ensureTable(db);
      await db.delete(
        _tableName,
        where: '$_colCompanyId = ?',
        whereArgs: [effectiveCompanyId],
      );
      return true;
    });
  }

  /// Verificar si hay overrides para la compañía actual.
  Future<bool> hasCustomTheme({int? companyId}) async {
    final effectiveCompanyId = await _resolveCompanyId(companyId);
    return _withDb('theme_has_custom', (db) async {
      await _ensureTable(db);
      final rows = await db.query(
        _tableName,
        columns: [_colOverridesJson],
        where: '$_colCompanyId = ?',
        whereArgs: [effectiveCompanyId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final rawJson = (rows.first[_colOverridesJson] as String?) ?? '{}';
      try {
        final decoded = json.decode(rawJson);
        return decoded is Map && decoded.isNotEmpty;
      } catch (_) {
        return false;
      }
    });
  }
}
