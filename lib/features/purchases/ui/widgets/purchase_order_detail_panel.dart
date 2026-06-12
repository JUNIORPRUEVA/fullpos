import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/currency_display.dart';
import '../../data/purchase_order_models.dart';
import '../../providers/purchase_orders_providers.dart';
import 'purchase_ui.dart';

class PurchaseOrderDetailPanel extends ConsumerWidget {
  final void Function(PurchaseOrderDetailDto detail)? onOpenPdf;
  final void Function(int orderId)? onReceive;
  final void Function(PurchaseOrderDetailDto detail)? onDuplicate;
  final void Function(int orderId)? onDelete;

  const PurchaseOrderDetailPanel({
    super.key,
    this.onOpenPdf,
    this.onReceive,
    this.onDuplicate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = CurrencyDisplay.currency();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final detailAsync = ref.watch(purchaseSelectedOrderDetailProvider);

    return Container(
      decoration: purchaseSectionDecoration(context),
      child: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: TextStyle(color: scheme.error)),
        ),
        data: (detail) {
          if (detail == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.paddingL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 46,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Selecciona una orden',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'El detalle aparecerá aquí.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final status = detail.order.status.trim().toUpperCase();
          final isReceived = status == 'RECIBIDA';
          final isPartial = status == 'PARCIAL';
          final canDelete = status == 'PENDIENTE';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Encabezado limpio ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Orden #${detail.order.id ?? '-'}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detail.supplierName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(status: status, scheme: scheme),
                  ],
                ),
              ),

              // ── Metadatos ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _MetaItem(
                      label: 'Emisión',
                      value: dateFormat.format(
                        DateTime.fromMillisecondsSinceEpoch(
                          detail.order.createdAtMs,
                        ),
                      ),
                      scheme: scheme,
                    ),
                    const SizedBox(width: 20),
                    _MetaItem(
                      label: 'Proveedor',
                      value: detail.supplierPhone ?? 'Sin teléfono',
                      scheme: scheme,
                    ),
                  ],
                ),
              ),

              // ── Resumen financiero ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _SummaryItem(
                      label: 'Subtotal',
                      value: currency.format(detail.order.subtotal),
                      scheme: scheme,
                    ),
                    const SizedBox(width: 16),
                    _SummaryItem(
                      label: 'Impuestos',
                      value: currency.format(detail.order.taxAmount),
                      scheme: scheme,
                    ),
                    const SizedBox(width: 16),
                    _SummaryItem(
                      label: 'Total',
                      value: currency.format(detail.order.total),
                      scheme: scheme,
                      isBold: true,
                    ),
                    const Spacer(),
                    _SummaryItem(
                      label: 'Tipo',
                      value: detail.order.isAuto == 1
                          ? 'Automática'
                          : 'Manual',
                      scheme: scheme,
                    ),
                  ],
                ),
              ),

              // ── Botones de acción ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _ActionButton(
                      icon: Icons.picture_as_pdf,
                      label: 'PDF',
                      onPressed: () => onOpenPdf?.call(detail),
                      scheme: scheme,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.inventory_outlined,
                      label: isReceived
                          ? 'Recibida'
                          : (isPartial
                                ? 'Continuar recepción'
                                : 'Recibir'),
                      onPressed: isReceived
                          ? null
                          : () => onReceive?.call(detail.order.id ?? 0),
                      scheme: scheme,
                      filled: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: scheme.outlineVariant.withOpacity(0.3),
              ),
              const SizedBox(height: 8),

              // ── Lista de items ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  children: [
                    // Encabezado de tabla
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Producto',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            'Cant',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            'Costo',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(
                            'Subtotal',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...detail.items.map((it) => _ItemRow(
                          item: it,
                          currency: currency,
                          scheme: scheme,
                        )),

                    // ── Notas ──
                    if ((detail.order.notes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Notas',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail.order.notes!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withOpacity(0.75),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Barra de acciones inferior ──
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withOpacity(0.25),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _BottomAction(
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                      onPressed: canDelete
                          ? () => onDelete?.call(detail.order.id ?? 0)
                          : null,
                      color: AppColors.error,
                      scheme: scheme,
                    ),
                    const SizedBox(width: 12),
                    _BottomAction(
                      icon: Icons.copy,
                      label: 'Duplicar',
                      onPressed: () => onDuplicate?.call(detail),
                      scheme: scheme,
                    ),
                    const Spacer(),
                    _BottomAction(
                      icon: Icons.print_outlined,
                      label: 'Imprimir',
                      onPressed: () => onOpenPdf?.call(detail),
                      scheme: scheme,
                      filled: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Widgets internos ───

class _StatusBadge extends StatelessWidget {
  final String status;
  final ColorScheme scheme;

  const _StatusBadge({required this.status, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final color = status == 'RECIBIDA'
        ? AppColors.success
        : (status == 'PARCIAL' ? AppColors.warning : scheme.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;

  const _MetaItem({
    required this.label,
    required this.value,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;
  final bool isBold;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.scheme,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: isBold ? scheme.primary : scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final ColorScheme scheme;
  final bool filled;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.scheme,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 15),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 15),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
              ),
            ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final PurchaseOrderItemDetailDto item;
  final NumberFormat currency;
  final ColorScheme scheme;

  const _ItemRow({
    required this.item,
    required this.currency,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withOpacity(0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.productCode} • ${item.productName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              item.item.qty.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              currency.format(item.item.unitCost),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              currency.format(item.item.totalLine),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final ColorScheme scheme;
  final Color? color;
  final bool filled;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.scheme,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? scheme.primary;

    if (filled) {
      return SizedBox(
        height: 32,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: fg,
            foregroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          side: BorderSide(color: fg.withOpacity(0.3)),
        ),
      ),
    );
  }
}
