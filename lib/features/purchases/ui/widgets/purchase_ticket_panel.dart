import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../products/models/supplier_model.dart';
import '../../data/purchase_order_models.dart';
import '../../data/purchases_repository.dart';
import '../../providers/purchase_catalog_provider.dart';
import '../../providers/purchase_draft_provider.dart';
import '../../utils/purchase_order_pdf_launcher.dart';

class PurchaseTicketPanel extends ConsumerStatefulWidget {
  final VoidCallback? onOrderCreated;
  final bool isAuto;

  const PurchaseTicketPanel({
    super.key,
    this.onOrderCreated,
    this.isAuto = false,
  });

  @override
  ConsumerState<PurchaseTicketPanel> createState() =>
      _PurchaseTicketPanelState();
}

class _PurchaseTicketPanelState extends ConsumerState<PurchaseTicketPanel> {
  final ScrollController _itemsScroll = ScrollController();
  final Map<int, TextEditingController> _unitCostCtrls = {};

  bool _saving = false;

  @override
  void dispose() {
    _itemsScroll.dispose();
    for (final c in _unitCostCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<SupplierModel?> _pickSupplierDialog({
    required BuildContext context,
    required List<SupplierModel> suppliers,
    SupplierModel? selected,
  }) async {
    final searchCtrl = TextEditingController();

    try {
      return await showDialog<SupplierModel>(
        context: context,
        builder: (c) {
          SupplierModel? current = selected;

          return StatefulBuilder(
            builder: (context, setState) {
              final q = searchCtrl.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? suppliers
                  : suppliers
                        .where(
                          (s) =>
                              s.name.toLowerCase().contains(q) ||
                              (s.phone ?? '').toLowerCase().contains(q),
                        )
                        .toList(growable: false);

              return AlertDialog(
                title: const Text('Seleccionar proveedor'),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar por nombre o teléfono',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: Material(
                          color: Colors.transparent,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final s = filtered[index];
                              final isSelected = current?.id == s.id;
                              return ListTile(
                                title: Text(s.name),
                                subtitle: (s.phone ?? '').trim().isEmpty
                                    ? null
                                    : Text(s.phone!.trim()),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle)
                                    : null,
                                onTap: () {
                                  current = s;
                                  Navigator.of(c).pop(s);
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(c).pop(null),
                    child: const Text('Cancelar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      searchCtrl.dispose();
    }
  }

  PurchaseOrderDetailDto _buildDraftDetail({
    required PurchaseDraftState draft,
    required String supplierName,
    required String? supplierPhone,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final order = PurchaseOrderModel(
      id: null,
      supplierId: draft.supplier?.id ?? 0,
      status: 'PENDIENTE',
      subtotal: draft.subtotal,
      taxRate: draft.taxRatePercent,
      taxAmount: draft.taxAmount,
      total: draft.total,
      isAuto: 0,
      notes: draft.notes.trim().isEmpty ? null : draft.notes.trim(),
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      receivedAtMs: null,
      purchaseDateMs: draft.purchaseDate.millisecondsSinceEpoch,
    );

    final items = draft.lines
        .where((l) => l.product.id != null)
        .map(
          (l) => PurchaseOrderItemDetailDto(
            item: PurchaseOrderItemModel(
              id: null,
              orderId: 0,
              productId: l.product.id!,
              qty: l.qty,
              unitCost: l.unitCost,
              totalLine: l.subtotal,
              createdAtMs: nowMs,
            ),
            productCode: l.product.code,
            productName: l.product.name,
          ),
        )
        .toList(growable: false);

    return PurchaseOrderDetailDto(
      order: order,
      supplierName: supplierName,
      supplierPhone: supplierPhone,
      items: items,
    );
  }

  Future<void> _previewPdf(BuildContext context) async {
    final draft = ref.read(purchaseDraftProvider);
    final supplier = draft.supplier;
    if (supplier == null || supplier.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un proveedor para previsualizar'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    if (draft.lines.isEmpty || draft.total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agregue productos antes de previsualizar'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final detail = _buildDraftDetail(
      draft: draft,
      supplierName: supplier.name,
      supplierPhone: supplier.phone,
    );

    await PurchaseOrderPdfLauncher.openPreviewDialog(
      context: context,
      detail: detail,
    );
  }

  Future<void> _createOrder(BuildContext context) async {
    if (_saving) return;

    final draft = ref.read(purchaseDraftProvider);
    final supplier = draft.supplier;

    if (supplier == null || supplier.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un proveedor'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (draft.lines.isEmpty || draft.total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La orden debe tener al menos 1 producto'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = PurchasesRepository();
      final items = draft.lines
          .where((l) => l.product.id != null)
          .map(
            (l) => repo.itemInput(
              productId: l.product.id!,
              qty: l.qty,
              unitCost: l.unitCost,
            ),
          )
          .toList(growable: false);

      final orderId = await repo.createOrder(
        supplierId: supplier.id!,
        items: items,
        taxRatePercent: draft.taxRatePercent,
        notes: draft.notes.trim().isEmpty ? null : draft.notes.trim(),
        isAuto: widget.isAuto,
        purchaseDateMs: draft.purchaseDate.millisecondsSinceEpoch,
      );

      final detail = await repo.getOrderById(orderId);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Orden creada #$orderId'),
          backgroundColor: AppColors.success,
        ),
      );

      if (detail != null) {
        await PurchaseOrderPdfLauncher.openPreviewDialog(
          context: context,
          detail: detail,
        );
      }

      ref.read(purchaseDraftProvider.notifier).reset();
      widget.onOrderCreated?.call();
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _createOrder(context),
        module: 'purchases/v2/create',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _syncControllers(List<PurchaseDraftLine> lines) {
    final liveIds = <int>{
      for (final l in lines)
        if (l.product.id != null) l.product.id!,
    };

    final toRemove = _unitCostCtrls.keys.where((id) => !liveIds.contains(id));
    for (final id in toRemove.toList(growable: false)) {
      _unitCostCtrls.remove(id)?.dispose();
    }

    for (final l in lines) {
      final id = l.product.id;
      if (id == null) continue;
      final ctrl = _unitCostCtrls.putIfAbsent(
        id,
        () => TextEditingController(text: l.unitCost.toStringAsFixed(2)),
      );
      final desired = l.unitCost.toStringAsFixed(2);
      if (ctrl.text != desired && !ctrl.selection.isValid) {
        ctrl.text = desired;
      }
      if (ctrl.text != desired &&
          ctrl.selection.baseOffset == ctrl.selection.extentOffset) {
        // Si no está editando activamente, sincronizar.
        ctrl.value = TextEditingValue(
          text: desired,
          selection: TextSelection.collapsed(offset: desired.length),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat('#,##0.00', 'en_US');
    final dateFormat = DateFormat('dd/MM/yyyy');

    final draft = ref.watch(purchaseDraftProvider);
    final suppliersAsync = ref.watch(purchaseSuppliersProvider);

    _syncControllers(draft.lines);

    final panelDecoration = BoxDecoration(
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

    final supplierName = draft.supplier?.name ?? 'Sin proveedor';
    final supplierChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: draft.supplier == null
            ? AppColors.warningLight
            : scheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 16,
            color: scheme.onSurface.withOpacity(0.75),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              supplierName,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    Widget buildItemRow(PurchaseDraftLine line) {
      final product = line.product;
      final id = product.id;
      if (id == null) return const SizedBox.shrink();

      final unitCtrl = _unitCostCtrls[id]!;

      void applyCost() {
        final parsed = double.tryParse(unitCtrl.text.replaceAll(',', '.'));
        if (parsed == null) return;
        ref.read(purchaseDraftProvider.notifier).setUnitCost(id, parsed);
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.code,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.65),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _QtyStepper(
              qty: line.qty,
              onMinus: () =>
                  ref.read(purchaseDraftProvider.notifier).changeQtyBy(id, -1),
              onPlus: () =>
                  ref.read(purchaseDraftProvider.notifier).changeQtyBy(id, 1),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 88,
              child: TextField(
                controller: unitCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^[0-9]*[\.,]?[0-9]{0,4}'),
                  ),
                ],
                onSubmitted: (_) => applyCost(),
                onEditingComplete: applyCost,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Costo',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 92,
              child: Text(
                currency.format(line.subtotal),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: () =>
                  ref.read(purchaseDraftProvider.notifier).removeProduct(id),
              icon: const Icon(Icons.delete_outline),
              color: scheme.error,
            ),
          ],
        ),
      );
    }

    final itemsList = draft.lines.isEmpty
        ? _TicketEmpty(scheme: scheme)
        : ListView.separated(
            controller: _itemsScroll,
            itemCount: draft.lines.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: scheme.outlineVariant.withOpacity(0.45),
            ),
            itemBuilder: (context, index) => buildItemRow(draft.lines[index]),
          );

    final summary = Column(
      children: [
        _SummaryRow(label: 'Subtotal', value: currency.format(draft.subtotal)),
        _SummaryRow(
          label: 'Impuestos (${draft.taxRatePercent.toStringAsFixed(0)}%)',
          value: currency.format(draft.taxAmount),
        ),
        const Divider(height: 18),
        _SummaryRow(
          label: 'Total',
          value: currency.format(draft.total),
          isTotal: true,
        ),
      ],
    );

    final bottomBar = Container(
      padding: const EdgeInsets.all(AppSizes.paddingM),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withOpacity(0.45)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => _previewPdf(context),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Vista previa PDF'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _createOrder(context),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Generar Orden de Compra'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Shortcuts(
      shortcuts: const {
        // Ctrl+Enter: generar orden
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            _CreateOrderIntent(),
      },
      child: Actions(
        actions: {
          _CreateOrderIntent: CallbackAction<_CreateOrderIntent>(
            onInvoke: (_) {
              unawaited(_createOrder(context));
              return null;
            },
          ),
        },
        child: Container(
          decoration: panelDecoration,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ticket de compra',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          'Borrador',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurface.withOpacity(0.65),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: supplierChip),
                        const SizedBox(width: 8),
                        suppliersAsync.when(
                          data: (suppliers) {
                            return OutlinedButton(
                              onPressed: () async {
                                final picked = await _pickSupplierDialog(
                                  context: context,
                                  suppliers: suppliers,
                                  selected: draft.supplier,
                                );
                                if (picked == null) return;
                                ref
                                    .read(purchaseDraftProvider.notifier)
                                    .setSupplier(picked);
                                // Forzar recarga de productos base cuando cambia proveedor.
                                ref.invalidate(purchaseProductsBaseProvider);
                              },
                              child: Text(
                                draft.supplier == null ? 'Elegir' : 'Cambiar',
                              ),
                            );
                          },
                          loading: () => const SizedBox(
                            width: 86,
                            height: 36,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (e, _) => Tooltip(
                            message: '$e',
                            child: const Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.event,
                          size: 16,
                          color: scheme.onSurface.withOpacity(0.65),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateFormat.format(draft.purchaseDate),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface.withOpacity(0.75),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: scheme.outlineVariant.withOpacity(0.45),
              ),
              Expanded(child: itemsList),
              Padding(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                child: summary,
              ),
              bottomBar,
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketEmpty extends StatelessWidget {
  final ColorScheme scheme;

  const _TicketEmpty({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: scheme.primary),
            const SizedBox(height: 10),
            Text(
              'Agrega productos al ticket',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Haz clic en un producto del catálogo para añadirlo.',
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
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final style = isTotal
        ? theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: scheme.onSurface,
          )
        : theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface.withOpacity(0.82),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final double qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _QtyStepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove),
            iconSize: 18,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
          ),
          SizedBox(
            width: 46,
            child: Text(
              qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add),
            iconSize: 18,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _CreateOrderIntent extends Intent {
  const _CreateOrderIntent();
}
