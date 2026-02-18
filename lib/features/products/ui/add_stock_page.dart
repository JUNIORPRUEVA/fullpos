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

    return Scaffold(
      appBar: AppBar(
        title: Text('Agregar Stock - ${product.name}'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card con información del producto y stock actual
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Información del Producto',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Código:',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                                Text(
                                  product.code,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stock Actual:',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                                Text(
                                  product.stock.toString(),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: product.stock >= product.stockMin
                                            ? AppColors.success
                                            : Colors.orange,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stock Mínimo:',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                                Text(
                                  product.stockMin.toString(),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Formulario para agregar stock
              Text(
                'Agregar Stock',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _quantityController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad a Agregar',
                        hintText: '0.00',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.add),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
                      ],
                      onFieldSubmitted: (_) {
                        // Si presiona Enter en el campo cantidad, enfocar nota
                        FocusScope.of(context).nextFocus();
                      },
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
                        labelText: 'Nota (Opcional)',
                        hintText: 'Ej: Compra a proveedor X',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                      ),
                      onFieldSubmitted: (_) {
                        // Si presiona Enter/Tab en nota, guardar directamente
                        if (!_saving) {
                          _addStock();
                        }
                      },
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _addStock,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Agregar Stock'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Historial de movimientos
              Text(
                'Historial de Movimientos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_movements.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.history, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text(
                          'Sin movimientos registrados',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _movements.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final detail = _movements[index];
                    final movement = detail.movement;
                    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
                    final dateStr = dateFormat.format(
                      movement.createdAt.toLocal(),
                    );
                    final qtyFormat = NumberFormat.decimalPattern();
                    String qtyLabel;
                    if (movement.isAdjust) {
                      qtyLabel = movement.quantity >= 0
                          ? '+${qtyFormat.format(movement.quantity)}'
                          : qtyFormat.format(movement.quantity);
                    } else if (movement.isInput) {
                      qtyLabel = '+${qtyFormat.format(movement.quantity)}';
                    } else {
                      qtyLabel = '-${qtyFormat.format(movement.quantity)}';
                    }

                    final color = movement.isInput
                        ? AppColors.success
                        : movement.isOutput
                        ? Colors.red
                        : (movement.quantity >= 0
                              ? Colors.orange
                              : Colors.deepOrange);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          movement.isInput
                                              ? Icons.add_circle
                                              : movement.isOutput
                                              ? Icons.remove_circle
                                              : Icons.tune,
                                          color: color,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          movement.type.label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Cantidad: $qtyLabel',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    if (movement.note?.isNotEmpty ?? false) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Nota: ${movement.note}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontStyle: FontStyle.italic,
                                              color: Colors.grey[600],
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    dateStr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Por: ${detail.userLabel}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
