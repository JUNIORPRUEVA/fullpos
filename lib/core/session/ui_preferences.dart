import 'package:shared_preferences/shared_preferences.dart';

/// Maneja las preferencias de UI del usuario
class UiPreferences {
  UiPreferences._();

  static const String _keySidebarCollapsed = 'sidebar_collapsed';
  static const String _keyKeyboardShortcuts = 'keyboard_shortcuts';

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
}
