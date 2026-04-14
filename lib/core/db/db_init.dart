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
      if (Platform.isWindows) {
        _ensureWindowsSqliteLibrary();
      }
      // Inicializar FFI para desktop
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _initialized = true;
    }
  }

  static void _ensureWindowsSqliteLibrary() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final target = File('${exeDir.path}${Platform.pathSeparator}sqlite3.dll');
    if (target.existsSync()) return;

    final programFiles =
        Platform.environment['ProgramFiles'] ?? 'C:\\Program Files';
    final programFilesX86 =
        Platform.environment['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)';
    final candidates = <String>[
      '${programFiles}${Platform.pathSeparator}FullTech${Platform.pathSeparator}sqlite3.dll',
      '${programFiles}${Platform.pathSeparator}LibreOffice${Platform.pathSeparator}program${Platform.pathSeparator}sqlite3.dll',
      '${programFilesX86}${Platform.pathSeparator}sqlite3.dll',
    ];

    for (final candidatePath in candidates) {
      final candidate = File(candidatePath);
      if (!candidate.existsSync()) continue;
      try {
        candidate.copySync(target.path);
        return;
      } catch (_) {
        // Intentar con el siguiente candidato.
      }
    }
  }
}
