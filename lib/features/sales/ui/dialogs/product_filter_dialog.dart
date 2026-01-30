import 'package:flutter/material.dart';

import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

enum ProductSortBy {
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
  stockAsc,
  stockDesc,
}

class ProductFilterModel {
  ProductSortBy sortBy;
  int? categoryId;
  bool onlyWithStock;
  double? minPrice;
  double? maxPrice;

  ProductFilterModel({
    this.sortBy = ProductSortBy.nameAsc,
    this.categoryId,
    this.onlyWithStock = false,
    this.minPrice,
    this.maxPrice,
  });

  ProductFilterModel copyWith({
    ProductSortBy? sortBy,
    int? categoryId,
    bool? clearCategory,
    bool? onlyWithStock,
    double? minPrice,
    double? maxPrice,
    bool? clearPrices,
  }) {
    return ProductFilterModel(
      sortBy: sortBy ?? this.sortBy,
      categoryId: clearCategory == true
          ? null
          : (categoryId ?? this.categoryId),
      onlyWithStock: onlyWithStock ?? this.onlyWithStock,
      minPrice: clearPrices == true ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPrices == true ? null : (maxPrice ?? this.maxPrice),
    );
  }

  bool get hasActiveFilters {
    return categoryId != null ||
        onlyWithStock ||
        minPrice != null ||
        maxPrice != null;
  }
}

class ProductFilterDialog extends StatefulWidget {
  final ProductFilterModel initialFilter;
  final List<dynamic> categories; // Lista de categorías {id, name}

  const ProductFilterDialog({
    super.key,
    required this.initialFilter,
    required this.categories,
  });

  @override
  State<ProductFilterDialog> createState() => _ProductFilterDialogState();
}

class _ProductFilterDialogState extends State<ProductFilterDialog> {
  late ProductFilterModel _filter;
  late TextEditingController _minPriceController;
  late TextEditingController _maxPriceController;

  @override
  void initState() {
    super.initState();
    _filter = ProductFilterModel(
      sortBy: widget.initialFilter.sortBy,
      categoryId: widget.initialFilter.categoryId,
      onlyWithStock: widget.initialFilter.onlyWithStock,
      minPrice: widget.initialFilter.minPrice,
      maxPrice: widget.initialFilter.maxPrice,
    );
    _minPriceController = TextEditingController(
      text: _filter.minPrice?.toStringAsFixed(2) ?? '',
    );
    _maxPriceController = TextEditingController(
      text: _filter.maxPrice?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DialogKeyboardShortcuts(
      onSubmit: _applyFilters,
      child: Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: scheme.onPrimary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Filtros y Ordenamiento',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: scheme.onPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ordenar por
                    _buildSectionTitle('Ordenar por'),
                    const SizedBox(height: 12),
                    _buildSortOption(
                      'Nombre (A-Z)',
                      ProductSortBy.nameAsc,
                      Icons.sort_by_alpha,
                    ),
                    _buildSortOption(
                      'Nombre (Z-A)',
                      ProductSortBy.nameDesc,
                      Icons.sort_by_alpha,
                    ),
                    _buildSortOption(
                      'Precio (Menor a Mayor)',
                      ProductSortBy.priceAsc,
                      Icons.attach_money,
                    ),
                    _buildSortOption(
                      'Precio (Mayor a Menor)',
                      ProductSortBy.priceDesc,
                      Icons.attach_money,
                    ),
                    _buildSortOption(
                      'Stock (Menor a Mayor)',
                      ProductSortBy.stockAsc,
                      Icons.inventory,
                    ),
                    _buildSortOption(
                      'Stock (Mayor a Menor)',
                      ProductSortBy.stockDesc,
                      Icons.inventory,
                    ),
                    const SizedBox(height: 24),

                    // Filtrar por Categoría
                    _buildSectionTitle('Categoría'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: _filter.categoryId,
                      decoration: InputDecoration(
                        hintText: 'Todas las categorías',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todas las categorías'),
                        ),
                        ...widget.categories.map((cat) {
                          return DropdownMenuItem<int?>(
                            value: cat['id'] as int,
                            child: Text(cat['name'] as String),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _filter = _filter.copyWith(
                            categoryId: value,
                            clearCategory: value == null,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Solo con Stock
                    CheckboxListTile(
                      title: const Text('Solo productos con stock disponible'),
                      value: _filter.onlyWithStock,
                      onChanged: (value) {
                        setState(() {
                          _filter = _filter.copyWith(
                            onlyWithStock: value ?? false,
                          );
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 24),

                    // Rango de Precio
                    _buildSectionTitle('Rango de Precio'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Mínimo',
                              prefixText: '\$',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _maxPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Máximo',
                              prefixText: '\$',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear_all, size: 20),
                    label: const Text('Limpiar'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _applyFilters,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Aplicar'),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildSortOption(String label, ProductSortBy value, IconData icon) {
    final isSelected = _filter.sortBy == value;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        setState(() {
          _filter = _filter.copyWith(sortBy: value);
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withOpacity(0.1)
              : scheme.surface.withOpacity(0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? scheme.primary
                  : scheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? scheme.primary
                      : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: scheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _filter = ProductFilterModel(
        sortBy: ProductSortBy.nameAsc,
        categoryId: null,
        onlyWithStock: false,
        minPrice: null,
        maxPrice: null,
      );
      _minPriceController.clear();
      _maxPriceController.clear();
    });
  }

  void _applyFilters() {
    // Parsear precios
    final minText = _minPriceController.text.trim();
    final maxText = _maxPriceController.text.trim();

    final minPrice = minText.isEmpty ? null : double.tryParse(minText);
    final maxPrice = maxText.isEmpty ? null : double.tryParse(maxText);

    // Validar que mínimo no sea mayor que máximo
    if (minPrice != null && maxPrice != null && minPrice > maxPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El precio mínimo no puede ser mayor que el máximo'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    _filter = _filter.copyWith(
      minPrice: minPrice,
      maxPrice: maxPrice,
      clearPrices: minPrice == null && maxPrice == null,
    );

    Navigator.of(context).pop(_filter);
  }
}
