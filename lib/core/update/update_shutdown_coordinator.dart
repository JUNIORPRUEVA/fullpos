import 'dart:async';

import '../backup/backup_service.dart';
import '../db/database_manager.dart';
import '../logging/app_logger.dart';
import '../services/cloud_sync_service.dart';
import '../sync/product_sync_service.dart';
import 'app_update_safety.dart';
import 'cash_close_activity_tracker.dart';
import 'import_export_activity_tracker.dart';
import 'print_activity_tracker.dart';

enum UpdatePreparationStep {
  verifyingOpenProcesses,
  pausingBackgroundTasks,
  waitingForIdle,
  closingServices,
  startingInstaller,
}

class UpdatePreparationResult {
  const UpdatePreparationResult({required this.ready, this.message});

  final bool ready;
  final String? message;
}

typedef UpdatePreparationProgress = void Function(UpdatePreparationStep step);

class SafeUpdateCoordinator {
  SafeUpdateCoordinator({
    AppUpdateSafetyValidator safetyValidator = const AppUpdateSafetyValidator(),
    CloudSyncService? cloudSyncService,
    ProductSyncService? productSyncService,
    BackupService? backupService,
    DatabaseManager? databaseManager,
    AppLogger? logger,
  }) : _safetyValidator = safetyValidator,
       _cloudSyncService = cloudSyncService ?? CloudSyncService.instance,
       _productSyncService = productSyncService ?? ProductSyncService.instance,
       _backupService = backupService ?? BackupService.instance,
       _databaseManager = databaseManager ?? DatabaseManager.instance,
       _logger = logger ?? AppLogger.instance;

  static const pendingProcessesMessage =
      'No pudimos iniciar la actualización porque hay procesos que aún no terminan. Espera unos segundos y vuelve a intentarlo.';

  final AppUpdateSafetyValidator _safetyValidator;
  final CloudSyncService _cloudSyncService;
  final ProductSyncService _productSyncService;
  final BackupService _backupService;
  final DatabaseManager _databaseManager;
  final AppLogger _logger;

  bool _preparing = false;
  bool _readyToCloseForUpdate = false;

  bool get isPreparing => _preparing;
  bool get readyToCloseForUpdate => _readyToCloseForUpdate;

  static bool updatePreparing = false;
  static bool get blocksCriticalOperations => updatePreparing;

  Future<UpdatePreparationResult> prepare({
    Duration timeout = const Duration(seconds: 25),
    UpdatePreparationProgress? onProgress,
  }) async {
    if (_preparing) {
      return const UpdatePreparationResult(
        ready: false,
        message: pendingProcessesMessage,
      );
    }
    _preparing = true;
    _readyToCloseForUpdate = false;
    updatePreparing = true;
    try {
      onProgress?.call(UpdatePreparationStep.verifyingOpenProcesses);
      await _logger.logInfo(
        'Starting safe update validation',
        module: 'app_update',
      );
      final validation = await _safetyValidator.validate();
      if (!validation.safe) {
        await _logger.logWarn(
          'Safe update validation blocked: ${validation.blockReason}',
          module: 'app_update',
        );
        updatePreparing = false;
        return UpdatePreparationResult(
          ready: false,
          message:
              validation.blockReason ??
              AppUpdateSafetyValidator.pendingWorkMessage,
        );
      }
      if (validation.warning != null) {
        await _logger.logWarn(
          'Safe update validation warning: ${validation.warning}',
          module: 'app_update',
        );
      }

      onProgress?.call(UpdatePreparationStep.pausingBackgroundTasks);
      await _logger.logInfo(
        'Blocking new critical operations and pausing background workers',
        module: 'app_update',
      );
      _cloudSyncService.pauseForUpdate();
      _productSyncService.pauseForUpdate();
      _backupService.pauseSchedulerForUpdate();

      onProgress?.call(UpdatePreparationStep.waitingForIdle);
      final idle = await _waitForIdle(timeout);
      if (!idle) {
        await _logger.logWarn(
          'Safe update preparation timeout waiting for active operations',
          module: 'app_update',
        );
        updatePreparing = false;
        return const UpdatePreparationResult(
          ready: false,
          message: pendingProcessesMessage,
        );
      }

      onProgress?.call(UpdatePreparationStep.closingServices);
      await _logger.logInfo(
        'Closing database connections safely for update',
        module: 'app_update',
      );
      await _databaseManager.close(reason: 'safe_update_prepare');

      _readyToCloseForUpdate = true;
      onProgress?.call(UpdatePreparationStep.startingInstaller);
      await _logger.logInfo(
        'Safe update preparation completed readyToCloseForUpdate=true',
        module: 'app_update',
      );
      return const UpdatePreparationResult(ready: true);
    } finally {
      _preparing = false;
      if (!_readyToCloseForUpdate) {
        updatePreparing = false;
      }
    }
  }

  Future<bool> _waitForIdle(Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    final cloudIdle = await _cloudSyncService.waitUntilIdle(timeout);
    if (!cloudIdle) return false;
    final remainingAfterCloud = timeout - stopwatch.elapsed;
    if (remainingAfterCloud <= Duration.zero) return false;

    final productIdle = await _productSyncService.waitUntilIdle(
      remainingAfterCloud,
    );
    if (!productIdle) return false;
    final remainingAfterProducts = timeout - stopwatch.elapsed;
    if (remainingAfterProducts <= Duration.zero) return false;

    if (!await _backupService.waitUntilIdle(remainingAfterProducts)) {
      return false;
    }
    final remainingAfterBackup = timeout - stopwatch.elapsed;
    if (remainingAfterBackup <= Duration.zero) return false;

    if (!await PrintActivityTracker.instance.waitUntilIdle(
      remainingAfterBackup,
    )) {
      return false;
    }
    final remainingAfterPrint = timeout - stopwatch.elapsed;
    if (remainingAfterPrint <= Duration.zero) return false;

    if (!await ImportExportActivityTracker.instance.waitUntilIdle(
      remainingAfterPrint,
    )) {
      return false;
    }
    final remainingAfterImportExport = timeout - stopwatch.elapsed;
    if (remainingAfterImportExport <= Duration.zero) return false;

    return CashCloseActivityTracker.instance.waitUntilIdle(
      remainingAfterImportExport,
    );
  }
}
