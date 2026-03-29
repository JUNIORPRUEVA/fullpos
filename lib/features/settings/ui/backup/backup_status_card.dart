import 'package:flutter/material.dart';

import '../../../../core/backup/cloud_status_service.dart';

class BackupStatusCard extends StatelessWidget {
  const BackupStatusCard({
    super.key,
    required this.status,
    required this.keepLocalCopy,
    required this.onKeepLocalCopyChanged,
  });

  final CloudStatus status;
  final bool keepLocalCopy;
  final ValueChanged<bool> onKeepLocalCopyChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    String destination;
    if (status.canUseCloudBackup) {
      destination = keepLocalCopy ? 'Nube + Local' : 'Nube';
    } else if (status.isCloudEnabled) {
      destination = 'Local (pendiente de subir)';
    } else {
      destination = 'Local';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estado de backup',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _StatusRow(
          label: 'Nube',
          value: status.isCloudEnabled ? 'Activa' : 'Inactiva',
          color: status.isCloudEnabled ? scheme.primary : scheme.error,
        ),
        const Divider(),
        _StatusRow(
          label: 'Destino actual',
          value: destination,
          color: scheme.secondary,
        ),
        if (status.reason != null) ...[
          const SizedBox(height: 6),
          Text(
            status.reason!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          value: keepLocalCopy,
          onChanged: status.canUseCloudBackup
              ? onKeepLocalCopyChanged
              : null,
          title: const Text('Mantener copia local adicional'),
          subtitle: const Text('Opcional cuando la nube está activa'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
