import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Acceso resiliente a SharedPreferences.
///
/// En desktop (especialmente Windows), un corte de luz puede dejar el archivo
/// JSON de preferencias truncado y `SharedPreferences.getInstance()` lanza
/// `FormatException`, impidiendo el arranque.
///
/// Esta utilidad intenta reparar renombrando el archivo corrupto y reintentando.
/// No toca la base de datos.
class PrefsSafe {
  PrefsSafe._();

  static Future<SharedPreferences?> getInstance({
    bool attemptRepair = true,
  }) async {
    try {
      return await SharedPreferences.getInstance();
    } on FormatException {
      if (!attemptRepair) return null;
      final repaired = await _repairCorruptedPrefsFiles();
      if (!repaired) return null;
      try {
        return await SharedPreferences.getInstance();
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _repairCorruptedPrefsFiles() async {
    // Solo aplica a plataformas con backend de archivo.
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return false;
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      // Candidatos comunes usados por shared_preferences_* en desktop.
      final candidates = <File>[
        File(p.join(supportDir.path, 'shared_preferences.json')),
        File(
          p.join(
            supportDir.path,
            'shared_preferences',
            'shared_preferences.json',
          ),
        ),
        File(p.join(supportDir.path, 'flutter_shared_preferences.json')),
      ];

      var didSomething = false;
      for (final file in candidates) {
        if (!await file.exists()) continue;

        final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        final target = '${file.path}.corrupt_$stamp';
        try {
          await file.rename(target);
          didSomething = true;
        } catch (_) {
          // Si rename falla (lock/permiso), intentar copiar+delete.
          try {
            await file.copy(target);
            await file.delete();
            didSomething = true;
          } catch (_) {}
        }
      }

      return didSomething;
    } catch (_) {
      return false;
    }
  }
}
