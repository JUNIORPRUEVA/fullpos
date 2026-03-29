import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/products_repository.dart';
import '../../models/category_model.dart';
import '../../models/supplier_model.dart';
import '../widgets/products_surface.dart';

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
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ProductsSurface(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ProductsSectionHeader(
                        eyebrow: 'FILTROS',
                        title: 'Refinar catálogo',
                        subtitle:
                            'Combina criterios de categoría, suplidor, stock y estado para limpiar la vista operativa del catálogo.',
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Clasificación',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas'),
                          ),
                          ...widget.categories.map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedCategoryId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedSupplierId,
                        decoration: const InputDecoration(
                          labelText: 'Suplidor',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...widget.suppliers.map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedSupplierId = value),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Stock',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                      CheckboxListTile(
                        title: const Text('Stock Bajo'),
                        value: _hasLowStock ?? false,
                        onChanged: (value) =>
                            setState(() => _hasLowStock = value),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text('Agotados'),
                        value: _isOutOfStock ?? false,
                        onChanged: (value) =>
                            setState(() => _isOutOfStock = value),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Estado',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                      RadioListTile<bool?>(
                        title: const Text('Todos'),
                        value: null,
                        groupValue: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<bool?>(
                        title: const Text('Solo Activos'),
                        value: true,
                        groupValue: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<bool?>(
                        title: const Text('Solo Inactivos'),
                        value: false,
                        groupValue: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Limpiar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _applyFilters,
                            child: const Text('Aplicar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
