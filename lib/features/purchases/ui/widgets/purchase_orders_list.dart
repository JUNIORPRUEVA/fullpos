import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/theme/color_utils.dart';
import '../../providers/purchase_orders_providers.dart';

class PurchaseOrdersList extends ConsumerWidget {
  final void Function(int orderId)? onOpenPdf;
  final void Function(int orderId)? onReceive;
  final void Function(int orderId)? onEdit;

  const PurchaseOrdersList({
    super.key,
    this.onOpenPdf,
    this.onReceive,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusTheme = theme.extension<AppStatusTheme>();
    final currency = NumberFormat('#,##0.00', 'en_US');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final ordersAsync = ref.watch(purchaseOrdersListProvider);
    final selectedId = ref.watch(purchaseSelectedOrderIdProvider);

    Color statusColor(String status) {
      final normalized = status.trim().toUpperCase();
      if (normalized == 'RECIBIDA') {
        return statusTheme?.success ?? scheme.tertiary;
      }
      return statusTheme?.warning ?? scheme.secondary;
    }

    return ordersAsync.when(
      loading: () => const _OrdersListSkeleton(),
      error: (e, _) => Center(
        child: Text(
          'Error cargando órdenes: $e',
          style: TextStyle(color: scheme.error),
        ),
      ),
      data: (orders) {
        if (orders.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppSizes.radiusXL),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.55),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 44,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No hay órdenes todavía',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Crea una orden manual o automática para verla aquí.',
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

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: AppSizes.paddingL),
          itemCount: orders.length + 1,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.4)),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.paddingM,
                  vertical: 10,
                ),
                color: scheme.surfaceContainerHighest.withOpacity(0.35),
                child: Row(
                  children: [
                    const SizedBox(width: 70, child: Text('Orden')),
                    Expanded(child: Text('Proveedor')),
                    const SizedBox(width: 150, child: Text('Fecha')),
                    const SizedBox(
                      width: 120,
                      child: Text('Total', textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: 120, child: Text('Estado')),
                    const SizedBox(width: 120, child: Text('Acciones')),
                  ],
                ),
              );
            }

            final dto = orders[index - 1];
            final id = dto.order.id ?? 0;
            final isSelected = selectedId == id;
            final bg = isSelected
                ? scheme.primaryContainer.withOpacity(0.35)
                : scheme.surface;

            final created = DateTime.fromMillisecondsSinceEpoch(
              dto.order.createdAtMs,
            );
            final status = dto.order.status.trim().toUpperCase();
            final statusBg = statusColor(status);
            final statusFg = ColorUtils.readableTextColor(statusBg);

            return Material(
              color: bg,
              child: InkWell(
                onTap: () {
                  ref.read(purchaseSelectedOrderIdProvider.notifier).state = id;
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.paddingM,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          '#$id',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          dto.supplierName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: Text(
                          dateFormat.format(created),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          currency.format(dto.order.total),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusFg,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Ver PDF',
                              onPressed: id <= 0
                                  ? null
                                  : () => onOpenPdf?.call(id),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                            IconButton(
                              tooltip: 'Recibir',
                              onPressed: status == 'RECIBIDA'
                                  ? null
                                  : (id <= 0
                                        ? null
                                        : () => onReceive?.call(id)),
                              icon: const Icon(Icons.inventory_outlined),
                            ),
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: status == 'RECIBIDA'
                                  ? null
                                  : (id <= 0 ? null : () => onEdit?.call(id)),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OrdersListSkeleton extends StatelessWidget {
  const _OrdersListSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withOpacity(0.55);
    final line = scheme.outlineVariant.withOpacity(0.25);

    Widget row() {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingM,
          vertical: 10,
        ),
        child: Row(
          children: [
            Container(width: 56, height: 12, color: base),
            const SizedBox(width: 14),
            Expanded(child: Container(height: 12, color: base)),
            const SizedBox(width: 14),
            Container(width: 130, height: 12, color: base),
            const SizedBox(width: 14),
            Container(width: 90, height: 12, color: base),
            const SizedBox(width: 14),
            Container(
              width: 90,
              height: 22,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 14),
            Container(
              width: 96,
              height: 22,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: AppSizes.paddingL),
      itemCount: 10,
      separatorBuilder: (_, __) => Divider(height: 1, color: line),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingM,
              vertical: 10,
            ),
            color: scheme.surfaceContainerHighest.withOpacity(0.35),
            child: const Row(
              children: [
                SizedBox(width: 70, child: Text('Orden')),
                Expanded(child: Text('Proveedor')),
                SizedBox(width: 150, child: Text('Fecha')),
                SizedBox(
                  width: 120,
                  child: Text('Total', textAlign: TextAlign.right),
                ),
                SizedBox(width: 120, child: Text('Estado')),
                SizedBox(width: 120, child: Text('Acciones')),
              ],
            ),
          );
        }
        return row();
      },
    );
  }
}
