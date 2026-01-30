import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_themes.dart';

/// Provider para el tema seleccionado actualmente
final appThemeProvider = StateNotifierProvider<AppThemeNotifier, AppThemeEnum>((ref) {
  return AppThemeNotifier();
});

/// Provider que retorna el ThemeData actual
final themeDataProvider = Provider<ThemeData>((ref) {
  final themeEnum = ref.watch(appThemeProvider);
  return AppThemes.getTheme(themeEnum);
});

/// Notifier para manejar los cambios de tema
class AppThemeNotifier extends StateNotifier<AppThemeEnum> {
  static const String _themeKey = 'app_theme';

  AppThemeNotifier() : super(AppThemeEnum.proPos) {
    _loadTheme();
  }

  /// Cargar el tema guardado de SharedPreferences
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeKey = prefs.getString(_themeKey) ?? 'proPos';
      state = AppThemes.getThemeEnumByKey(themeKey);
    } catch (e) {
      // Si hay error, mantener el tema profesional
      state = AppThemeEnum.proPos;
    }
  }

  /// Cambiar el tema y guardar en SharedPreferences
  Future<void> setTheme(AppThemeEnum theme) async {
    try {
      state = theme;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, theme.key);
    } catch (e) {
      // Si hay error, ignorar pero mantener el estado
      state = theme;
    }
  }

  /// Cambiar a tema original
  Future<void> setOriginal() => setTheme(AppThemeEnum.original);

  /// Cambiar a tema azul/blanco/negro
  Future<void> setAzulBlancoNegro() => setTheme(AppThemeEnum.azulBlancoNegro);

  /// Cambiar a tema profesional POS
  Future<void> setProPos() => setTheme(AppThemeEnum.proPos);
}
