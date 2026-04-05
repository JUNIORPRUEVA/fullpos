import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/utils/currency_display.dart';
import '../../products/data/products_repository.dart';
import '../../products/models/product_model.dart';
import '../data/purchase_order_models.dart';
import '../data/purchases_repository.dart';
import '../utils/purchase_order_pdf_launcher.dart';
import 'widgets/purchase_ui.dart';

class PurchaseOrderReceivePage extends StatefulWidget {
  final int orderId;

  const PurchaseOrderReceivePage({super.key, required this.orderId});

  @override
  State<PurchaseOrderReceivePage> createState() =>
      _PurchaseOrderReceivePageState();
}

class _PurchaseOrderReceivePageState extends State<PurchaseOrderReceivePage> {
  final PurchasesRepository _repo = PurchasesRepository();
  final ProductsRepository _productsRepo = ProductsRepository();

  bool _loading = true;
  final Set<int> _receivingItems = <int>{};
  final Set<int> _creatingProductItems = <int>{};
  bool _canceling = false;
  String? _error;
  PurchaseOrderDetailDto? _detail;

  static double _normalizeQty(double value) =>
      double.parse(value.toStringAsFixed(6));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _repo.getOrderById(widget.orderId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _receiveItem(PurchaseOrderItemDetailDto item) async {
    final detail = _detail;
    if (detail == null) return;

    final status = detail.order.status.trim().toUpperCase();
    if (status == 'RECIBIDA') return;

    final itemId = item.item.id ?? 0;
    if (itemId <= 0) return;

    if ((item.item.productId ?? 0) <= 0) {
      await _createProductAndReceive(item);
      return;
    }

    final ordered = item.item.qty;
    final received = item.item.receivedQty;
    final remaining = ordered - received;
    if (remaining <= 0) return;

    final qtyCtrl = TextEditingController(text: remaining.toStringAsFixed(2));
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Recibir producto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item.productCode} • ${item.productName}'),
              const SizedBox(height: 8),
              Text('Ordenado: ${ordered.toStringAsFixed(2)}'),
              Text('Recibido: ${received.toStringAsFixed(2)}'),
              Text('Pendiente: ${remaining.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cantidad a recibir',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              const Text('Nota: esto actualiza el inventario de inmediato.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Recibir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
        qtyCtrl.dispose();
      });
      return;
    }

    final parsed = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
    Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
      qtyCtrl.dispose();
    });

    if (parsed == null || parsed <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cantidad inválida'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final normalizedParsed = _normalizeQty(parsed);
    final normalizedRemaining = _normalizeQty(remaining);
    const tolerance = 0.0005;
    if (normalizedParsed - normalizedRemaining > tolerance) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cantidad mayor a lo pendiente (${normalizedRemaining.toStringAsFixed(2)}).',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _receivingItems.add(itemId));
    try {
      await _repo.receiveItem(
        orderId: widget.orderId,
        itemId: itemId,
        qtyToReceive: normalizedParsed,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto recibido e inventario actualizado'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _receiveItem(item),
        module: 'purchases/receive-item',
      );
    } finally {
      if (mounted) {
        setState(() => _receivingItems.remove(itemId));
      }
    }
  }

  Future<void> _createProductAndReceive(PurchaseOrderItemDetailDto item) async {
    final detail = _detail;
    if (detail == null) return;

    final itemId = item.item.id ?? 0;
    if (itemId <= 0) return;

    final ordered = item.item.qty;
    final received = item.item.receivedQty;
    final remaining = _normalizeQty(ordered - received);
    if (remaining <= 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultCode =
        (item.productCode.trim().isNotEmpty
                ? item.productCode.trim()
                : 'AUTO-${now % 1000000}')
            .toUpperCase();
    final defaultName = item.productName.trim().isNotEmpty
        ? item.productName.trim()
        : 'Producto';
    final defaultCost = (item.item.unitCost > 0 ? item.item.unitCost : 0.01)
        .toStringAsFixed(2);

    final codeCtrl = TextEditingController(text: defaultCode);
    final nameCtrl = TextEditingController(text: defaultName);
    final costCtrl = TextEditingController(text: defaultCost);
    final saleCtrl = TextEditingController(text: defaultCost);
    final qtyCtrl = TextEditingController(text: remaining.toStringAsFixed(2));

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Crear producto y recibir'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Item de compra: ${item.productName}'),
                const SizedBox(height: 10),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: costCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Costo compra',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: saleCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio venta',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Cantidad a recibir (pendiente ${remaining.toStringAsFixed(2)})',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Crear y recibir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
        codeCtrl.dispose();
        nameCtrl.dispose();
        costCtrl.dispose();
        saleCtrl.dispose();
        qtyCtrl.dispose();
      });
      return;
    }

    final code = codeCtrl.text.trim().toUpperCase();
    final name = nameCtrl.text.trim();
    final purchasePrice = double.tryParse(
      costCtrl.text.trim().replaceAll(',', '.'),
    );
    final salePrice = double.tryParse(
      saleCtrl.text.trim().replaceAll(',', '.'),
    );
    final qtyToReceive = double.tryParse(
      qtyCtrl.text.trim().replaceAll(',', '.'),
    );

    Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
      codeCtrl.dispose();
      nameCtrl.dispose();
      costCtrl.dispose();
      saleCtrl.dispose();
      qtyCtrl.dispose();
    });

    if (code.isEmpty || name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Código y nombre son obligatorios.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (purchasePrice == null || purchasePrice <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Costo de compra inválido.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (salePrice == null || salePrice <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio de venta inválido.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (qtyToReceive == null || qtyToReceive <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cantidad a recibir inválida.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final normalizedQty = _normalizeQty(qtyToReceive);
    const tolerance = 0.0005;
    if (normalizedQty - remaining > tolerance) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cantidad mayor a lo pendiente (${remaining.toStringAsFixed(2)}).',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _creatingProductItems.add(itemId);
      _receivingItems.add(itemId);
    });

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final productId = await _productsRepo.create(
        ProductModel(
          code: code,
          name: name,
          placeholderType: 'color',
          purchasePrice: purchasePrice,
          salePrice: salePrice,
          stock: 0,
          stockMin: 0,
          supplierId: detail.order.supplierId,
          isActive: true,
          createdAtMs: ts,
          updatedAtMs: ts,
        ),
      );

      await _repo.attachProductToOrderItem(
        orderId: widget.orderId,
        itemId: itemId,
        productId: productId,
        productCodeSnapshot: code,
        productNameSnapshot: name,
      );

      await _repo.receiveItem(
        orderId: widget.orderId,
        itemId: itemId,
        qtyToReceive: normalizedQty,
      );

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto creado y recibido correctamente.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _createProductAndReceive(item),
        module: 'purchases/create-product-and-receive',
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingProductItems.remove(itemId);
          _receivingItems.remove(itemId);
        });
      }
    }
  }

  Future<void> _cancelReceipt() async {
    final detail = _detail;
    if (detail == null) return;

    final anyReceived = detail.items.any((item) => item.item.receivedQty > 0);
    if (!anyReceived) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Anular recepción'),
          content: const Text(
            'Esto revertirá el inventario (salida de stock) y dejará la orden como PENDIENTE. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Anular'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _canceling = true);
    try {
      await _repo.cancelReceipt(widget.orderId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recepción anulada y stock revertido'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _cancelReceipt,
        module: 'purchases/cancel-receipt',
      );
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
  }

  Color _statusColor(String status) {
    switch (status.trim().toUpperCase()) {
      case 'RECIBIDA':
        return AppColors.success;
      case 'PARCIAL':
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  Widget _buildSummaryCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    PurchaseOrderDetailDto detail,
    NumberFormat currency,
    DateFormat dateFormat,
    String status,
    double orderedTotal,
    double receivedTotal,
    bool anyReceived,
  ) {
    final orderDateMs = detail.order.purchaseDateMs ?? detail.order.createdAtMs;
    final supplierPhone = detail.supplierPhone?.trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.paddingM),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orden #${detail.order.id ?? '-'}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              PurchaseFactTile(label: 'Suplidor', value: detail.supplierName),
              PurchaseFactTile(
                label: 'Fecha',
                value: dateFormat.format(
                  DateTime.fromMillisecondsSinceEpoch(orderDateMs),
                ),
              ),
              PurchaseFactTile(
                label: 'Monto orden',
                value: currency.format(detail.order.total),
              ),
              if (supplierPhone.isNotEmpty)
                PurchaseFactTile(label: 'Teléfono', value: supplierPhone),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PurchaseStatusBadge(label: status, color: _statusColor(status)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recibido ${receivedTotal.toStringAsFixed(2)} de ${orderedTotal.toStringAsFixed(2)} unidades',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => PurchaseOrderPdfLauncher.openPreviewDialog(
                  context: context,
                  detail: detail,
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('WhatsApp / PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _canceling || !anyReceived ? null : _cancelReceipt,
                icon: _canceling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.undo_rounded),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                ),
                label: const Text('Anular recepción'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    PurchaseOrderItemDetailDto item,
    bool isDone,
    bool hasProduct,
    bool isReceiving,
    bool isCreating,
  ) {
    if (isDone) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 18),
          SizedBox(width: 6),
          Text(
            'Completo',
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    if (!hasProduct) {
      return OutlinedButton.icon(
        onPressed: isCreating ? null : () => _createProductAndReceive(item),
        icon: isCreating
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_box_outlined),
        label: const Text('Crear y recibir'),
      );
    }

    return OutlinedButton.icon(
      onPressed: isReceiving ? null : () => _receiveItem(item),
      icon: isReceiving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.inventory_2_outlined),
      label: const Text('Recibir'),
    );
  }

  Widget _buildWarningChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
          SizedBox(width: 4),
          Text(
            'Requiere crear producto',
            style: TextStyle(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    ColorScheme scheme,
    String orderStatus,
    PurchaseOrderItemDetailDto item,
    NumberFormat currency,
  ) {
    final itemId = item.item.id ?? 0;
    final ordered = item.item.qty;
    final received = item.item.receivedQty;
    final remaining = ordered - received;
    final hasProduct = (item.item.productId ?? 0) > 0;
    final isReceiving = itemId > 0 && _receivingItems.contains(itemId);
    final isCreating = itemId > 0 && _creatingProductItems.contains(itemId);
    final isDone = orderStatus == 'RECIBIDA' || remaining <= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingM,
        vertical: 10,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final action = _buildActionButton(
            item,
            isDone,
            hasProduct,
            isReceiving,
            isCreating,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.productCode} • ${item.productName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (!hasProduct) ...[
                  const SizedBox(height: 6),
                  _buildWarningChip(),
                ],
                const SizedBox(height: 6),
                Text(
                  'Ordenado: ${ordered.toStringAsFixed(2)} • Recibido: ${received.toStringAsFixed(2)} • Pendiente: ${remaining.toStringAsFixed(2)}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  'Costo: ${currency.format(item.item.unitCost)} • Total: ${currency.format(item.item.totalLine)}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.productCode} • ${item.productName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!hasProduct) _buildWarningChip(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Ordenado: ${ordered.toStringAsFixed(2)}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          'Recibido: ${received.toStringAsFixed(2)}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          'Pendiente: ${remaining.toStringAsFixed(2)}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          'Costo: ${currency.format(item.item.unitCost)}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          'Total: ${currency.format(item.item.totalLine)}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Align(alignment: Alignment.topRight, child: action),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = CurrencyDisplay.currency();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final detail = _detail;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text(
          'Recibir Orden',
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            )
          : detail == null
          ? Center(
              child: Text(
                'Orden no encontrada',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final pagePadding = (width * 0.03).clamp(12.0, 40.0);
                final panelMaxWidth = width > 1500
                    ? 1250.0
                    : (width > 1200 ? 1100.0 : 940.0);
                final orderedTotal = detail.items.fold<double>(
                  0.0,
                  (sum, item) =>
                      sum + (item.item.qty > 0 ? item.item.qty : 0.0),
                );
                final receivedTotal = detail.items.fold<double>(
                  0.0,
                  (sum, item) =>
                      sum +
                      (item.item.receivedQty > 0 ? item.item.receivedQty : 0.0),
                );
                final status = detail.order.status.trim().toUpperCase();
                final anyReceived = detail.items.any(
                  (item) => item.item.receivedQty > 0,
                );

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    12,
                    pagePadding,
                    24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: panelMaxWidth),
                      child: Column(
                        children: [
                          PurchaseHeroCard(
                            eyebrow: 'Recepción',
                            title:
                                'Confirma entrada de mercadería y corrige inventario en tiempo real.',
                            subtitle:
                                'La vista ahora prioriza densidad operativa, lectura rápida y acciones claras por línea sin tocar el flujo funcional.',
                            stats: [
                              PurchaseMetricTile(
                                label: 'Proveedor',
                                value: detail.supplierName,
                                icon: Icons.local_shipping_rounded,
                              ),
                              PurchaseMetricTile(
                                label: 'Estado',
                                value: status,
                                icon: Icons.inventory_2_rounded,
                              ),
                            ],
                            actions: [
                              if (anyReceived)
                                TextButton.icon(
                                  onPressed: _canceling ? null : _cancelReceipt,
                                  icon: _canceling
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.undo_rounded,
                                          color: Colors.white,
                                        ),
                                  label: const Text(
                                    'Anular recepción',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: PurchaseSectionCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(
                                      AppSizes.paddingM,
                                    ),
                                    child: _buildSummaryCard(
                                      context,
                                      theme,
                                      scheme,
                                      detail,
                                      currency,
                                      dateFormat,
                                      status,
                                      orderedTotal,
                                      receivedTotal,
                                      anyReceived,
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: scheme.outlineVariant.withOpacity(
                                      0.35,
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: detail.items.length,
                                      separatorBuilder: (_, _) => Divider(
                                        height: 1,
                                        color: scheme.outlineVariant
                                            .withOpacity(0.35),
                                      ),
                                      itemBuilder: (context, index) {
                                        return _buildItemRow(
                                          context,
                                          scheme,
                                          status,
                                          detail.items[index],
                                          currency,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
