import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../data/client_model.dart';

/// Widget compacto para mostrar un cliente en una sola linea (tipo tabla)
class ClientRowTile extends StatelessWidget {
  final ClientModel client;
  final VoidCallback onViewDetails;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onToggleCredit;
  final VoidCallback onDelete;

  const ClientRowTile({
    super.key,
    required this.client,
    required this.onViewDetails,
    required this.onEdit,
    required this.onToggleActive,
    required this.onToggleCredit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yyyy');
    final createdDate = dateFormat.format(
      DateTime.fromMillisecondsSinceEpoch(client.createdAtMs),
    );
    final mutedText = scheme.onSurface.withOpacity(0.7);
    final roleColor = client.isActive ? scheme.tertiary : scheme.outline;
    final creditColor = client.hasCredit ? scheme.primary : scheme.outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingM,
            vertical: 8,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: roleColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSizes.paddingS),
                    Expanded(
                      child: Text(
                        client.nombre,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.paddingM),
              Expanded(
                flex: 1,
                child: Text(
                  client.telefono?.isNotEmpty == true ? client.telefono! : '-',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              Expanded(
                flex: 1,
                child: Text(
                  client.rnc?.isNotEmpty == true ? client.rnc! : '-',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              Expanded(
                flex: 1,
                child: Text(
                  client.cedula?.isNotEmpty == true ? client.cedula! : '-',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  client.isActive ? 'Activo' : 'Inactivo',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: roleColor,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: creditColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: creditColor.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      client.hasCredit ? Icons.credit_card : Icons.block,
                      size: 12,
                      color: creditColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      client.hasCredit ? 'Credito' : 'Sin credito',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: creditColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              SizedBox(
                width: 86,
                child: Text(
                  createdDate,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: scheme.onSurface, size: 18),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                      break;
                    case 'toggle_active':
                      onToggleActive();
                      break;
                    case 'toggle_credit':
                      onToggleCredit();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('Editar', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_active',
                    child: Row(
                      children: [
                        Icon(
                          client.isActive ? Icons.block : Icons.check_circle,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          client.isActive ? 'Desactivar' : 'Activar',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_credit',
                    child: Row(
                      children: [
                        Icon(
                          client.hasCredit
                              ? Icons.credit_card_off
                              : Icons.credit_card,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          client.hasCredit ? 'Quitar Credito' : 'Dar Credito',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: scheme.error),
                        const SizedBox(width: 8),
                        Text(
                          'Eliminar',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
