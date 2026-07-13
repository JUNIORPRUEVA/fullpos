import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/products_repository.dart';
import '../../models/category_model.dart';
import '../../models/supplier_model.dart';

/// Panel lateral de filtros avanzados para productos.
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
    final filters = widget.initialFilters;
    if (filters != null) {
      _selectedCategoryId = filters.categoryId;
      _selectedSupplierId = filters.supplierId;
      _hasLowStock = filters.hasLowStock;
      _isOutOfStock = filters.isOutOfStock;
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
    Navigator.pop(
      context,
      ProductFilters(
        categoryId: _selectedCategoryId,
        supplierId: _selectedSupplierId,
        hasLowStock: _hasLowStock,
        isOutOfStock: _isOutOfStock,
      ),
    );
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedCategoryId != null) count++;
    if (_selectedSupplierId != null) count++;
    if (_hasLowStock == true) count++;
    if (_isOutOfStock == true) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final panelWidth = viewport.width < 620
        ? viewport.width
        : (viewport.width * 0.28).clamp(390.0, 460.0);

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
            child: Material(
              color: scheme.surface,
              elevation: 0,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  left: false,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(
                        left: BorderSide(
                          color: scheme.outlineVariant.withOpacity(0.85),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildHeader(theme, scheme),
                        Expanded(
                          child: CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  18,
                                  18,
                                  20,
                                ),
                                sliver: SliverList.list(
                                  children: [
                                    _buildHint(theme, scheme),
                                    const SizedBox(height: 18),
                                    _buildCategorySection(theme, scheme),
                                    const SizedBox(height: 18),
                                    _buildSupplierSection(theme, scheme),
                                    const SizedBox(height: 18),
                                    _buildStockSection(theme, scheme),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildActions(scheme),
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

  Widget _buildHeader(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withOpacity(0.85)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.tune_rounded, color: scheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtros de catálogo',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _activeFilterCount == 0
                      ? 'Sin filtros activos'
                      : '$_activeFilterCount filtros activos',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildHint(ThemeData theme, ColorScheme scheme) {
    return Text(
      'Refina el listado sin salir del catálogo.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    );
  }

  Widget _buildCategorySection(ThemeData theme, ColorScheme scheme) {
    return _FilterSection(
      title: 'Categoría',
      icon: Icons.category_rounded,
      child: Column(
        children: [
          _optionTile<int?>(
            theme: theme,
            scheme: scheme,
            label: 'Todas',
            value: null,
            selectedValue: _selectedCategoryId,
            onSelected: (value) => setState(() => _selectedCategoryId = value),
          ),
          ...widget.categories.map(
            (category) => _optionTile<int?>(
              theme: theme,
              scheme: scheme,
              label: category.name,
              value: category.id,
              selectedValue: _selectedCategoryId,
              onSelected: (value) =>
                  setState(() => _selectedCategoryId = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierSection(ThemeData theme, ColorScheme scheme) {
    return _FilterSection(
      title: 'Suplidor',
      icon: Icons.local_shipping_rounded,
      child: Column(
        children: [
          _optionTile<int?>(
            theme: theme,
            scheme: scheme,
            label: 'Todos',
            value: null,
            selectedValue: _selectedSupplierId,
            onSelected: (value) => setState(() => _selectedSupplierId = value),
          ),
          ...widget.suppliers.map(
            (supplier) => _optionTile<int?>(
              theme: theme,
              scheme: scheme,
              label: supplier.name,
              value: supplier.id,
              selectedValue: _selectedSupplierId,
              onSelected: (value) =>
                  setState(() => _selectedSupplierId = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockSection(ThemeData theme, ColorScheme scheme) {
    return _FilterSection(
      title: 'Stock',
      icon: Icons.inventory_2_rounded,
      child: Column(
        children: [
          _toggleTile(
            theme: theme,
            scheme: scheme,
            label: 'Stock bajo',
            icon: Icons.priority_high_rounded,
            selected: _hasLowStock == true,
            onTap: () {
              setState(() {
                _hasLowStock = _hasLowStock == true ? null : true;
              });
            },
          ),
          _toggleTile(
            theme: theme,
            scheme: scheme,
            label: 'Agotados',
            icon: Icons.remove_shopping_cart_rounded,
            selected: _isOutOfStock == true,
            onTap: () {
              setState(() {
                _isOutOfStock = _isOutOfStock == true ? null : true;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _optionTile<T>({
    required ThemeData theme,
    required ColorScheme scheme,
    required String label,
    required T value,
    required T selectedValue,
    required ValueChanged<T> onSelected,
  }) {
    final selected = value == selectedValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onSelected(value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withOpacity(0.09) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? scheme.primary.withOpacity(0.35)
                  : scheme.outlineVariant.withOpacity(0.72),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleTile({
    required ThemeData theme,
    required ColorScheme scheme,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withOpacity(0.09) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? scheme.primary.withOpacity(0.38)
                  : scheme.outlineVariant.withOpacity(0.75),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              Switch.adaptive(
                value: selected,
                onChanged: (_) => onTap(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withOpacity(0.85)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _clearFilters,
              child: const Text('Limpiar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _applyFilters,
              child: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _FilterSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
