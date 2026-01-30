import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_db.dart';

class BackupPaths {
  BackupPaths._();

  static const String backupsDirName = 'FULLPOS_BACKUPS';

  static Future<Directory> documentsDir() async {
    // En desktop, getApplicationDocumentsDirectory apunta a Documents.
    // En Android, es el Documents dir de la app.
    return getApplicationDocumentsDirectory();
  }

  static Future<Directory> backupsBaseDir() async {
    final docs = await documentsDir();

    // Windows: fuera de carpeta de instalación, dentro de Documents.
    // Android: dentro del Documents dir de la app.
    final dir = Directory(p.join(docs.path, backupsDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> tempWorkDir() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory(p.join(temp.path, 'backup_work'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> databaseFilePath() async {
    return AppDb.databasePath();
  }

  static Future<List<Directory>> optionalDataDirs() async {
    final docs = await documentsDir();
    final candidates = <String>[
      'product_images',
    ];

    final dirs = <Directory>[];
    for (final name in candidates) {
      final dir = Directory(p.join(docs.path, name));
      if (await dir.exists()) dirs.add(dir);
    }
    return dirs;
  }

  static Future<void> cleanTempWorkDir() async {
    final dir = await tempWorkDir();
    if (!await dir.exists()) return;

    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // Ignorar.
    }
  }
}
