import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

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

  Future<void> _pickDate(bool isStart) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_createdAfter ?? DateTime.now())
          : (_createdBefore ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selected == null || !mounted) return;
    setState(() {
      if (isStart) {
        _createdAfter = selected;
      } else {
        _createdBefore = selected;
      }
    });
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
                                const Text(
                                  'Clasificación',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
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
                                const SizedBox(height: 12),
                                const Text(
                                  'Stock',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
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
                                          _isOutOfStock = selected
                                              ? true
                                              : null;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Estado',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Todos'),
                                      selected: _isActive == null,
                                      onSelected: (_) =>
                                          setState(() => _isActive = null),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Activos'),
                                      selected: _isActive == true,
                                      onSelected: (_) =>
                                          setState(() => _isActive = true),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Inactivos'),
                                      selected: _isActive == false,
                                      onSelected: (_) =>
                                          setState(() => _isActive = false),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Fechas',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _pickDate(true),
                                        icon: const Icon(Icons.event_outlined),
                                        label: Text(
                                          _createdAfter == null
                                              ? 'Desde'
                                              : _dateFormat.format(
                                                  _createdAfter!,
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _pickDate(false),
                                        icon: const Icon(Icons.event_outlined),
                                        label: Text(
                                          _createdBefore == null
                                              ? 'Hasta'
                                              : _dateFormat.format(
                                                  _createdBefore!,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
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
