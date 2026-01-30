import 'dart:io';

import 'package:crypto/crypto.dart';

import '../logging/app_logger.dart';
import '../session/session_manager.dart';
import '../utils/id_utils.dart';
import '../db/app_db.dart';
import 'backup_models.dart';
import 'backup_paths.dart';
import 'backup_prefs.dart';
import 'backup_repository.dart';
import 'backup_service.dart';
import 'cloud_backup_service.dart';
import 'cloud_status_service.dart';

class BackupOrchestrator {
  BackupOrchestrator._();

  static final BackupOrchestrator instance = BackupOrchestrator._();

  DateTime? _lastAutoBackupAt;

  Future<void> triggerAutoBackupIfAllowed({
    required bool enabled,
    required BackupTrigger trigger,
  }) async {
    if (!enabled) return;
    if (BackupService.instance.isRunning) return;

    final last = _lastAutoBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }

    await createBackup(
      trigger: trigger,
      maxWait: const Duration(seconds: 30),
    );
    _lastAutoBackupAt = DateTime.now();
  }

  Future<BackupResult> createBackup({
    required BackupTrigger trigger,
    String? notes,
    Duration maxWait = const Duration(minutes: 2),
  }) async {
    final status = await CloudStatusService.instance.checkStatus();
    final keepLocalCopy = await BackupPrefs.instance.getKeepLocalCopy();

    if (!status.canUseCloudBackup) {
      return BackupService.instance.createBackup(
        trigger: trigger,
        notes: notes,
        maxWait: maxWait,
      );
    }

    final startedAt = DateTime.now();
    final historyId = IdUtils.uuidV4();
    final companyId = (await SessionManager.companyId() ?? 1).toString();
    final userId = await SessionManager.userId();
    final deviceId =
        await SessionManager.terminalId() ?? await SessionManager.ensureTerminalId();
    final cloudHistory = BackupHistoryEntry(
      id: historyId,
      empresaId: companyId,
      createdAtMs: startedAt.millisecondsSinceEpoch,
      mode: BackupMode.cloud,
      status: BackupStatus.inProgress,
      dbVersion: AppDb.schemaVersion,
      appVersion: const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: 'unknown',
      ),
      deviceId: deviceId,
      usuarioId: userId,
      notes: notes,
    );
    await BackupRepository.instance.insertHistory(cloudHistory);

    BackupResult localResult;
    if (keepLocalCopy) {
      localResult = await BackupService.instance.createBackup(
        trigger: trigger,
        notes: notes,
        maxWait: maxWait,
      );
    } else {
      final tempDir = await BackupPaths.tempWorkDir();
      localResult = await BackupService.instance.createBackup(
        trigger: trigger,
        notes: notes,
        maxWait: maxWait,
        outputDir: tempDir,
        recordHistory: false,
      );
    }

    if (!localResult.ok || localResult.path == null) {
      await BackupRepository.instance.updateHistory(
        cloudHistory.copyWith(
          status: BackupStatus.failed,
          errorMessage: localResult.messageDev ?? localResult.messageUser,
        ),
      );
      return localResult;
    }

    final localPath = localResult.path!;
    final sizeBytes = localResult.sizeBytes ?? await File(localPath).length();
    final checksum =
        localResult.checksumSha256 ?? await _sha256OfFile(localPath);

    final upload = await CloudBackupService.instance.uploadBackup(
      filePath: localPath,
      sizeBytes: sizeBytes,
      checksumSha256: checksum,
      dbVersion: AppDb.schemaVersion,
      appVersion: const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: 'unknown',
      ),
      deviceId: deviceId,
      userId: userId ?? 0,
    );

    if (!upload.ok) {
      await BackupRepository.instance.updateHistory(
        cloudHistory.copyWith(
          status: BackupStatus.failed,
          errorMessage: upload.message ?? 'Upload fallido',
        ),
      );

      if (!keepLocalCopy) {
        // Fallback local si el upload fallÃ³.
        final fallback = await BackupService.instance.createBackup(
          trigger: trigger,
          notes: notes ?? 'FALLBACK_LOCAL',
          maxWait: maxWait,
        );
        return fallback;
      }

      return BackupResult(
        ok: false,
        messageUser: 'Backup en nube fallÃ³. Se guardÃ³ copia local.',
        messageDev: upload.message,
      );
    }

    await BackupRepository.instance.updateHistory(
      cloudHistory.copyWith(
        status: BackupStatus.success,
        cloudBackupId: upload.cloudBackupId,
        sizeBytes: sizeBytes,
        checksumSha256: checksum,
      ),
    );

    if (!keepLocalCopy) {
      try {
        await File(localPath).delete();
      } catch (_) {
        // Ignorar.
      }
    }

    await AppLogger.instance.logInfo(
      'Backup cloud ok id=${upload.cloudBackupId}',
      module: 'backup_cloud',
    );

    return BackupResult(
      ok: true,
      path: keepLocalCopy ? localPath : null,
      sizeBytes: sizeBytes,
      checksumSha256: checksum,
    );
  }

  Future<String> _sha256OfFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
