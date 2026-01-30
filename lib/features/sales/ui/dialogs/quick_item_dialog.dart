import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/sale_item_model.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

/// Diálogo para agregar un item rápido (fuera de inventario)
class QuickItemDialog extends StatefulWidget {
  const QuickItemDialog({super.key});

  @override
  State<QuickItemDialog> createState() => _QuickItemDialogState();
}

class _QuickItemDialogState extends State<QuickItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _costController = TextEditingController(text: '0');

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _saveItem() {
    if (!_formKey.currentState!.validate()) return;

    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text) ?? 0;
    final qty = double.tryParse(_qtyController.text) ?? 1;
    final cost = double.tryParse(_costController.text) ?? 0;

    final item = SaleItemModel(
      saleId: 0, // Temporal
      productId: null, // NULL = item manual
      productCodeSnapshot: 'MANUAL',
      productNameSnapshot: description,
      unitPrice: price,
      purchasePriceSnapshot: cost,
      qty: qty,
      discountLine: 0,
      totalLine: qty * price,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DialogKeyboardShortcuts(
      onSubmit: _saveItem,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.add_shopping_cart,
                    color: scheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Venta Rápida',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Agregar un artículo fuera de inventario',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción *',
                  hintText: 'Ej: Servicio de instalación',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'La descripción es requerida';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Precio *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Requerido';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price <= 0) {
                          return 'Precio inválido';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _qtyController,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Requerido';
                        final qty = int.tryParse(value);
                        if (qty == null || qty <= 0) return 'Inválido';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(
                  labelText: 'Costo (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.money_off),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _saveItem,
                    icon: const Icon(Icons.check),
                    label: const Text('Agregar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
