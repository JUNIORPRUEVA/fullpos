import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../identity/identity_recovery_bundle.dart';
import 'app_recovery.dart';

class RecoveryLock {
  RecoveryLock._();

  static const Duration staleAfter = Duration(minutes: 10);

  static Future<File> lockFile() async {
    final dir = await AppRecoveryController.recoveryDir();
    return File(p.join(dir.path, 'recovery.lock'));
  }

  static Future<bool> isFresh() async {
    final file = await lockFile();
    if (!await file.exists()) return false;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final createdAt = DateTime.tryParse(
          (decoded['createdAt'] ?? '').toString(),
        );
        if (createdAt != null) {
          return DateTime.now().toUtc().difference(createdAt.toUtc()) <
              staleAfter;
        }
      }
      final modified = await file.lastModified();
      return DateTime.now().toUtc().difference(modified.toUtc()) < staleAfter;
    } catch (_) {
      return true;
    }
  }

  static Future<void> acquire(String reason) async {
    final file = await lockFile();
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      if (await isFresh()) {
        throw const AppRecoveryRequiredException(
          'Ya hay una recuperación en curso',
        );
      }
      await IdentityRecoveryBundle.instance.log(
        'recovery_lock_stale_replaced reason=$reason',
      );
    }
    await file.writeAsString(
      jsonEncode({
        'reason': reason,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  static Future<void> release() async {
    final file = await lockFile();
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
