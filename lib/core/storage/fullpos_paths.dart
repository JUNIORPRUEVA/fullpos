import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FullPosPaths {
  FullPosPaths._();

  static const String rootDirName = 'FullPOS_PTV';
  static const String legacyAppDirName = 'FullPOS';

  static Directory? _rootOverrideForTests;

  static void setRootOverrideForTests(Directory? directory) {
    _rootOverrideForTests = directory;
  }

  static Future<Directory> rootDir() async {
    final override = _rootOverrideForTests;
    if (override != null) {
      await _ensureDir(override);
      return override;
    }

    const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
    final candidates = <Directory>[];
    if (Platform.isWindows && !isFlutterTest) {
      final programData = Platform.environment['PROGRAMDATA']?.trim();
      if (programData != null && programData.isNotEmpty) {
        candidates.add(Directory(p.join(programData, rootDirName)));
      }
    }

    final support = await getApplicationSupportDirectory();
    final normalizedSupport = p.normalize(support.path).toLowerCase();
    final normalizedTemp = p.normalize(Directory.systemTemp.path).toLowerCase();
    if (p.equals(normalizedSupport, normalizedTemp) ||
        p.isWithin(normalizedTemp, normalizedSupport)) {
      final dir = Directory(p.join(support.path, rootDirName));
      await _ensureDir(dir);
      return dir;
    }

    candidates.add(Directory(p.join(support.path, rootDirName)));

    for (final candidate in candidates) {
      if (await _canUseDirectory(candidate)) return candidate;
    }

    final fallback = candidates.last;
    await _ensureDir(fallback);
    return fallback;
  }

  static Future<Directory> dataDir() => _childDir('data');
  static Future<Directory> backupsDir() => _childDir('backups');
  static Future<Directory> mediaDir() => _childDir('media');
  static Future<Directory> productImagesDir() async {
    final media = await mediaDir();
    return _ensureDir(Directory(p.join(media.path, 'products')));
  }

  static Future<Directory> categoryImagesDir() async {
    final media = await mediaDir();
    return _ensureDir(Directory(p.join(media.path, 'categories')));
  }

  static Future<Directory> profileImagesDir() async {
    final media = await mediaDir();
    return _ensureDir(Directory(p.join(media.path, 'profile_images')));
  }

  static Future<Directory> businessMediaDir() async {
    final media = await mediaDir();
    return _ensureDir(Directory(p.join(media.path, 'business')));
  }

  static Future<Directory> logsDir() => _childDir('logs');
  static Future<Directory> appLogsDir() async {
    final logs = await logsDir();
    return _ensureDir(Directory(p.join(logs.path, 'app')));
  }

  static Future<Directory> supportLogsDir() async {
    final logs = await logsDir();
    return _ensureDir(Directory(p.join(logs.path, 'support')));
  }

  static Future<Directory> dbLogsDir() async {
    final logs = await logsDir();
    return _ensureDir(Directory(p.join(logs.path, 'db')));
  }

  static Future<Directory> licenseDir() => _childDir('license');
  static Future<Directory> identityDir() => _childDir('identity');
  static Future<Directory> updatesDir() => _childDir('updates');
  static Future<Directory> tempDir() => _childDir('temp');

  static Future<Directory> dbHardeningBackupsDir() async {
    final backups = await backupsDir();
    return _ensureDir(Directory(p.join(backups.path, 'db_hardening')));
  }

  static Future<String> databasePath(String fileName) async {
    final dir = await dataDir();
    return p.join(dir.path, fileName);
  }

  static Future<File> licenseFile() async {
    final dir = await licenseDir();
    return File(p.join(dir.path, 'license.dat'));
  }

  static Future<Directory> _childDir(String name) async {
    final root = await rootDir();
    return _ensureDir(Directory(p.join(root.path, name)));
  }

  static Future<Directory> _ensureDir(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<bool> _canUseDirectory(Directory directory) async {
    try {
      await _ensureDir(directory);
      final probe = File(
        p.join(directory.path, '.fullpos_write_probe_${pid.toString()}'),
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
