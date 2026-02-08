import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

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

  /// Verifica si hay un usuario logueado
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLoggedIn) ?? false;
  }

  /// Obtiene el ID del usuario logueado
  static Future<int?> userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyUserId);
  }

  /// Obtiene el nombre de usuario logueado
  static Future<String?> username() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  /// Obtiene el nombre para mostrar del usuario
  static Future<String?> displayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDisplayName);
  }

  /// Obtiene el rol del usuario
  static Future<String?> role() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRole);
  }

  /// Obtiene los permisos del usuario (JSON string)
  static Future<String?> permissions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPermissions);
  }

  /// Actualiza el JSON de permisos cacheado en sesión.
  ///
  /// Importante: se usa para evitar inconsistencias cuando un admin cambia
  /// permisos y el cliente tenía un cache viejo.
  static Future<void> setPermissions(String? permissionsJson) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCompanyId);
  }

  static Future<void> setCompanyId(int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCompanyId, companyId);
    _notifyChanged();
  }

  static Future<String?> terminalId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTerminalId);
  }

  static Future<String> ensureTerminalId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyTerminalId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = 'terminal-${_randomToken(6)}';
    await prefs.setString(_keyTerminalId, generated);
    return generated;
  }

  /// Verifica si el usuario actual es admin
  static Future<bool> isAdmin() async {
    final userRole = await role();
    return userRole == 'admin';
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
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDisplayName, displayName);
    _notifyChanged();
  }

  /// Cierra la sesión
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
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

  static String _randomToken(int length) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[rand.nextInt(alphabet.length)],
    ).join();
  }
}
