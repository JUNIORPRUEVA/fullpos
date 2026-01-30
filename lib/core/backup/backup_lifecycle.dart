import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/settings/providers/business_settings_provider.dart';
import '../logging/app_logger.dart';
import 'backup_models.dart';
import 'backup_orchestrator.dart';

class BackupLifecycle extends ConsumerStatefulWidget {
  const BackupLifecycle({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<BackupLifecycle> createState() => _BackupLifecycleState();
}

class _BackupLifecycleState extends ConsumerState<BackupLifecycle>
    with WidgetsBindingObserver, WindowListener {
  bool _closing = false;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (_isDesktop) {
      unawaited(_installWindowCloseHook());
    }
  }

  Future<void> _installWindowCloseHook() async {
    try {
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    } catch (_) {
      // Ignorar si el plugin falla.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isDesktop) {
      try {
        windowManager.removeListener(this);
      } catch (_) {
        // Ignorar.
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = ref.read(businessSettingsProvider).enableAutoBackup;
    if (!enabled) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(
        BackupOrchestrator.instance.triggerAutoBackupIfAllowed(
          enabled: true,
          trigger: BackupTrigger.autoLifecycle,
        ),
      );
    }
  }

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;

    final enabled = ref.read(businessSettingsProvider).enableAutoBackup;

    if (enabled) {
      try {
        // No bloquear el cierre indefinidamente: timeout corto.
        await BackupOrchestrator.instance
            .createBackup(
              trigger: BackupTrigger.autoWindowClose,
              maxWait: const Duration(seconds: 5),
            )
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        unawaited(
          AppLogger.instance.logWarn(
            'Auto-backup al cerrar falló/timeout: $e',
            module: 'backup',
          ),
        );
      }
    }

    try {
      await windowManager.destroy();
    } catch (_) {
      // Ignorar.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
