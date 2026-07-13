import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/app_db.dart';
import '../storage/fullpos_paths.dart';

class BackupPaths {
  BackupPaths._();

  static const String backupsDirName = 'FULLPOS_BACKUPS';

  static Future<Directory> documentsDir() async {
    return FullPosPaths.rootDir();
  }

  static Future<Directory> backupsBaseDir() async {
    final dir = await FullPosPaths.backupsDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> tempWorkDir() async {
    final temp = await FullPosPaths.tempDir();
    final dir = Directory(p.join(temp.path, 'backup_work'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> databaseFilePath() async {
    return AppDb.databasePath();
  }

  static Future<List<Directory>> optionalDataDirs() async {
    final dirs = <Directory>[
      await FullPosPaths.productImagesDir(),
      await FullPosPaths.categoryImagesDir(),
    ];
    return [
      for (final dir in dirs)
        if (await dir.exists()) dir,
    ];
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
