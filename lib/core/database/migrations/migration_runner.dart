import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Runner central para migraciones versionadas.
///
/// Nota: hoy el proyecto usa `_onUpgrade` con if(oldVersion < X). Este runner
/// existe para migraciones futuras en archivos 001_x.dart, 002_y.dart, etc.
class MigrationRunner {
  MigrationRunner._();

  static Future<void> run({
    required DatabaseExecutor db,
    required int oldVersion,
    required int newVersion,
    required List<Migration> migrations,
  }) async {
    if (oldVersion >= newVersion) return;

    final sorted = [...migrations]
      ..sort((a, b) => a.fromVersion.compareTo(b.fromVersion));

    var current = oldVersion;
    while (current < newVersion) {
      final next = sorted.where((m) => m.fromVersion == current).toList();
      if (next.isEmpty) {
        // No hay migración registrada para este salto.
        return;
      }
      if (next.length != 1) {
        throw StateError(
          'Ambiguous migrations for version $current: ${next.map((e) => '${e.fromVersion}->${e.toVersion}').join(', ')}',
        );
      }

      final migration = next.single;
      if (migration.toVersion <= current) {
        throw StateError(
          'Invalid migration ${migration.fromVersion}->${migration.toVersion}',
        );
      }

      await migration.run(db);
      current = migration.toVersion;
    }
  }
}

