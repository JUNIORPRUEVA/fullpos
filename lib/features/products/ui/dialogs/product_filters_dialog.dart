import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/products_repository.dart';
import '../../models/category_model.dart';
import '../../models/supplier_model.dart';

/// Diálogo de filtros avanzados para productos
class ProductFiltersDialog extends StatefulWidget {
  final ProductFilters? initialFilters;
  final List<CategoryModel> categories;
  final List<SupplierModel> suppliers;

  const ProductFiltersDialog({
    super.key,
    this.initialFilters,
    required this.categories,
    required this.suppliers,
  });

  @override
  State<ProductFiltersDialog> createState() => _ProductFiltersDialogState();
}

class _ProductFiltersDialogState extends State<ProductFiltersDialog> {
  int? _selectedCategoryId;
  int? _selectedSupplierId;
  bool? _hasLowStock;
  bool? _isOutOfStock;
  bool? _isActive;
  DateTime? _createdAfter;
  DateTime? _createdBefore;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilters != null) {
      _selectedCategoryId = widget.initialFilters!.categoryId;
      _selectedSupplierId = widget.initialFilters!.supplierId;
      _hasLowStock = widget.initialFilters!.hasLowStock;
      _isOutOfStock = widget.initialFilters!.isOutOfStock;
      _isActive = widget.initialFilters!.isActive;
      _createdAfter = widget.initialFilters!.createdAfter;
      _createdBefore = widget.initialFilters!.createdBefore;
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedCategoryId = null;
      _selectedSupplierId = null;
      _hasLowStock = null;
      _isOutOfStock = null;
      _isActive = null;
      _createdAfter = null;
      _createdBefore = null;
    });
  }

  void _applyFilters() {
    final filters = ProductFilters(
      categoryId: _selectedCategoryId,
      supplierId: _selectedSupplierId,
      hasLowStock: _hasLowStock,
      isOutOfStock: _isOutOfStock,
      isActive: _isActive,
      createdAfter: _createdAfter,
      createdBefore: _createdBefore,
    );
    Navigator.pop(context, filters);
  }

  @override
  Widget build(BuildContext context) {
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
              _applyFilters();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: const Text('Filtros de Productos'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Categoría
            DropdownButtonFormField<int>(
              initialValue: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                ...widget.categories.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name),
                    )),
              ],
              onChanged: (value) => setState(() => _selectedCategoryId = value),
            ),
            const SizedBox(height: 16),

            // Suplidor
            DropdownButtonFormField<int>(
              initialValue: _selectedSupplierId,
              decoration: const InputDecoration(
                labelText: 'Suplidor',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...widget.suppliers.map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name),
                    )),
              ],
              onChanged: (value) => setState(() => _selectedSupplierId = value),
            ),
            const SizedBox(height: 16),

            // Estado de stock
            const Text(
              'Estado de Stock',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            CheckboxListTile(
              title: const Text('Stock Bajo'),
              value: _hasLowStock ?? false,
              onChanged: (value) => setState(() => _hasLowStock = value),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('Agotados'),
              value: _isOutOfStock ?? false,
              onChanged: (value) => setState(() => _isOutOfStock = value),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 16),

            // Estado activo
            const Text(
              'Estado',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioListTile<bool?>(
              title: const Text('Todos'),
              value: null,
              groupValue: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            RadioListTile<bool?>(
              title: const Text('Solo Activos'),
              value: true,
              groupValue: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            RadioListTile<bool?>(
              title: const Text('Solo Inactivos'),
              value: false,
              groupValue: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: _clearFilters,
                child: const Text('Limpiar'),
              ),
              ElevatedButton(
                onPressed: _applyFilters,
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
