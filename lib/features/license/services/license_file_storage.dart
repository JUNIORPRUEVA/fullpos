import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LicenseFileStorage {
  static const _fileName = 'license.dat';

  Future<File> file() async {
    // Requisito: %APPDATA%/FullPOS/license.dat
    final appData = Platform.isWindows ? Platform.environment['APPDATA'] : null;

    Directory base;
    if (appData != null && appData.trim().isNotEmpty) {
      base = Directory(p.join(appData.trim(), 'FullPOS'));
    } else {
      final support = await getApplicationSupportDirectory();
      base = Directory(p.join(support.path, 'FullPOS'));
    }

    if (!base.existsSync()) {
      base.createSync(recursive: true);
    }

    return File(p.join(base.path, _fileName));
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
