import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../data/purchase_order_models.dart';
import '../../providers/purchase_orders_providers.dart';

class PurchaseOrderDetailPanel extends ConsumerWidget {
  final void Function(PurchaseOrderDetailDto detail)? onOpenPdf;
  final void Function(int orderId)? onReceive;
  final void Function(PurchaseOrderDetailDto detail)? onDuplicate;

  const PurchaseOrderDetailPanel({
    super.key,
    this.onOpenPdf,
    this.onReceive,
    this.onDuplicate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat('#,##0.00', 'en_US');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final detailAsync = ref.watch(purchaseSelectedOrderDetailProvider);

    final decoration = BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withOpacity(0.10),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );

    return Container(
      decoration: decoration,
      child: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: TextStyle(color: scheme.error),
          ),
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
                      'El detalle aparecerá aquí (panel fijo).',
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

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Orden #${detail.order.id ?? '-'}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detail.supplierName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface.withOpacity(0.8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateFormat.format(
                              DateTime.fromMillisecondsSinceEpoch(
                                detail.order.createdAtMs,
                              ),
                            ),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => onOpenPdf?.call(detail),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Abrir PDF'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: isReceived
                          ? null
                          : () => onReceive?.call(detail.order.id ?? 0),
                      icon: const Icon(Icons.inventory_outlined),
                      label: Text(isReceived ? 'Recibida' : 'Marcar recibida'),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.45)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSizes.paddingM),
                  children: [
                    _InfoGrid(detail: detail, currency: currency),
                    const SizedBox(height: 12),
                    Text(
                      'Items',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ItemsTable(detail: detail, currency: currency),
                    if ((detail.order.notes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Notas',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.outlineVariant.withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          detail.order.notes!.trim(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withOpacity(0.45),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onDuplicate?.call(detail),
                        icon: const Icon(Icons.copy),
                        label: const Text('Duplicar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => onOpenPdf?.call(detail),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Imprimir'),
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                        ),
                      ),
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

class _InfoGrid extends StatelessWidget {
  final PurchaseOrderDetailDto detail;
  final NumberFormat currency;

  const _InfoGrid({required this.detail, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget chip(String label, String value, {Color? bg}) {
      final background = bg ?? scheme.surfaceContainerHighest.withOpacity(0.35);
      final fg = ColorUtils.readableTextColor(background);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg.withOpacity(0.8),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('Estado', detail.order.status.trim().toUpperCase(),
            bg: detail.order.status.trim().toUpperCase() == 'RECIBIDA'
                ? AppColors.successLight
                : AppColors.warningLight),
        chip('Subtotal', currency.format(detail.order.subtotal)),
        chip('Impuestos', currency.format(detail.order.taxAmount)),
        chip('Total', currency.format(detail.order.total),
            bg: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)),
        chip('Tipo', detail.order.isAuto == 1 ? 'Automática' : 'Manual'),
      ],
    );
  }
}

class _ItemsTable extends StatelessWidget {
  final PurchaseOrderDetailDto detail;
  final NumberFormat currency;

  const _ItemsTable({required this.detail, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: scheme.surfaceContainerHighest.withOpacity(0.35),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Expanded(child: Text('Producto')),
                const SizedBox(
                  width: 70,
                  child: Text('Cant', textAlign: TextAlign.right),
                ),
                const SizedBox(width: 90, child: Text('Costo', textAlign: TextAlign.right)),
                const SizedBox(
                  width: 100,
                  child: Text('Subtotal', textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          ...detail.items.map((it) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withOpacity(0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${it.productCode} • ${it.productName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      it.item.qty.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      currency.format(it.item.unitCost),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(
                      currency.format(it.item.totalLine),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
