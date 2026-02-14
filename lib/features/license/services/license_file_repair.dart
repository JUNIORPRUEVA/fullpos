import 'dart:io';

import 'license_file_storage.dart';

class LicenseFileRepair {
  LicenseFileRepair({LicenseFileStorage? storage})
    : _storage = storage ?? LicenseFileStorage();

  final LicenseFileStorage _storage;

  /// Renombra license.dat a license.bad.TIMESTAMP para poder re-sincronizar.
  Future<String?> quarantineLocalLicenseFile() async {
    final f = await _storage.file();
    if (!await f.exists()) return null;

    final ts = DateTime.now().millisecondsSinceEpoch;
    final quarantined = File('${f.path}.bad.$ts');

    try {
      await f.rename(quarantined.path);
      return quarantined.path;
    } catch (_) {
      // Fallback: copy + delete
      try {
        await quarantined.writeAsBytes(await f.readAsBytes(), flush: true);
        await f.delete();
        return quarantined.path;
      } catch (_) {
        return null;
      }
    }
  }
}
