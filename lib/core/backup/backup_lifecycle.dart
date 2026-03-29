import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/business_settings_provider.dart';
import 'backup_models.dart';
import 'backup_orchestrator.dart';

class BackupLifecycle extends ConsumerStatefulWidget {
  const BackupLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BackupLifecycle> createState() => _BackupLifecycleState();
}

class _BackupLifecycleState extends ConsumerState<BackupLifecycle>
    with WidgetsBindingObserver {
  Timer? _lifecycleBackupTimer;

  static const Duration _autoBackupDelayAfterPause = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleBackupTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = ref.read(businessSettingsProvider).enableAutoBackup;
    if (!enabled) {
      _cancelPendingLifecycleBackup();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _cancelPendingLifecycleBackup();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _scheduleLifecycleBackup();
      return;
    }

    if (state == AppLifecycleState.detached) {
      _cancelPendingLifecycleBackup();
      unawaited(
        BackupOrchestrator.instance.triggerAutoBackupIfAllowed(
          enabled: true,
          trigger: BackupTrigger.autoLifecycle,
        ),
      );
    }
  }

  void _scheduleLifecycleBackup() {
    _lifecycleBackupTimer?.cancel();
    _lifecycleBackupTimer = Timer(_autoBackupDelayAfterPause, () {
      unawaited(
        BackupOrchestrator.instance.triggerAutoBackupIfAllowed(
          enabled: true,
          trigger: BackupTrigger.autoLifecycle,
        ),
      );
    });
  }

  void _cancelPendingLifecycleBackup() {
    _lifecycleBackupTimer?.cancel();
    _lifecycleBackupTimer = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
