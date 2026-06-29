import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../identity/identity_recovery_bundle.dart';
import '../identity/license_reactivation_marker.dart';
import '../identity/terminal_id_log_recovery_service.dart';
import '../recovery/app_recovery.dart';
import '../storage/prefs_safe.dart';

/// Maneja la sesión del usuario usando SharedPreferences
class SessionManager {
  SessionManager._();

  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Stream que emite cuando cambia la sesión (login/logout/perfil).
  static Stream<void> get changes => _changesController.stream;

  static void _notifyChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  static const String _keyLoggedIn = 'logged_in';
  static const String _keyUserId = 'logged_user_id';
  static const String _keyUsername = 'logged_user';
  static const String _keyDisplayName = 'logged_display_name';
  static const String _keyRole = 'logged_role';
  static const String _keyPermissions = 'logged_permissions';
  static const String _keyCompanyId = 'logged_company_id';
  static const String _keyTerminalId = 'terminal_id';

  static Future<SharedPreferences?> _prefs({bool attemptRepair = true}) {
    return PrefsSafe.getInstance(attemptRepair: attemptRepair);
  }

  /// Verifica si hay un usuario logueado
  static Future<bool> isLoggedIn() async {
    final prefs = await _prefs();
    return prefs?.getBool(_keyLoggedIn) ?? false;
  }

  /// Obtiene el ID del usuario logueado
  static Future<int?> userId() async {
    final prefs = await _prefs();
    return prefs?.getInt(_keyUserId);
  }

  /// Obtiene el nombre de usuario logueado
  static Future<String?> username() async {
    final prefs = await _prefs();
    return prefs?.getString(_keyUsername);
  }

  /// Obtiene el nombre para mostrar del usuario
  static Future<String?> displayName() async {
    final prefs = await _prefs();
    return prefs?.getString(_keyDisplayName);
  }

  /// Obtiene el rol del usuario
  static Future<String?> role() async {
    final prefs = await _prefs();
    return prefs?.getString(_keyRole);
  }

  /// Obtiene los permisos del usuario (JSON string)
  static Future<String?> permissions() async {
    final prefs = await _prefs();
    return prefs?.getString(_keyPermissions);
  }

  /// Actualiza el JSON de permisos cacheado en sesión.
  ///
  /// Importante: se usa para evitar inconsistencias cuando un admin cambia
  /// permisos y el cliente tenía un cache viejo.
  static Future<void> setPermissions(String? permissionsJson) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    final existing = prefs.getString(_keyPermissions);
    if (permissionsJson != null) {
      // Evitar loops: si el valor no cambia, no escribimos ni notificamos.
      if (existing == permissionsJson) return;
      await prefs.setString(_keyPermissions, permissionsJson);
      _notifyChanged();
      return;
    }

    // permissionsJson == null
    if (existing == null) return;
    await prefs.remove(_keyPermissions);
    _notifyChanged();
  }

  static Future<int?> companyId() async {
    final prefs = await _prefs();
    return prefs?.getInt(_keyCompanyId);
  }

  static Future<void> setCompanyId(int companyId) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setInt(_keyCompanyId, companyId);
    _notifyChanged();
  }

  static Future<String?> terminalId() async {
    final prefs = await _prefs();
    final existing = prefs?.getString(_keyTerminalId);
    if (existing != null && existing.isNotEmpty) return existing;
    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final restored = (bundle?.terminalId ?? '').trim();
    if (restored.isEmpty || prefs == null) return null;
    final ok = await IdentityRecoveryBundle.instance
        .restoreBundleToSharedPreferences(
          bundle!,
          reason: 'session_terminal_id_missing',
        );
    return ok ? restored : null;
  }

  static Future<String> ensureTerminalId() async {
    final prefs = await _prefs();
    if (prefs == null) {
      if (await IdentityRecoveryBundle.instance
          .hasPriorInstallationEvidence()) {
        unawaited(
          AppRecoveryController.instance.requireIdentityRecovery(
            'terminal_id_missing_prefs_unavailable',
          ),
        );
        await IdentityRecoveryBundle.instance.markRecoveryRequired(
          'terminal_id_missing_prefs_unavailable',
        );
        await IdentityRecoveryBundle.instance.log(
          'terminal_id_generation_blocked_prefs_unavailable',
        );
        throw const IdentityRecoveryException(
          'No se pudo recuperar terminal_id local',
        );
      }
      return 'terminal-${_randomToken(6)}';
    }
    final existing = prefs.getString(_keyTerminalId);
    if (existing != null && existing.isNotEmpty) {
      await IdentityRecoveryBundle.instance.saveFromCurrentState(
        'session_terminal_id_confirmed',
      );
      return existing;
    }

    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final restored = (bundle?.terminalId ?? '').trim();
    if (restored.isNotEmpty) {
      final ok = await IdentityRecoveryBundle.instance
          .restoreBundleToSharedPreferences(
            bundle!,
            reason: 'session_ensure_terminal_id',
          );
      if (ok) return restored;
    }

    if (await IdentityRecoveryBundle.instance.hasPriorInstallationEvidence()) {
      final sqliteTerminal = await _restoreTerminalIdFromSqlite(prefs);
      if (sqliteTerminal != null) return sqliteTerminal;

      final recovered = await const TerminalIdLogRecoveryService().recover(
        reason: 'terminal_id_missing_prior_installation',
      );
      if (recovered.recovered && recovered.terminalId != null) {
        return recovered.terminalId!;
      }

      final generated = await _createReplacementTerminalId(
        prefs,
        reason: 'terminal_id_missing_prior_installation',
      );
      return generated;
    }

    final generated = 'terminal-${_randomToken(6)}';
    await prefs.setString(_keyTerminalId, generated);
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'session_terminal_id_generated_first_install',
    );
    return generated;
  }

  static Future<String?> _restoreTerminalIdFromSqlite(
    SharedPreferences prefs,
  ) async {
    Database? db;
    try {
      final dbPath = await AppDb.databasePath();
      if (!await File(dbPath).exists()) return null;
      db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
      final rows = await db.query('app_identity', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      final terminalId = (row['terminal_id'] ?? '').toString().trim();
      if (terminalId.isEmpty || terminalId.toLowerCase() == 'null') {
        return null;
      }

      final currentBusinessId = await _currentBusinessId(prefs);
      final sqliteBusinessId = (row['business_id'] ?? '').toString().trim();
      if (currentBusinessId != null &&
          sqliteBusinessId.isNotEmpty &&
          sqliteBusinessId != currentBusinessId) {
        await IdentityRecoveryBundle.instance.log(
          'sqlite_terminal_id_rejected_business_mismatch',
        );
        return null;
      }

      final currentLicenseKey = await _currentLicenseKey(prefs);
      final sqliteLicenseKey = (row['license_key'] ?? '').toString().trim();
      if (currentLicenseKey != null &&
          sqliteLicenseKey.isNotEmpty &&
          !_licenseMatches(sqliteLicenseKey, currentLicenseKey)) {
        await IdentityRecoveryBundle.instance.log(
          'sqlite_terminal_id_rejected_license_mismatch',
        );
        return null;
      }

      await prefs.setString(_keyTerminalId, terminalId);
      await IdentityRecoveryBundle.instance.saveFromCurrentState(
        'session_terminal_id_restored_from_sqlite',
      );
      await IdentityRecoveryBundle.instance.log(
        'terminal_id_restored_from_sqlite terminalId=${_mask(terminalId)}',
      );
      return terminalId;
    } catch (e) {
      await IdentityRecoveryBundle.instance.log(
        'sqlite_terminal_id_restore_failed error=$e',
      );
      return null;
    } finally {
      await db?.close();
    }
  }

  static Future<String?> _currentBusinessId(SharedPreferences prefs) async {
    final direct = (prefs.getString(IdentityRecoveryBundle.businessIdKey) ?? '')
        .trim();
    if (direct.isNotEmpty) return direct;
    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final fromBundle = (bundle?.businessId ?? '').trim();
    return fromBundle.isEmpty ? null : fromBundle;
  }

  static Future<String?> _currentLicenseKey(SharedPreferences prefs) async {
    final direct = (prefs.getString(IdentityRecoveryBundle.licenseKeyKey) ?? '')
        .trim();
    if (direct.isNotEmpty) return direct;
    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final fromBundle = (bundle?.licenseKey ?? '').trim();
    return fromBundle.isEmpty ? null : fromBundle;
  }

  static bool _licenseMatches(String candidate, String expected) {
    final a = candidate.trim();
    final b = expected.trim();
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    const suffixLength = 6;
    if (a.length < suffixLength || b.length < suffixLength) return false;
    return a.substring(a.length - suffixLength) ==
        b.substring(b.length - suffixLength);
  }

  static Future<String> _createReplacementTerminalId(
    SharedPreferences prefs, {
    required String reason,
  }) async {
    final generated = 'terminal-${_randomToken(6)}';
    await prefs.setString(_keyTerminalId, generated);
    await const LicenseReactivationMarker().require(
      reason: reason,
      temporaryTerminalId: generated,
    );
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'session_terminal_id_replacement_reactivation_required',
    );
    await IdentityRecoveryBundle.instance.log(
      'terminal_id_replacement_generated reason=$reason terminalId=${_mask(generated)}',
    );
    return generated;
  }

  static String _mask(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'null';
    if (v.length <= 4) return '***';
    return '${v.substring(0, 4)}...${v.substring(v.length - 2)}';
  }

  /// Verifica si el usuario actual es admin.
  /// Normaliza el rol a minúsculas para evitar falsos negativos por capitalización
  /// (e.g. 'Admin', 'ADMIN' deben tratarse igual que 'admin').
  static Future<bool> isAdmin() async {
    final userRole = await role();
    return (userRole?.trim().toLowerCase()) == 'admin';
  }

  /// Inicia sesión con un usuario
  static Future<void> login({
    required int userId,
    required String username,
    required String displayName,
    required String role,
    String? permissions,
    int companyId = 1,
    String? terminalId,
  }) async {
    // En caso de prefs corrupto, intentar reparación una vez.
    final prefs = await _prefs(attemptRepair: true);
    if (prefs == null) {
      throw StateError('No se pudo inicializar almacenamiento local');
    }
    await prefs.setBool(_keyLoggedIn, true);
    await prefs.setInt(_keyUserId, userId);
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyDisplayName, displayName);
    await prefs.setString(_keyRole, role);
    await prefs.setInt(_keyCompanyId, companyId);
    if (terminalId != null && terminalId.isNotEmpty) {
      await prefs.setString(_keyTerminalId, terminalId);
    } else {
      await ensureTerminalId();
    }
    if (permissions != null) {
      await prefs.setString(_keyPermissions, permissions);
    } else {
      // Evitar que queden permisos viejos guardados de una sesión anterior.
      await prefs.remove(_keyPermissions);
    }

    _notifyChanged();
    assert(() {
      debugPrint(
        '[AUTH] login saved: logged_in=true userId=$userId username=$username role=$role',
      );
      return true;
    }());
  }

  /// Actualiza solo el nombre para mostrar del usuario actual
  static Future<void> setDisplayName(String displayName) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setString(_keyDisplayName, displayName);
    _notifyChanged();
  }

  /// Cierra la sesión
  static Future<void> logout() async {
    final prefs = await _prefs();
    if (prefs == null) {
      _notifyChanged();
      return;
    }
    final beforeLoggedIn = prefs.getBool(_keyLoggedIn);
    final beforeUserId = prefs.getInt(_keyUserId);
    await prefs.remove(_keyLoggedIn);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyPermissions);
    await prefs.remove(_keyCompanyId);

    _notifyChanged();
    assert(() {
      debugPrint(
        '[AUTH] logout cleared: before logged_in=$beforeLoggedIn userId=$beforeUserId -> logged_in=${prefs.getBool(_keyLoggedIn)} userId=${prefs.getInt(_keyUserId)}',
      );
      return true;
    }());
  }

  static Future<void> clearInvalidSession({String? reason}) async {
    final prefs = await _prefs();
    if (prefs == null) {
      _notifyChanged();
      return;
    }
    await prefs.remove(_keyLoggedIn);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyPermissions);
    await prefs.remove(_keyCompanyId);
    _notifyChanged();
    assert(() {
      debugPrint('[AUTH] invalid session cleared reason=${reason ?? ''}');
      return true;
    }());
  }

  static String _randomToken(int length) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[rand.nextInt(alphabet.length)],
    ).join();
  }
}
