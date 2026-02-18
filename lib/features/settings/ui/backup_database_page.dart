import 'package:flutter/material.dart';

import '../../../core/backup/backup_models.dart';
import '../../../core/backup/backup_orchestrator.dart';
import '../../../core/backup/backup_paths.dart';
import '../../../core/backup/backup_prefs.dart';
import '../../../core/backup/backup_repository.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/backup/cloud_status_service.dart';
import '../../../core/backup/danger_actions_service.dart';
import '../../../core/backup/restore_service.dart';
import '../../../core/session/session_manager.dart';
import 'backup/backup_history_list.dart';
import 'backup/backup_status_card.dart';
import 'backup/confirm_phrase_dialog.dart';
import 'backup/danger_zone_actions.dart';
import 'settings_layout.dart';

class BackupDatabasePage extends StatefulWidget {
  const BackupDatabasePage({super.key});

  @override
  State<BackupDatabasePage> createState() => _BackupDatabasePageState();
}

class _BackupDatabasePageState extends State<BackupDatabasePage> {
  bool _loading = true;
  bool _busy = false;
  CloudStatus? _status;
  bool _keepLocalCopy = false;
  int _retention = 15;
  List<BackupHistoryEntry> _history = const [];
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final status = await CloudStatusService.instance.checkStatus();
    final keepLocalCopy = await BackupPrefs.instance.getKeepLocalCopy();
    final retention = await BackupService.instance.getRetentionCount();
    final history = await BackupRepository.instance.listHistory(limit: 60);
    final isAdmin = await SessionManager.isAdmin();

    if (!mounted) return;
    setState(() {
      _status = status;
      _keepLocalCopy = keepLocalCopy;
      _retention = retention;
      _history = history;
      _isAdmin = isAdmin;
      _loading = false;
    });
  }

  Future<void> _createBackupNow() async {
    if (_busy) return;
    setState(() => _busy = true);

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'Guardando backup...'),
    );

    try {
      final result = await BackupOrchestrator.instance.createBackup(
        trigger: BackupTrigger.manual,
        maxWait: const Duration(minutes: 2),
      );

      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }

      if (!mounted) return;
      await _load();

      if (result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.messageUser ?? 'Backup completado.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.messageUser ?? 'Backup fallido.')),
        );
      }
    } finally {
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restoreLocal(BackupHistoryEntry entry) async {
    if (entry.filePath == null) return;
    final ok = await _confirmRestore();
    if (!mounted) return;
    if (!ok) return;

    setState(() => _busy = true);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'Restaurando backup...'),
    );

    try {
      final result = await RestoreService.instance.restoreLocal(
        zipPath: entry.filePath!,
        expectedChecksumSha256: entry.checksumSha256,
      );
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? 'Backup restaurado. Reinicia la app.'
                : (result.messageUser ?? 'No se pudo restaurar.'),
          ),
        ),
      );
    } finally {
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restoreCloud(BackupHistoryEntry entry) async {
    if (entry.cloudBackupId == null) return;
    final ok = await _confirmRestore();
    if (!mounted) return;
    if (!ok) return;

    setState(() => _busy = true);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'Restaurando desde nube...'),
    );

    try {
      final result = await RestoreService.instance.restoreFromCloud(
        cloudBackupId: entry.cloudBackupId!,
        expectedChecksumSha256: entry.checksumSha256,
      );
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? 'Backup de nube restaurado. Reinicia la app.'
                : (result.messageUser ?? 'No se pudo restaurar.'),
          ),
        ),
      );
    } finally {
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retryCloudUpload(BackupHistoryEntry entry) async {
    if (_busy) return;

    setState(() => _busy = true);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'Reintentando subida...'),
    );

    try {
      final result = await BackupOrchestrator.instance.retryCloudUpload(
        entry: entry,
      );
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? 'Subida a nube completada.'
                : (result.messageUser ?? 'No se pudo subir.'),
          ),
        ),
      );
    } finally {
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: const Text(
          'Esto reemplazara los datos actuales.\n\nDeseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Si, restaurar'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _runDiagnostics() async {
    if (_busy) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'Ejecutando diagnostico...'),
    );

    String message;
    try {
      final tempDir = await BackupPaths.tempWorkDir();
      final result = await BackupService.instance.createBackup(
        trigger: BackupTrigger.manual,
        outputDir: tempDir,
        recordHistory: false,
        maxWait: const Duration(minutes: 2),
      );
      if (!result.ok || result.path == null) {
        message = 'Diagnostico fallo: ${result.messageUser ?? 'error'}';
      } else {
        final ok = await BackupService.instance.verifyZipIntegrity(
          result.path!,
          timeout: const Duration(seconds: 20),
        );
        message = ok == true
            ? 'Diagnostico OK: backup valido.'
            : 'Diagnostico fallo: integridad no valida.';
      }
    } finally {
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Backup Diagnostics'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _setRetention(int value) async {
    await BackupService.instance.setRetentionCount(value);
    if (!mounted) return;
    setState(() => _retention = value);
  }

  Future<void> _onKeepLocalCopy(bool value) async {
    await BackupPrefs.instance.setKeepLocalCopy(value);
    if (!mounted) return;
    setState(() => _keepLocalCopy = value);
  }

  Future<void> _handleDangerAction({
    required String title,
    required String message,
    required String phraseHint,
    required String confirmText,
    required Future<DangerActionResult> Function(String phrase, String pin)
    action,
  }) async {
    final result = await showDialog<ConfirmPhraseResult>(
      context: context,
      builder: (_) => ConfirmPhraseDialog(
        title: title,
        message: message,
        phraseHint: phraseHint,
        confirmText: confirmText,
      ),
    );
    if (result == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'Procesando...'),
    );

    try {
      final outcome = await action(result.phrase, result.pin);
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(outcome.messageUser)));
    } finally {
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _runDiagnostics,
          child: const Text('Backup y Base de Datos'),
        ),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading || status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                BackupStatusCard(
                  status: status,
                  keepLocalCopy: _keepLocalCopy,
                  onKeepLocalCopyChanged: _busy ? (_) {} : _onKeepLocalCopy,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _createBackupNow,
                      icon: const Icon(Icons.save),
                      label: const Text('Hacer backup ahora'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Retencion'),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: _retention,
                          onChanged: _busy ? null : (v) => _setRetention(v!),
                          items: const [5, 10, 15, 20, 30]
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('$v'),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                BackupHistoryList(
                  history: _history,
                  onRestoreLocal: _busy ? (_) {} : _restoreLocal,
                  onRestoreCloud: _busy ? (_) {} : _restoreCloud,
                  onRetryCloudUpload: _busy ? (_) {} : _retryCloudUpload,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                ),
                const SizedBox(height: 12),
                if (_isAdmin)
                  DangerZoneActions(
                    onResetLocal: _busy
                        ? () {}
                        : () => _handleDangerAction(
                            title: 'Resetear Base de Datos',
                            message:
                                'Deja la empresa en limpio. Esta accion no se puede deshacer.',
                            phraseHint: 'Escribe: RESETEAR EMPRESA',
                            confirmText: 'Resetear',
                            action: (phrase, pin) => DangerActionsService
                                .instance
                                .resetLocal(confirmedPhrase: phrase, pin: pin),
                          ),
                    onDeleteLocal: _busy
                        ? () {}
                        : () => _handleDangerAction(
                            title: 'Borrar TODO',
                            message:
                                'Elimina la base de datos completa y todos los datos.',
                            phraseHint: 'Escribe: BORRAR TODO FULLPOS',
                            confirmText: 'Borrar TODO',
                            action: (phrase, pin) =>
                                DangerActionsService.instance.deleteAllLocal(
                                  confirmedPhrase: phrase,
                                  pin: pin,
                                ),
                          ),
                  ),
              ],
            ),
      ),
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
