import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fullpos/core/security/app_actions.dart';
import 'package:fullpos/core/security/authorization_guard.dart';
import 'package:fullpos/core/session/session_manager.dart';
import '../../data/stock_repository.dart';
import '../../models/product_model.dart';
import '../../models/stock_movement_model.dart';

/// Diálogo para ajustar stock de un producto
class StockAdjustDialog extends StatefulWidget {
  final ProductModel product;

  const StockAdjustDialog({super.key, required this.product});

  @override
  State<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<StockAdjustDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  final StockRepository _stockRepo = StockRepository();

  StockMovementType _selectedType = StockMovementType.input;
  bool _isLoading = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.adjustStock,
      resourceType: 'product',
      resourceId: widget.product.id?.toString(),
      reason: 'Ajustar stock',
    );
    if (!authorized || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final quantity = double.parse(_quantityController.text.trim());
      final note = _noteController.text.trim();
      final currentUserId = await SessionManager.userId();

      await _stockRepo.adjustStock(
        productId: widget.product.id!,
        type: _selectedType,
        quantity: quantity,
        note: note.isEmpty ? null : note,
        userId: currentUserId,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock ajustado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double? _calculateNewStock() {
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null) return null;

    switch (_selectedType) {
      case StockMovementType.input:
        return widget.product.stock + quantity;
      case StockMovementType.output:
        return widget.product.stock - quantity;
      case StockMovementType.adjust:
        return quantity;
    }
  }

  @override
  Widget build(BuildContext context) {
    final newStock = _calculateNewStock();

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.pop(context),
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_isLoading) return null;
              _save();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: const Text('Ajustar Stock'),
            content: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // Información del producto
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Código: ${widget.product.code}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Stock Actual: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.product.stock.toString(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: widget.product.isOutOfStock
                                ? Colors.red
                                : widget.product.hasLowStock
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tipo de movimiento
              const Text(
                'Tipo de Movimiento',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<StockMovementType>(
                segments: const [
                  ButtonSegment(
                    value: StockMovementType.input,
                    label: Text('Entrada'),
                    icon: Icon(Icons.add_circle),
                  ),
                  ButtonSegment(
                    value: StockMovementType.output,
                    label: Text('Salida'),
                    icon: Icon(Icons.remove_circle),
                  ),
                  ButtonSegment(
                    value: StockMovementType.adjust,
                    label: Text('Ajuste'),
                    icon: Icon(Icons.tune),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (Set<StockMovementType> newSelection) {
                  setState(() {
                    _selectedType = newSelection.first;
                    _quantityController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),

              // Cantidad
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: _selectedType == StockMovementType.adjust
                      ? 'Nuevo Stock *'
                      : 'Cantidad *',
                  hintText: _selectedType == StockMovementType.adjust
                      ? 'Ej: 100'
                      : 'Ej: 10',
                  border: const OutlineInputBorder(),
                  suffixText: _selectedType == StockMovementType.adjust
                      ? 'unidades'
                      : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'La cantidad es requerida';
                  }
                  final quantity = double.tryParse(value.trim());
                  if (quantity == null || quantity <= 0) {
                    return 'La cantidad debe ser mayor que 0';
                  }
                  if (_selectedType == StockMovementType.output &&
                      quantity > widget.product.stock) {
                    return 'Stock insuficiente (actual: ${widget.product.stock})';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Nota
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Ej: Compra a proveedor, Venta, Corrección',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Previsualización del nuevo stock
              if (newStock != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: newStock < widget.product.stockMin
                        ? Colors.red[50]
                        : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: newStock < widget.product.stockMin
                          ? Colors.red
                          : Colors.green,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        newStock < widget.product.stockMin
                            ? Icons.warning
                            : Icons.check_circle,
                        color: newStock < widget.product.stockMin
                            ? Colors.red
                            : Colors.green,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nuevo Stock',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              newStock.toString(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: newStock < widget.product.stockMin
                                    ? Colors.red
                                    : Colors.green,
                              ),
                            ),
                            if (newStock < widget.product.stockMin)
                              Text(
                                '¡Estará por debajo del mínimo! (${widget.product.stockMin})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
