import 'package:flutter/widgets.dart';

import '../lib/core/db/app_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbPath = await AppDb.databasePath();
  // Use print() so output is visible in `flutter run` logs.
  // ignore: avoid_print
  print(
    '[DB-MIGRATE] path="$dbPath" targetVersion=${AppDb.schemaVersion}',
  );

  // Open via AppDb to ensure the app's real migration logic runs (onUpgrade + integrity checks).
  final db = await AppDb.database;

  final beforeRows = await db.rawQuery('PRAGMA user_version');
  final userVersion = beforeRows.isNotEmpty
      ? (beforeRows.first['user_version'] as int?)
      : null;
  // ignore: avoid_print
  print('[DB-MIGRATE] user_version=$userVersion');

  // Close to release file locks.
  await db.close();
  // ignore: avoid_print
  print('[DB-MIGRATE] done');
}
