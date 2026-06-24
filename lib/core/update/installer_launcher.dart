import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_manager.dart';
import '../logging/app_logger.dart';
import '../services/cloud_sync_service.dart';
import '../sync/product_sync_service.dart';
import '../window/window_service.dart';
import 'app_update_policy.dart';
import 'pending_update_status.dart';
import 'update_downloader.dart';
import 'update_shutdown_coordinator.dart';

class InstallerLauncher {
  InstallerLauncher({
    SafeUpdateCoordinator? shutdownCoordinator,
    PendingUpdateStatusStore? statusStore,
    Future<Directory> Function()? updateRoot,
  }) : _shutdownCoordinator = shutdownCoordinator ?? SafeUpdateCoordinator(),
       _statusStore =
           statusStore ??
           PendingUpdateStatusStore(
             updateRoot: updateRoot ?? UpdateDownloader().updateRoot,
           );

  static const _allowDebugLaunch = bool.fromEnvironment(
    'FULLPOS_ALLOW_INSTALLER_LAUNCH',
    defaultValue: false,
  );

  final SafeUpdateCoordinator _shutdownCoordinator;
  final PendingUpdateStatusStore _statusStore;

  bool _launching = false;
  bool get isLaunching => _launching;

  Future<void> launch(
    File installer,
    AppUpdatePolicy policy, {
    UpdatePreparationProgress? onProgress,
  }) async {
    if (_launching) throw StateError('Installer launch already in progress');
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    if (kDebugMode && !_allowDebugLaunch) {
      throw StateError(
        'Installer launch is disabled in debug builds. '
        'Use FULLPOS_ALLOW_INSTALLER_LAUNCH=true only for manual testing.',
      );
    }
    _launching = true;
    try {
      final prepareResult = await _shutdownCoordinator.prepare(
        onProgress: onProgress,
      );
      if (!prepareResult.ready) {
        throw UpdatePreparationException(
          prepareResult.message ??
              SafeUpdateCoordinator.pendingProcessesMessage,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('update_install_target', policy.latest.toString());
      await prefs.setString('update_installer_path', installer.path);
      await prefs.setInt(
        'update_install_attempted_at',
        DateTime.now().millisecondsSinceEpoch,
      );
      await _statusStore.markInstalling(policy: policy, installer: installer);

      CloudSyncService.instance.stopRealtimeSyncEngine();
      ProductSyncService.instance.stop();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await AppLogger.instance.logInfo(
        'Launching FullPOSUpdater target=${policy.latest}',
        module: 'app_update',
      );
      await AppLogger.instance.flush();
      await WindowService.setPreventClose(false);

      try {
        final appExecutable = File(Platform.resolvedExecutable);
        final appDirectory = appExecutable.parent;
        final updater = File(p.join(appDirectory.path, 'FullPOSUpdater.exe'));
        if (!await updater.exists()) {
          throw StateError(
            'FullPOSUpdater.exe was not found in ${appDirectory.path}',
          );
        }
        final logFile = File(
          p.join(installer.parent.path, 'FullPOSUpdater.log'),
        );
        final args = <String>[
          '--installer',
          installer.path,
          '--app',
          appExecutable.path,
          '--pid',
          pid.toString(),
          '--silent',
          '--restart',
          '--log',
          logFile.path,
        ];
        await AppLogger.instance.logInfo(
          'FullPOSUpdater.exe launch command="${updater.path}" args=${args.join(' ')}',
          module: 'app_update',
        );
        await Process.start(
          updater.path,
          args,
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
        await AppLogger.instance.logInfo(
          'FullPOS closing for update',
          module: 'app_update',
        );
        exit(0);
      } catch (_) {
        await prefs.remove('update_install_target');
        await prefs.remove('update_installer_path');
        await prefs.remove('update_install_attempted_at');
        await DatabaseManager.instance.reopen(
          reason: 'app_update_launch_failed',
        );
        ProductSyncService.instance.start();
        CloudSyncService.instance.startRealtimeSyncEngine();
        rethrow;
      }
    } finally {
      _launching = false;
    }
  }
}

class UpdatePreparationException implements Exception {
  const UpdatePreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}
