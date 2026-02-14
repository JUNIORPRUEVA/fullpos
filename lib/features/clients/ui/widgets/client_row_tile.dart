import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../data/client_model.dart';

/// Widget compacto para mostrar un cliente en una sola linea (tipo tabla)
class ClientRowTile extends StatelessWidget {
  final ClientModel client;
  final bool isSelected;
  final VoidCallback onViewDetails;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onToggleCredit;
  final VoidCallback onDelete;

  const ClientRowTile({
    super.key,
    required this.client,
    this.isSelected = false,
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
    final statusColor = client.isActive ? scheme.tertiary : scheme.outline;
    final creditColor = client.hasCredit ? scheme.primary : scheme.outline;

    final bgColor = isSelected
        ? scheme.primaryContainer.withOpacity(0.35)
        : scheme.surface;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingM,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
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
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSizes.paddingS),
                    Expanded(
                      child: Text(
                        client.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              Expanded(
                flex: 1,
                child: Text(
                  client.rnc?.isNotEmpty == true ? client.rnc! : '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              Expanded(
                flex: 1,
                child: Text(
                  client.cedula?.isNotEmpty == true ? client.cedula! : '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              SizedBox(
                width: 64,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    client.isActive ? 'Activo' : 'Inactivo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              SizedBox(
                width: 88,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: creditColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: creditColor.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Icon(
                        client.hasCredit ? Icons.credit_card : Icons.block,
                        size: 12,
                        color: scheme.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          client.hasCredit ? 'Crédito' : 'Sin crédito',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              SizedBox(
                width: 86,
                child: Text(
                  createdDate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: AppSizes.paddingS),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                icon: Icon(
                  Icons.more_vert,
                  color: scheme.onSurface.withOpacity(0.7),
                  size: 18,
                ),
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
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 10),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_active',
                    child: Row(
                      children: [
                        Icon(
                          client.isActive ? Icons.block : Icons.check_circle,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(client.isActive ? 'Desactivar' : 'Activar'),
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
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          client.hasCredit ? 'Quitar crédito' : 'Dar crédito',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: scheme.error),
                        const SizedBox(width: 10),
                        Text('Eliminar', style: TextStyle(color: scheme.error)),
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
