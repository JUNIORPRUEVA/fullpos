import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../core/backup/backup_models.dart';

class BackupHistoryList extends StatelessWidget {
  const BackupHistoryList({
    super.key,
    required this.history,
    required this.onRestoreLocal,
    required this.onRestoreCloud,
    required this.onRetryCloudUpload,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<BackupHistoryEntry> history;
  final ValueChanged<BackupHistoryEntry> onRestoreLocal;
  final ValueChanged<BackupHistoryEntry> onRestoreCloud;
  final ValueChanged<BackupHistoryEntry> onRetryCloudUpload;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(child: Text('Sin historial de backups.'));
    }

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = history[index];
        final created = DateTime.fromMillisecondsSinceEpoch(
          entry.createdAtMs,
        ).toLocal();
        final fileName = entry.filePath != null
            ? p.basename(entry.filePath!)
            : (entry.cloudBackupId ?? 'cloud');
        final sizeKb = entry.sizeBytes != null
            ? (entry.sizeBytes! / 1024).round()
            : null;
        final statusColor = _statusColor(context, entry.status);
        final hasLocal =
            entry.filePath != null && File(entry.filePath!).existsSync();
        final canRetryCloud =
            entry.mode == BackupMode.cloud &&
            entry.cloudBackupId == null &&
            hasLocal &&
            (entry.status == BackupStatus.failed ||
                entry.status == BackupStatus.pendingUpload);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      entry.mode == BackupMode.cloud
                          ? Icons.cloud
                          : Icons.archive,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _statusLabel(entry.status),
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: statusColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Fecha: $created',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (sizeKb != null)
                  Text(
                    'Tamaño: ${sizeKb}KB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (entry.notes != null)
                  Text(
                    'Notas: ${entry.notes}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (entry.errorMessage != null)
                  Text(
                    _errorLabel(entry.errorMessage!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _isPendingError(entry.errorMessage!)
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (entry.cloudBackupId != null)
                      OutlinedButton.icon(
                        onPressed: () => onRestoreCloud(entry),
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Restaurar nube'),
                      ),
                    if (canRetryCloud)
                      FilledButton.icon(
                        onPressed: () => onRetryCloudUpload(entry),
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('Reintentar nube'),
                      ),
                    if (hasLocal)
                      OutlinedButton.icon(
                        onPressed: () => onRestoreLocal(entry),
                        icon: const Icon(Icons.restore),
                        label: const Text('Restaurar local'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(BuildContext context, BackupStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case BackupStatus.success:
        return scheme.primary;
      case BackupStatus.failed:
        return scheme.error;
      case BackupStatus.pendingUpload:
        return scheme.tertiary;
      case BackupStatus.inProgress:
        return scheme.secondary;
    }
  }

  String _statusLabel(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return 'OK';
      case BackupStatus.failed:
        return 'FALLÓ';
      case BackupStatus.pendingUpload:
        return 'PENDIENTE';
      case BackupStatus.inProgress:
        return 'PROCESANDO';
    }
  }

  String _errorLabel(String error) {
    const prefix = 'PENDING_UPLOAD:';
    final trimmed = error.trim();
    if (trimmed.startsWith(prefix)) {
      final reason = trimmed.substring(prefix.length).trim();
      return 'Pendiente: ${reason.isEmpty ? 'reintentar' : reason}';
    }
    return 'Error: $error';
  }

  bool _isPendingError(String error) {
    const prefix = 'PENDING_UPLOAD:';
    return error.trim().startsWith(prefix);
  }
}
