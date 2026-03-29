import 'package:flutter/material.dart';

class DangerZoneActions extends StatelessWidget {
  const DangerZoneActions({
    super.key,
    required this.onResetLocal,
    required this.onDeleteLocal,
  });

  final VoidCallback onResetLocal;
  final VoidCallback onDeleteLocal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zona roja (acciones peligrosas)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Solo administradores. Requiere confirmación y PIN.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onResetLocal,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Resetear BD Local'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
              ),
              FilledButton.icon(
                onPressed: onDeleteLocal,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Borrar TODO'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
