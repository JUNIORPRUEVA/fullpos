import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_manager.dart';
import '../logging/app_logger.dart';
import '../services/cloud_sync_service.dart';
import '../sync/product_sync_service.dart';
import '../window/window_service.dart';
import 'app_update_policy.dart';

class InstallerLauncher {
  static const _allowDebugLaunch = bool.fromEnvironment(
    'FULLPOS_ALLOW_INSTALLER_LAUNCH',
    defaultValue: false,
  );

  bool _launching = false;
  bool get isLaunching => _launching;

  Future<void> launch(File installer, AppUpdatePolicy policy) async {
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('update_install_target', policy.latest.toString());
      await prefs.setString('update_installer_path', installer.path);
      await prefs.setInt(
        'update_install_attempted_at',
        DateTime.now().millisecondsSinceEpoch,
      );

      CloudSyncService.instance.stopRealtimeSyncEngine();
      ProductSyncService.instance.stop();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await DatabaseManager.instance.close(reason: 'app_update_install');
      await AppLogger.instance.logInfo(
        'Launching verified installer target=${policy.latest}',
        module: 'app_update',
      );
      await AppLogger.instance.flush();
      await WindowService.setPreventClose(false);

      try {
        await Process.start(
          installer.path,
          const ['/SP-', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
          mode: ProcessStartMode.detached,
          runInShell: false,
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
