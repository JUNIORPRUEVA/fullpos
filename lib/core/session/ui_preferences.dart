import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Maneja las preferencias de UI del usuario
class UiPreferences {
  UiPreferences._();

  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Stream que emite cuando cambian preferencias relevantes para la UI.
  ///
  /// Se usa para refrescar widgets globales (ej: Topbar) sin depender de
  /// navegación o reinicio.
  static Stream<void> get changes => _changesController.stream;

  static void _notifyChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  static const String _keySidebarCollapsed = 'sidebar_collapsed';
  static const String _keyKeyboardShortcuts = 'keyboard_shortcuts';
  static const String _keyProfileImagePrefix = 'profile_image_path:';

  static String _profileImageKey(String userKey) =>
      '$_keyProfileImagePrefix$userKey';

  /// Verifica si el sidebar está colapsado
  static Future<bool> isSidebarCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySidebarCollapsed) ?? false;
  }

  /// Guarda el estado del sidebar (colapsado o expandido)
  static Future<void> setSidebarCollapsed(bool collapsed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySidebarCollapsed, collapsed);
  }

  /// Toggle del estado del sidebar
  static Future<bool> toggleSidebar() async {
    final current = await isSidebarCollapsed();
    await setSidebarCollapsed(!current);
    return !current;
  }

  /// Verifica si los atajos de teclado estǭn habilitados
  static Future<bool> isKeyboardShortcutsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKeyboardShortcuts) ?? true;
  }

  /// Habilita/Deshabilita atajos de teclado
  static Future<void> setKeyboardShortcutsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeyboardShortcuts, enabled);
  }

  /// Ruta local (en disco) de la imagen de perfil para un usuario.
  ///
  /// [userKey] debe ser estable (por ejemplo: "id:123" o "u:juan").
  static Future<String?> getProfileImagePath(String userKey) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_profileImageKey(userKey));
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// Guarda/borra la ruta local de imagen de perfil para un usuario.
  static Future<void> setProfileImagePath(String userKey, String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _profileImageKey(userKey);
    final value = path?.trim();
    if (value == null || value.isEmpty) {
      final existed = prefs.containsKey(key);
      if (!existed) return;
      await prefs.remove(key);
      _notifyChanged();
      return;
    }

    final existing = prefs.getString(key);
    if (existing == value) return;
    await prefs.setString(key, value);
    _notifyChanged();
  }
}
