import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
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
    final textColor = AppColors.textDark;
    final mutedText = AppColors.textDarkMuted;
    final statusColor = client.isActive
        ? const Color(0xFF16A34A)
        : scheme.outline;
    final creditColor = scheme.primary;
    final initials = client.nombre.trim().isNotEmpty
        ? client.nombre.trim().substring(0, 1).toUpperCase()
        : '?';

    final selectedBg = scheme.primary.withOpacity(0.09);
    final selectedBorder = scheme.primary.withOpacity(0.62);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius: BorderRadius.circular(12),
        hoverColor: scheme.primary.withOpacity(0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 60, maxHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? selectedBorder : Colors.transparent,
              width: isSelected ? 1 : 0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: scheme.primary.withOpacity(0.12),
                      foregroundColor: scheme.primary,
                      child: Text(
                        initials,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        client.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Text(
                  client.rnc?.isNotEmpty == true ? client.rnc! : '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Text(
                  client.cedula?.isNotEmpty == true ? client.cedula! : '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(
                      client.isActive ? 0.14 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withOpacity(0.30)),
                  ),
                  child: Text(
                    client.isActive ? 'Activo' : 'Inactivo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 86,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: creditColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: creditColor.withOpacity(0.28)),
                  ),
                  child: Text(
                    client.hasCredit ? 'Crédito' : 'Sin crédito',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: Text(
                  createdDate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                icon: Icon(Icons.more_vert, color: mutedText, size: 17),
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
