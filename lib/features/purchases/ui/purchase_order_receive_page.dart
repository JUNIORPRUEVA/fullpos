import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../products/data/products_repository.dart';
import '../../products/models/product_model.dart';
import '../data/purchases_repository.dart';
import '../data/purchase_order_models.dart';
import '../utils/purchase_order_pdf_launcher.dart';

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

  Future<void> _receiveItem(PurchaseOrderItemDetailDto it) async {
    final detail = _detail;
    if (detail == null) return;

    final status = detail.order.status.trim().toUpperCase();
    if (status == 'RECIBIDA') return;

    final itemId = it.item.id ?? 0;
    if (itemId <= 0) return;

    if ((it.item.productId ?? 0) <= 0) {
      await _createProductAndReceive(it);
      return;
    }

    final ordered = it.item.qty;
    final received = it.item.receivedQty;
    final remaining = ordered - received;
    if (remaining <= 0) return;

    final qtyCtrl = TextEditingController(text: remaining.toStringAsFixed(2));
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Recibir producto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${it.productCode} • ${it.productName}'),
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
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Recibir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      qtyCtrl.dispose();
      return;
    }

    final parsed = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
    qtyCtrl.dispose();
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
        onRetry: () => _receiveItem(it),
        module: 'purchases/receive-item',
      );
    } finally {
      if (mounted) {
        setState(() => _receivingItems.remove(itemId));
      }
    }
  }

  Future<void> _createProductAndReceive(PurchaseOrderItemDetailDto it) async {
    final detail = _detail;
    if (detail == null) return;

    final itemId = it.item.id ?? 0;
    if (itemId <= 0) return;

    final ordered = it.item.qty;
    final received = it.item.receivedQty;
    final remaining = _normalizeQty(ordered - received);
    if (remaining <= 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultCode =
        (it.productCode.trim().isNotEmpty
                ? it.productCode.trim()
                : 'AUTO-${now % 1000000}')
            .toUpperCase();
    final defaultName = it.productName.trim().isNotEmpty
        ? it.productName.trim()
        : 'Producto';
    final defaultCost = (it.item.unitCost > 0 ? it.item.unitCost : 0.01)
        .toStringAsFixed(2);

    final codeCtrl = TextEditingController(text: defaultCode);
    final nameCtrl = TextEditingController(text: defaultName);
    final costCtrl = TextEditingController(text: defaultCost);
    final saleCtrl = TextEditingController(text: defaultCost);
    final qtyCtrl = TextEditingController(text: remaining.toStringAsFixed(2));

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Crear producto y recibir'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Item de compra: ${it.productName}'),
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
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Crear y recibir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      codeCtrl.dispose();
      nameCtrl.dispose();
      costCtrl.dispose();
      saleCtrl.dispose();
      qtyCtrl.dispose();
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

    codeCtrl.dispose();
    nameCtrl.dispose();
    costCtrl.dispose();
    saleCtrl.dispose();
    qtyCtrl.dispose();

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
        onRetry: () => _createProductAndReceive(it),
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

    final anyReceived = detail.items.any((e) => e.item.receivedQty > 0);
    if (!anyReceived) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Anular recepción'),
          content: const Text(
            'Esto revertirá el inventario (salida de stock) y dejará la orden como PENDIENTE. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat('#,##0.00', 'en_US');
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
                  (sum, e) => sum + (e.item.qty > 0 ? e.item.qty : 0.0),
                );
                final receivedTotal = detail.items.fold<double>(
                  0.0,
                  (sum, e) =>
                      sum + (e.item.receivedQty > 0 ? e.item.receivedQty : 0.0),
                );
                final status = detail.order.status.trim().toUpperCase();
                final anyReceived = detail.items.any(
                  (e) => e.item.receivedQty > 0,
                );

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    14,
                    pagePadding,
                    18,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: panelMaxWidth),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: scheme.outlineVariant.withOpacity(0.55),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.withOpacity(0.10),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSizes.paddingM),
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  AppSizes.paddingM,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withOpacity(
                                      0.35,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Orden #${detail.order.id ?? '-'}',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Suplidor: ${detail.supplierName}',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      'Fecha: ${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(detail.order.createdAtMs))}',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Estado: $status',
                                      style: TextStyle(
                                        color: status == 'RECIBIDA'
                                            ? AppColors.success
                                            : (status == 'PARCIAL'
                                                  ? AppColors.warning
                                                  : scheme.onSurfaceVariant),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Recibido: ${receivedTotal.toStringAsFixed(2)} / ${orderedTotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              PurchaseOrderPdfLauncher.openPreviewDialog(
                                                context: context,
                                                detail: detail,
                                              ),
                                          icon: const Icon(
                                            Icons.picture_as_pdf,
                                          ),
                                          label: const Text('WhatsApp / PDF'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _canceling || !anyReceived
                                              ? null
                                              : _cancelReceipt,
                                          icon: _canceling
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(Icons.undo),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.error,
                                          ),
                                          label: const Text('Anular recepción'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSizes.paddingM),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: scheme.outlineVariant.withOpacity(
                                        0.35,
                                      ),
                                    ),
                                  ),
                                  child: ListView.separated(
                                    itemCount: detail.items.length,
                                    separatorBuilder: (_, _) => Divider(
                                      height: 1,
                                      color: scheme.outlineVariant.withOpacity(
                                        0.35,
                                      ),
                                    ),
                                    itemBuilder: (context, index) {
                                      final it = detail.items[index];
                                      final ordered = it.item.qty;
                                      final received = it.item.receivedQty;
                                      final remaining = ordered - received;
                                      final itemId = it.item.id ?? 0;
                                      final isBusy =
                                          itemId > 0 &&
                                          _receivingItems.contains(itemId);
                                      final isCreating =
                                          itemId > 0 &&
                                          _creatingProductItems.contains(
                                            itemId,
                                          );
                                      final hasProduct =
                                          (it.item.productId ?? 0) > 0;
                                      final isDone =
                                          detail.order.status
                                                  .trim()
                                                  .toUpperCase() ==
                                              'RECIBIDA' ||
                                          remaining <= 0;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSizes.paddingM,
                                          vertical: 10,
                                        ),
                                        child: LayoutBuilder(
                                          builder: (context, itemConstraints) {
                                            final compact =
                                                itemConstraints.maxWidth < 720;

                                            Widget action() {
                                              if (isDone) {
                                                return const Icon(
                                                  Icons.check_circle,
                                                  color: AppColors.success,
                                                );
                                              }
                                              if (!hasProduct) {
                                                return OutlinedButton.icon(
                                                  onPressed: isCreating
                                                      ? null
                                                      : () =>
                                                            _createProductAndReceive(
                                                              it,
                                                            ),
                                                  icon: isCreating
                                                      ? const SizedBox(
                                                          width: 14,
                                                          height: 14,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        )
                                                      : const Icon(
                                                          Icons
                                                              .add_box_outlined,
                                                        ),
                                                  label: const Text('Recibir'),
                                                );
                                              }
                                              return OutlinedButton(
                                                onPressed: isBusy
                                                    ? null
                                                    : () => _receiveItem(it),
                                                child: isBusy
                                                    ? const SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : const Text('Recibir'),
                                              );
                                            }

                                            if (compact) {
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${it.productCode} • ${it.productName}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (!hasProduct) ...[
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.warning
                                                            .withOpacity(0.12),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                        border: Border.all(
                                                          color: AppColors
                                                              .warning
                                                              .withOpacity(0.4),
                                                        ),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .warning_amber_rounded,
                                                            size: 14,
                                                            color: AppColors
                                                                .warning,
                                                          ),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Requiere crear producto',
                                                            style: TextStyle(
                                                              color: AppColors
                                                                  .warning,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Ordenado: ${ordered.toStringAsFixed(2)} • Recibido: ${received.toStringAsFixed(2)} • Pendiente: ${remaining.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Costo: ${currency.format(it.item.unitCost)} • Total: ${currency.format(it.item.totalLine)}',
                                                    style: TextStyle(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: action(),
                                                  ),
                                                ],
                                              );
                                            }

                                            return Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        '${it.productCode} • ${it.productName}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      if (!hasProduct) ...[
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: AppColors
                                                                .warning
                                                                .withOpacity(
                                                                  0.12,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  999,
                                                                ),
                                                            border: Border.all(
                                                              color: AppColors
                                                                  .warning
                                                                  .withOpacity(
                                                                    0.4,
                                                                  ),
                                                            ),
                                                          ),
                                                          child: const Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .warning_amber_rounded,
                                                                size: 14,
                                                                color: AppColors
                                                                    .warning,
                                                              ),
                                                              SizedBox(
                                                                width: 4,
                                                              ),
                                                              Text(
                                                                'Requiere crear producto',
                                                                style: TextStyle(
                                                                  color: AppColors
                                                                      .warning,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 12,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Ordenado: ${ordered.toStringAsFixed(2)} • Recibido: ${received.toStringAsFixed(2)} • Pendiente: ${remaining.toStringAsFixed(2)}',
                                                        style: TextStyle(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        'Costo: ${currency.format(it.item.unitCost)}',
                                                        style: TextStyle(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      currency.format(
                                                        it.item.totalLine,
                                                      ),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    action(),
                                                  ],
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSizes.paddingM),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  AppSizes.paddingM,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withOpacity(
                                      0.35,
                                    ),
                                  ),
                                ),
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    Text(
                                      'Subtotal: ${currency.format(detail.order.subtotal)}',
                                    ),
                                    Text(
                                      'Impuesto: ${currency.format(detail.order.taxAmount)}',
                                    ),
                                    Text(
                                      'Total: ${currency.format(detail.order.total)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
