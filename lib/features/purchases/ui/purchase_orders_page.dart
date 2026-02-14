import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../products/models/product_model.dart';
import '../../products/models/supplier_model.dart';
import '../data/purchase_order_models.dart';
import '../data/purchases_repository.dart';
import '../providers/purchase_catalog_provider.dart';
import '../providers/purchase_draft_provider.dart';
import '../providers/purchase_orders_providers.dart';
import '../utils/purchase_order_pdf_launcher.dart';
import 'widgets/purchase_order_detail_panel.dart';
import 'widgets/purchase_orders_list.dart';

class PurchaseOrdersPage extends ConsumerStatefulWidget {
  const PurchaseOrdersPage({super.key});

  @override
  ConsumerState<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends ConsumerState<PurchaseOrdersPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateOnly = DateFormat('dd/MM/yyyy');

    final filters = ref.watch(purchaseOrdersFiltersProvider);
    final suppliersAsync = ref.watch(purchaseSuppliersProvider);

    if (_searchCtrl.text != filters.query) {
      _searchCtrl.value = TextEditingValue(
        text: filters.query,
        selection: TextSelection.collapsed(offset: filters.query.length),
      );
    }

    Widget header() {
      return Container(
        padding: const EdgeInsets.all(AppSizes.paddingM),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 980;

            Future<void> pickRange() async {
              final now = DateTime.now();
              final initial = filters.range;
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(now.year + 20),
                initialDateRange: initial,
                saveText: 'Aplicar',
              );
              if (picked == null) return;

              final normalized = DateTimeRange(
                start: DateTime(
                  picked.start.year,
                  picked.start.month,
                  picked.start.day,
                ),
                end: DateTime(
                  picked.end.year,
                  picked.end.month,
                  picked.end.day,
                  23,
                  59,
                  59,
                  999,
                ),
              );

              ref.read(purchaseOrdersFiltersProvider.notifier).state = filters
                  .copyWith(range: normalized);
            }

            final rangeLabel = filters.range == null
                ? 'Rango'
                : '${dateOnly.format(filters.range!.start)} - ${dateOnly.format(filters.range!.end)}';

            final range = OutlinedButton.icon(
              onPressed: pickRange,
              icon: const Icon(Icons.date_range),
              label: Text(rangeLabel, overflow: TextOverflow.ellipsis),
            );

            final clearRange = IconButton(
              tooltip: 'Limpiar rango',
              onPressed: filters.range == null
                  ? null
                  : () {
                      ref.read(purchaseOrdersFiltersProvider.notifier).state =
                          filters.copyWith(clearRange: true);
                    },
              icon: const Icon(Icons.filter_alt_off_outlined),
            );

            final search = TextField(
              controller: _searchCtrl,
              onSubmitted: (_) {
                ref.read(purchaseOrdersFiltersProvider.notifier).state = filters
                    .copyWith(query: _searchCtrl.text);
              },
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por proveedor o #orden',
                border: OutlineInputBorder(),
              ),
            );

            final status = DropdownButtonFormField<String?>(
              value: filters.status,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Estado',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todos')),
                DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendiente')),
                DropdownMenuItem(value: 'RECIBIDA', child: Text('Recibida')),
              ],
              onChanged: (v) {
                ref.read(purchaseOrdersFiltersProvider.notifier).state = filters
                    .copyWith(status: v);
              },
            );

            final supplier = suppliersAsync.when(
              data: (suppliers) {
                final items = <DropdownMenuItem<int?>>[
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ...suppliers.map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ];

                return DropdownButtonFormField<int?>(
                  value: filters.supplierId,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Proveedor',
                    border: OutlineInputBorder(),
                  ),
                  items: items,
                  onChanged: (v) {
                    ref.read(purchaseOrdersFiltersProvider.notifier).state =
                        filters.copyWith(supplierId: v);
                  },
                );
              },
              loading: () => const SizedBox(
                height: 48,
                child: Center(child: LinearProgressIndicator(minHeight: 2)),
              ),
              error: (e, _) => Text(
                'Error proveedores: $e',
                style: TextStyle(color: scheme.error),
              ),
            );

            final newOrder = FilledButton.icon(
              onPressed: () => context.go('/purchases/manual'),
              icon: const Icon(Icons.add),
              label: const Text('Nueva Orden'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            );

            final refresh = IconButton(
              tooltip: 'Actualizar',
              onPressed: () {
                ref.invalidate(purchaseOrdersListProvider);
                ref.invalidate(purchaseSelectedOrderDetailProvider);
              },
              style: IconButton.styleFrom(
                backgroundColor: scheme.surfaceContainerHighest.withOpacity(
                  0.4,
                ),
              ),
              icon: const Icon(Icons.refresh),
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Registro de Órdenes',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      refresh,
                    ],
                  ),
                  const SizedBox(height: 10),
                  search,
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: status),
                      const SizedBox(width: 10),
                      Expanded(child: supplier),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: range),
                      const SizedBox(width: 10),
                      clearRange,
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: newOrder),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: Text(
                    'Registro de Órdenes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SizedBox(width: 360, child: search),
                const SizedBox(width: 10),
                SizedBox(width: 160, child: status),
                const SizedBox(width: 10),
                SizedBox(width: 240, child: supplier),
                const SizedBox(width: 10),
                SizedBox(width: 260, child: range),
                clearRange,
                const SizedBox(width: 10),
                refresh,
                const SizedBox(width: 10),
                newOrder,
              ],
            );
          },
        ),
      );
    }

    Future<bool> confirmOverwriteDraftIfDirty() async {
      final draft = ref.read(purchaseDraftProvider);
      if (!draft.hasChanges) return true;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) {
          return AlertDialog(
            title: const Text('Reemplazar borrador'),
            content: const Text(
              'Ya tienes una orden en borrador. ¿Deseas reemplazarla con la orden duplicada?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Reemplazar'),
              ),
            ],
          );
        },
      );

      return confirm == true;
    }

    Future<void> duplicateToDraft(PurchaseOrderDetailDto detail) async {
      final ok = await confirmOverwriteDraftIfDirty();
      if (!ok) return;
      if (!context.mounted) return;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final supplier = SupplierModel(
        id: detail.order.supplierId,
        name: detail.supplierName,
        phone: detail.supplierPhone,
        note: null,
        isActive: true,
        deletedAtMs: null,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );

      final lines = detail.items
          .map(
            (it) => PurchaseDraftLine(
              product: ProductModel(
                id: it.item.productId,
                code: it.productCode,
                name: it.productName,
                supplierId: detail.order.supplierId,
                purchasePrice: it.item.unitCost,
                salePrice: 0,
                stock: 0,
                reservedStock: 0,
                stockMin: 0,
                isActive: true,
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
              ),
              qty: it.item.qty,
              unitCost: it.item.unitCost,
            ),
          )
          .toList(growable: false);

      ref
          .read(purchaseDraftProvider.notifier)
          .loadFromOrder(
            supplier: supplier,
            lines: lines,
            taxRatePercent: detail.order.taxRate,
            notes: detail.order.notes,
            purchaseDate: detail.order.purchaseDateMs != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    detail.order.purchaseDateMs!,
                  )
                : DateTime.now(),
          );

      ref.invalidate(purchaseProductsBaseProvider);
      if (!context.mounted) return;
      context.go('/purchases/manual');
    }

    Future<void> openPdf(int orderId) async {
      final repo = PurchasesRepository();
      try {
        final detail = await repo.getOrderById(orderId);
        if (detail == null || !context.mounted) return;
        await PurchaseOrderPdfLauncher.openPreviewDialog(
          context: context,
          detail: detail,
        );
      } catch (e, st) {
        if (!context.mounted) return;
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => openPdf(orderId),
          module: 'purchases/v2/orders/pdf',
        );
      }
    }

    Future<void> receive(int orderId) async {
      final repo = PurchasesRepository();
      try {
        await repo.markAsReceived(orderId);
        ref.invalidate(purchaseOrdersListProvider);
        ref.invalidate(purchaseSelectedOrderDetailProvider);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Orden marcada como recibida'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e, st) {
        if (!context.mounted) return;
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => receive(orderId),
          module: 'purchases/v2/orders/receive',
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Órdenes de Compra',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        toolbarHeight: 48,
        actions: [
          TextButton(
            onPressed: () => context.go('/purchases'),
            child: const Text('Volver'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingL),
        child: Column(
          children: [
            header(),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 1100;

                  final list = PurchaseOrdersList(
                    onOpenPdf: (id) => openPdf(id),
                    onReceive: (id) => receive(id),
                    onEdit: (id) => context.go('/purchases/edit/$id'),
                  );

                  final detail = PurchaseOrderDetailPanel(
                    onOpenPdf: (detail) =>
                        PurchaseOrderPdfLauncher.openPreviewDialog(
                          context: context,
                          detail: detail,
                        ),
                    onReceive: (id) => receive(id),
                    onDuplicate: (detail) => duplicateToDraft(detail),
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        Expanded(child: list),
                        const SizedBox(height: 12),
                        SizedBox(height: 520, child: detail),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 6, child: list),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: detail),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
