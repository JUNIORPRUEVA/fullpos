import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Inicialización de la base de datos para plataformas desktop
class DbInit {
  DbInit._();

  static bool _initialized = false;

  /// Inicializa sqflite_ffi para Windows, Linux y macOS
  static void ensureInitialized() {
    if (_initialized) return;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Inicializar FFI para desktop
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _initialized = true;
    }
  }
}
