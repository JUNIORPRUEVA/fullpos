import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../data/products_repository.dart';
import '../data/stock_repository.dart';
import '../models/product_model.dart';
import '../models/stock_movement_model.dart';

/// Página para agregar stock a un producto
class AddStockPage extends StatefulWidget {
  final int productId;

  const AddStockPage({super.key, required this.productId});

  @override
  State<AddStockPage> createState() => _AddStockPageState();
}

class _AddStockPageState extends State<AddStockPage> {
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final ProductsRepository _productsRepo = ProductsRepository();
  final StockRepository _stockRepo = StockRepository();

  ProductModel? _product;
  List<StockMovementDetail> _movements = [];
  bool _loading = true;
  bool _saving = false;
  bool _error = false;
  String? _errorMessage;

  String _normalizeDecimalInput(String raw) {
    return raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  }

  double? _tryParseQuantity(String raw) {
    final normalized = _normalizeDecimalInput(raw);
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final product = await _productsRepo.getById(widget.productId);
      final movements = await _stockRepo.getDetailedHistory(
        productId: widget.productId,
        limit: 50,
      );

      if (!mounted) return;
      setState(() {
        _product = product;
        _movements = movements;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      final ex = await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _load,
        module: 'products/add_stock/load',
      );
      if (!mounted) return;
      setState(() {
        _error = true;
        _errorMessage = ex.messageUser;
        _loading = false;
      });
    }
  }

  Future<void> _addStock() async {
    if (!_formKey.currentState!.validate()) return;

    final canAdjust = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.adjustStock,
      resourceType: 'product',
      resourceId: widget.productId.toString(),
      isOnline: true,
    );
    if (!canAdjust || !mounted) return;

    final quantity = _tryParseQuantity(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cantidad inválida')));
      }
      return;
    }
    final note = _noteController.text.trim();
    final previousStock = _product?.stock ?? 0.0;

    setState(() => _saving = true);
    try {
      final currentUserId = await SessionManager.userId();

      await _stockRepo.recordInput(
        productId: widget.productId,
        quantity: quantity,
        note: note.isEmpty ? null : note,
        userId: currentUserId,
      );

      final updatedProduct = await _productsRepo.getById(widget.productId);
      final updatedStock = updatedProduct?.stock ?? (previousStock + quantity);

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      _quantityController.clear();
      _noteController.clear();
      Navigator.of(context).pop({
        'ok': true,
        'productId': widget.productId,
        'addedQty': quantity,
        'previousStock': previousStock,
        'updatedStock': updatedStock,
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Stock agregado correctamente'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _addStock,
        module: 'products/add_stock/save',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quantityFormat = NumberFormat.decimalPattern();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Agregar Stock')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error || _product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Agregar Stock')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $_errorMessage'),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final product = _product!;
    final stockHealthy = product.stock >= product.stockMin;

    return Scaffold(
      appBar: AppBar(
        title: Text('Agregar stock · ${product.name}'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Producto',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Código',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface.withOpacity(0.68),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  product.code,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: stockHealthy
                                  ? AppColors.success.withOpacity(0.08)
                                  : Colors.orange.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: stockHealthy
                                    ? AppColors.success.withOpacity(0.22)
                                    : Colors.orange.withOpacity(0.24),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stock actual',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface.withOpacity(0.68),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  quantityFormat.format(product.stock),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: stockHealthy
                                        ? AppColors.success
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mínimo',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface.withOpacity(0.68),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  quantityFormat.format(product.stockMin),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Entrada de stock',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _quantityController,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad a agregar',
                          hintText: '0.00',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.add),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9,\.]'),
                          ),
                        ],
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).nextFocus(),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingrese una cantidad';
                          }
                          final qty = _tryParseQuantity(value);
                          if (qty == null || qty <= 0) {
                            return 'La cantidad debe ser mayor que 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteController,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Nota',
                          hintText: 'Ej: compra a proveedor X',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                        onFieldSubmitted: (_) {
                          if (!_saving) _addStock();
                        },
                        maxLines: 3,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _addStock,
                          icon: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_box_outlined),
                          label: Text(
                            _saving ? 'Guardando...' : 'Agregar stock',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Historial',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_movements.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          'Sin movimientos',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurface.withOpacity(0.68),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _movements.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final detail = _movements[index];
                          final movement = detail.movement;
                          final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
                          final dateStr = dateFormat.format(
                            movement.createdAt.toLocal(),
                          );
                          String qtyLabel;
                          if (movement.isAdjust) {
                            qtyLabel = movement.quantity >= 0
                                ? '+${quantityFormat.format(movement.quantity)}'
                                : quantityFormat.format(movement.quantity);
                          } else if (movement.isInput) {
                            qtyLabel =
                                '+${quantityFormat.format(movement.quantity)}';
                          } else {
                            qtyLabel =
                                '-${quantityFormat.format(movement.quantity)}';
                          }

                          final color = movement.isInput
                              ? AppColors.success
                              : movement.isOutput
                              ? scheme.error
                              : (movement.quantity >= 0
                                    ? Colors.orange
                                    : Colors.deepOrange);

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    movement.isInput
                                        ? Icons.add_circle_outline
                                        : movement.isOutput
                                        ? Icons.remove_circle_outline
                                        : Icons.tune,
                                    color: color,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        movement.type.label,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$qtyLabel • $dateStr',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: scheme.onSurface
                                                  .withOpacity(0.68),
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if (movement.note?.isNotEmpty ??
                                          false) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          movement.note!,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: scheme.onSurface
                                                    .withOpacity(0.68),
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  detail.userLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface.withOpacity(0.68),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
