import 'dart:io';

import '../../../core/storage/fullpos_paths.dart';

class LicenseFileStorage {
  static const _fileName = 'license.dat';

  Future<File> file() async {
    final dir = await FullPosPaths.licenseDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<String?> readToken() async {
    final f = await file();
    if (!await f.exists()) return null;
    try {
      final raw = (await f.readAsString()).trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeToken(String token) async {
    final f = await file();
    final dir = f.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(token.trim());
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    await tmp.rename(f.path);
  }

  Future<void> delete() async {
    final f = await file();
    if (await f.exists()) {
      await f.delete();
    }
  }
}
