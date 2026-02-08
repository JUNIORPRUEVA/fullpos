import '../logging/app_logger.dart';
import 'backup_models.dart';
import 'backup_paths.dart';
import 'backup_service.dart';
import 'cloud_backup_service.dart';

class RestoreService {
  RestoreService._();

  static final RestoreService instance = RestoreService._();

  Future<BackupResult> restoreLocal({
    required String zipPath,
    String? expectedChecksumSha256,
  }) async {
    return BackupService.instance.restoreBackup(
      zipPath: zipPath,
      notes: 'RESTORE_LOCAL',
      expectedChecksumSha256: expectedChecksumSha256,
    );
  }

  Future<BackupResult> restoreFromCloud({
    required String cloudBackupId,
    String? expectedChecksumSha256,
  }) async {
    final valid = await CloudBackupService.instance.validateBackup(
      cloudBackupId: cloudBackupId,
    );
    if (!valid) {
      return const BackupResult(
        ok: false,
        messageUser: 'El backup en la nube no pasó validación.',
        messageDev: 'Cloud validation failed',
      );
    }

    final tempDir = await BackupPaths.tempWorkDir();
    final file = await CloudBackupService.instance.downloadBackup(
      cloudBackupId: cloudBackupId,
      outDir: tempDir,
    );
    if (file == null || !await file.exists()) {
      return const BackupResult(
        ok: false,
        messageUser: 'No se pudo descargar el backup de la nube.',
        messageDev: 'Cloud download failed',
      );
    }

    try {
      return await BackupService.instance.restoreBackup(
        zipPath: file.path,
        notes: 'RESTORE_CLOUD',
        expectedChecksumSha256: expectedChecksumSha256,
      );
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Restore cloud failed: $e',
        module: 'backup_restore',
      );
      return const BackupResult(
        ok: false,
        messageUser: 'No se pudo restaurar el backup de la nube.',
        messageDev: 'Restore cloud failed',
      );
    }
  }
}
