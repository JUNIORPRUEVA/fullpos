import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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

  static const String _pendingReasonPrefix = 'PENDING_UPLOAD:';

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

    await createBackup(trigger: trigger, maxWait: const Duration(seconds: 30));
    _lastAutoBackupAt = DateTime.now();
  }

  Future<BackupResult> createBackup({
    required BackupTrigger trigger,
    String? notes,
    Duration maxWait = const Duration(minutes: 2),
  }) async {
    final status = await CloudStatusService.instance.checkStatus();
    final keepLocalCopy = await BackupPrefs.instance.getKeepLocalCopy();

    // Nube completamente desactivada: solo local.
    if (!status.isCloudEnabled) {
      return BackupService.instance.createBackup(
        trigger: trigger,
        notes: notes,
        maxWait: maxWait,
      );
    }

    // Nube activada, pero no usable: crear local y marcar pendiente para reintento.
    if (!status.canUseCloudBackup) {
      final local = await BackupService.instance.createBackup(
        trigger: trigger,
        notes: notes,
        maxWait: maxWait,
      );

      if (local.ok && local.path != null) {
        final startedAt = DateTime.now();
        final historyId = IdUtils.uuidV4();
        final companyId = (await SessionManager.companyId() ?? 1).toString();
        final userId = await SessionManager.userId();
        final deviceId =
            await SessionManager.terminalId() ??
            await SessionManager.ensureTerminalId();
        final localPath = local.path!;
        final sizeBytes = local.sizeBytes ?? await File(localPath).length();
        final checksum = local.checksumSha256 ?? await _sha256OfFile(localPath);

        await BackupRepository.instance.insertHistory(
          BackupHistoryEntry(
            id: historyId,
            empresaId: companyId,
            createdAtMs: startedAt.millisecondsSinceEpoch,
            mode: BackupMode.cloud,
            status: BackupStatus.pendingUpload,
            dbVersion: AppDb.schemaVersion,
            appVersion: const String.fromEnvironment(
              'APP_VERSION',
              defaultValue: 'unknown',
            ),
            deviceId: deviceId,
            usuarioId: userId,
            filePath: localPath,
            sizeBytes: sizeBytes,
            checksumSha256: checksum,
            notes: notes,
            errorMessage:
                '$_pendingReasonPrefix ${status.reason ?? 'Nube no disponible'}',
          ),
        );
      }

      return BackupResult(
        ok: local.ok,
        path: local.path,
        sizeBytes: local.sizeBytes,
        checksumSha256: local.checksumSha256,
        messageUser: local.ok
            ? 'Backup local OK. Nube pendiente: ${status.reason ?? 'reintentar'}.'
            : (local.messageUser ?? 'Backup fallido.'),
        messageDev: local.messageDev,
      );
    }

    final startedAt = DateTime.now();
    final historyId = IdUtils.uuidV4();
    final companyId = (await SessionManager.companyId() ?? 1).toString();
    final userId = await SessionManager.userId();
    final deviceId =
        await SessionManager.terminalId() ??
        await SessionManager.ensureTerminalId();
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
      // Conservar ZIP para reintento (aunque keepLocalCopy sea false).
      final stablePath = await _ensureStableBackupPath(localPath);
      await BackupRepository.instance.updateHistory(
        cloudHistory.copyWith(
          status: BackupStatus.pendingUpload,
          filePath: stablePath,
          sizeBytes: sizeBytes,
          checksumSha256: checksum,
          errorMessage:
              '$_pendingReasonPrefix ${upload.message ?? 'Upload fallido'}',
        ),
      );

      return BackupResult(
        ok: true,
        path: keepLocalCopy ? localPath : stablePath,
        sizeBytes: sizeBytes,
        checksumSha256: checksum,
        messageUser: 'Backup local OK. Subida a nube pendiente (reintentar).',
        messageDev: upload.message,
      );
    }

    await BackupRepository.instance.updateHistory(
      cloudHistory.copyWith(
        status: BackupStatus.success,
        cloudBackupId: upload.cloudBackupId,
        sizeBytes: sizeBytes,
        checksumSha256: checksum,
        filePath: keepLocalCopy ? localPath : null,
        clearFilePath: !keepLocalCopy,
        clearErrorMessage: true,
      ),
    );

    if (!keepLocalCopy) {
      try {
        if (await File(localPath).exists()) {
          await File(localPath).delete();
        }
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

  Future<String> _ensureStableBackupPath(String path) async {
    final baseDir = await BackupPaths.backupsBaseDir();
    final file = File(path);
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final currentDir = p.dirname(path);
    if (p.equals(currentDir, baseDir.path)) {
      return path;
    }

    final dest = p.join(baseDir.path, p.basename(path));
    try {
      return (await file.rename(dest)).path;
    } catch (_) {
      await file.copy(dest);
      try {
        await file.delete();
      } catch (_) {}
      return dest;
    }
  }

  Future<BackupResult> retryCloudUpload({
    required BackupHistoryEntry entry,
  }) async {
    if (entry.mode != BackupMode.cloud) {
      return const BackupResult(
        ok: false,
        messageUser: 'Este backup no es de nube.',
      );
    }
    if (entry.cloudBackupId != null) {
      return const BackupResult(
        ok: true,
        messageUser: 'Este backup ya está subido a la nube.',
      );
    }

    final zipPath = entry.filePath;
    if (zipPath == null) {
      return const BackupResult(
        ok: false,
        messageUser: 'No existe archivo local para reintentar.',
      );
    }

    final status = await CloudStatusService.instance.checkStatus();
    if (!status.canUseCloudBackup) {
      await BackupRepository.instance.updateHistory(
        entry.copyWith(
          status: BackupStatus.pendingUpload,
          errorMessage:
              '$_pendingReasonPrefix ${status.reason ?? 'Nube no disponible'}',
        ),
      );
      return BackupResult(
        ok: false,
        messageUser:
            'Nube no disponible: ${status.reason ?? 'configuración incompleta'}.',
      );
    }

    final file = File(zipPath);
    if (!await file.exists()) {
      await BackupRepository.instance.updateHistory(
        entry.copyWith(
          status: BackupStatus.failed,
          errorMessage: 'No se encontró el ZIP local: $zipPath',
        ),
      );
      return const BackupResult(
        ok: false,
        messageUser: 'No se encontró el backup local.',
      );
    }

    final sizeBytes = await file.length();
    final checksum = await _sha256OfFile(zipPath);
    final expected = entry.checksumSha256;
    if (expected != null && expected.isNotEmpty && checksum != expected) {
      await BackupRepository.instance.updateHistory(
        entry.copyWith(
          status: BackupStatus.failed,
          sizeBytes: sizeBytes,
          checksumSha256: checksum,
          errorMessage:
              'Checksum no coincide (esperado=$expected real=$checksum)',
        ),
      );
      return const BackupResult(
        ok: false,
        messageUser:
            'El backup local parece alterado/corrupto (checksum no coincide).',
      );
    }

    await BackupRepository.instance.updateHistory(
      entry.copyWith(
        status: BackupStatus.inProgress,
        sizeBytes: sizeBytes,
        checksumSha256: checksum,
        clearErrorMessage: true,
      ),
    );

    final deviceId =
        await SessionManager.terminalId() ??
        await SessionManager.ensureTerminalId();
    final userId = await SessionManager.userId() ?? 0;

    final upload = await CloudBackupService.instance.uploadBackup(
      filePath: zipPath,
      sizeBytes: sizeBytes,
      checksumSha256: checksum,
      dbVersion: entry.dbVersion,
      appVersion: entry.appVersion,
      deviceId: deviceId,
      userId: userId,
    );

    if (!upload.ok) {
      await BackupRepository.instance.updateHistory(
        entry.copyWith(
          status: BackupStatus.pendingUpload,
          errorMessage:
              '$_pendingReasonPrefix ${upload.message ?? 'Upload fallido'}',
        ),
      );
      return BackupResult(
        ok: false,
        messageUser: 'No se pudo subir a la nube. Quedó pendiente.',
        messageDev: upload.message,
      );
    }

    final keepLocalCopy = await BackupPrefs.instance.getKeepLocalCopy();
    String? updatedPath = zipPath;
    if (!keepLocalCopy) {
      try {
        await file.delete();
        updatedPath = null;
      } catch (_) {
        // Ignorar: si no se pudo borrar, igual queda la copia local.
      }
    }

    await BackupRepository.instance.updateHistory(
      entry.copyWith(
        status: BackupStatus.success,
        cloudBackupId: upload.cloudBackupId,
        filePath: updatedPath,
        clearFilePath: updatedPath == null,
        sizeBytes: sizeBytes,
        checksumSha256: checksum,
        clearErrorMessage: true,
      ),
    );

    await AppLogger.instance.logInfo(
      'Retry cloud ok id=${upload.cloudBackupId}',
      module: 'backup_cloud',
    );

    return BackupResult(
      ok: true,
      path: updatedPath,
      sizeBytes: sizeBytes,
      checksumSha256: checksum,
    );
  }
}
