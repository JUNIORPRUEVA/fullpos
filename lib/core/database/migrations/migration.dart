import 'package:sqflite/sqflite.dart';

/// Representa una migración incremental (fromVersion -> toVersion).
abstract class Migration {
  int get fromVersion;
  int get toVersion;

  Future<void> run(DatabaseExecutor db);
}

