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

  @override
  void initState() {
    super.initState();
    if (widget.initialFilters != null) {
      _selectedCategoryId = widget.initialFilters!.categoryId;
      _selectedSupplierId = widget.initialFilters!.supplierId;
      _hasLowStock = widget.initialFilters!.hasLowStock;
      _isOutOfStock = widget.initialFilters!.isOutOfStock;
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedCategoryId = null;
      _selectedSupplierId = null;
      _hasLowStock = null;
      _isOutOfStock = null;
    });
  }

  void _applyFilters() {
    final filters = ProductFilters(
      categoryId: _selectedCategoryId,
      supplierId: _selectedSupplierId,
      hasLowStock: _hasLowStock,
      isOutOfStock: _isOutOfStock,
    );
    Navigator.pop(context, filters);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width * 0.34).clamp(420.0, 540.0);

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
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(72, 12, 12, 12),
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: dialogWidth,
                  child: ProductsSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            border: Border(
                              bottom: BorderSide(color: scheme.outlineVariant),
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(22),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'FILTROS DE CATÁLOGO',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Refina el catálogo con los filtros clave del día a día.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<int?>(
                                  value: _selectedCategoryId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Categoría',
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('Todas'),
                                    ),
                                    ...widget.categories.map(
                                      (c) => DropdownMenuItem<int?>(
                                        value: c.id,
                                        child: Text(c.name),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) => setState(
                                    () => _selectedCategoryId = value,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<int?>(
                                  value: _selectedSupplierId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Suplidor',
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('Todos'),
                                    ),
                                    ...widget.suppliers.map(
                                      (s) => DropdownMenuItem<int?>(
                                        value: s.id,
                                        child: Text(s.name),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) => setState(
                                    () => _selectedSupplierId = value,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest.withOpacity(0.45),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: scheme.outlineVariant),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Stock',
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          FilterChip(
                                            label: const Text('Stock bajo'),
                                            selected: _hasLowStock == true,
                                            onSelected: (selected) {
                                              setState(() {
                                                _hasLowStock = selected ? true : null;
                                              });
                                            },
                                          ),
                                          FilterChip(
                                            label: const Text('Agotados'),
                                            selected: _isOutOfStock == true,
                                            onSelected: (selected) {
                                              setState(() {
                                                _isOutOfStock = selected ? true : null;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
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
                      ],
                    ),
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
