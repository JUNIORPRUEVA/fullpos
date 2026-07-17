import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/session/session_manager.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/security/temporary_authorization_service.dart';
import '../data/categories_repository.dart';
import '../data/products_repository.dart';
import '../data/stock_repository.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';
import '../models/stock_movement_model.dart';
import 'tabs/catalog_tab.dart';
import 'widgets/product_thumbnail.dart';
import 'widgets/products_surface.dart';

class ProductsServicesPage extends StatelessWidget {
  const ProductsServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CatalogTab();
  }
}

enum _InventoryAdjustmentMode { increase, decrease, exact }

enum _InventoryStockFilter { all, available, low, out, high, priority }

enum _StockWorkspaceView { products, movements }

class StockAdjustmentWorkspacePage extends StatefulWidget {
  const StockAdjustmentWorkspacePage({super.key});

  @override
  State<StockAdjustmentWorkspacePage> createState() =>
      _StockAdjustmentWorkspacePageState();
}

class _StockAdjustmentWorkspacePageState
    extends State<StockAdjustmentWorkspacePage> {
  final ProductsRepository _productsRepository = ProductsRepository();
  final CategoriesRepository _categoriesRepository = CategoriesRepository();
  final StockRepository _stockRepository = StockRepository();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final FocusNode _quantityFocusNode = FocusNode();
  final ScrollController _productsScrollController = ScrollController();
  final NumberFormat _numberFormat = NumberFormat.decimalPattern('en_US');
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  List<StockMovementDetail> _recentAdjustments = [];
  ProductModel? _selectedProduct;
  int? _selectedCategoryId;
  _InventoryStockFilter _stockFilter = _InventoryStockFilter.all;
  _StockWorkspaceView _workspaceView = _StockWorkspaceView.products;
  _InventoryAdjustmentMode _mode = _InventoryAdjustmentMode.increase;
  bool _showAllProducts = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshSearch);
    _loadData();
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Limpiar autorización temporal específica de esta pantalla al salir.
    TemporaryAuthorizationService.clearAuthorization(
      'screen.products.stock_adjustment',
    );
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    _quantityController.dispose();
    _notesController.dispose();
    _quantityFocusNode.dispose();
    _productsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _productsRepository.getAll(),
        _categoriesRepository.getAll(),
        _stockRepository.getDetailedHistory(limit: 12),
      ]);
      if (!mounted) return;
      setState(() {
        _products = (results[0] as List<ProductModel>)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _categories = results[1] as List<CategoryModel>;
        _recentAdjustments = results[2] as List<StockMovementDetail>;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el módulo de ajustes: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ProductModel> _visibleProducts() {
    if (!_hasActiveProductFilter) return const [];
    final query = _searchController.text.trim().toLowerCase();
    return _products.where((product) {
      final matchesQuery =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);
      final matchesCategory =
          _selectedCategoryId == null ||
          product.categoryId == _selectedCategoryId;
      final matchesStock = switch (_stockFilter) {
        _InventoryStockFilter.all => true,
        _InventoryStockFilter.available => product.stock > product.stockMin,
        _InventoryStockFilter.low => product.hasLowStock,
        _InventoryStockFilter.out => product.isOutOfStock,
        _InventoryStockFilter.high => product.stock > product.stockMin * 2,
        _InventoryStockFilter.priority =>
          product.isOutOfStock || product.hasLowStock,
      };
      return matchesQuery && matchesCategory && matchesStock;
    }).toList();
  }

  bool get _hasActiveProductFilter =>
      _showAllProducts ||
      _searchController.text.trim().isNotEmpty ||
      _selectedCategoryId != null ||
      _stockFilter != _InventoryStockFilter.all;

  void _selectProduct(ProductModel product, {bool fillSearch = true}) {
    setState(() {
      _selectedProduct = product;
      if (fillSearch) _searchController.text = product.code;
    });
    _quantityFocusNode.requestFocus();
  }

  void _submitProductSearch(String rawValue) {
    final query = rawValue.trim().toLowerCase();
    if (query.isEmpty) return;
    final exact = _products.where(
      (product) =>
          product.code.toLowerCase() == query ||
          product.name.toLowerCase() == query,
    );
    if (exact.isNotEmpty) {
      _selectProduct(exact.first);
      return;
    }
    final partial = _visibleProducts();
    if (partial.length == 1) {
      _selectProduct(partial.first);
      return;
    }
    if (partial.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró un producto con ese código o nombre.'),
        ),
      );
    } else {
      setState(() => _workspaceView = _StockWorkspaceView.products);
    }
  }

  String _categoryName(ProductModel product) {
    if (product.categoryId == null) return 'Sin categoría';
    for (final category in _categories) {
      if (category.id == product.categoryId) return category.name;
    }
    return 'Sin categoría';
  }

  (String, Color) _stockStatus(ProductModel product, ColorScheme scheme) {
    if (product.isOutOfStock) return ('Agotado', scheme.error);
    if (product.hasLowStock) return ('Stock bajo', Colors.orange.shade700);
    if (product.stock <= product.stockMin * 2) {
      return ('Stock medio', Colors.amber.shade800);
    }
    return ('Disponible', Colors.green.shade700);
  }

  double? _parsedQuantity() {
    return double.tryParse(
      _quantityController.text.trim().replaceAll(',', '.'),
    );
  }

  double? _previewNewStock() {
    final product = _selectedProduct;
    final quantity = _parsedQuantity();
    if (product == null || quantity == null) return null;
    switch (_mode) {
      case _InventoryAdjustmentMode.increase:
        return product.stock + quantity;
      case _InventoryAdjustmentMode.decrease:
        return product.stock - quantity;
      case _InventoryAdjustmentMode.exact:
        return quantity;
    }
  }

  AppAction _actionForMode(_InventoryAdjustmentMode mode) {
    switch (mode) {
      case _InventoryAdjustmentMode.increase:
        return AppActions.addStock;
      case _InventoryAdjustmentMode.decrease:
        return AppActions.removeStock;
      case _InventoryAdjustmentMode.exact:
        return AppActions.adjustInventory;
    }
  }

  Future<void> _saveAdjustment() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) return;
    final product = _selectedProduct!;
    final quantity = _parsedQuantity()!;
    if (_mode == _InventoryAdjustmentMode.decrease &&
        quantity > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La cantidad a descontar no puede superar el stock actual.',
          ),
        ),
      );
      return;
    }

    final movementType = switch (_mode) {
      _InventoryAdjustmentMode.increase => StockMovementType.input,
      _InventoryAdjustmentMode.decrease => StockMovementType.output,
      _InventoryAdjustmentMode.exact => StockMovementType.adjust,
    };
    final expectedStock = switch (_mode) {
      _InventoryAdjustmentMode.increase => product.stock + quantity,
      _InventoryAdjustmentMode.decrease => product.stock - quantity,
      _InventoryAdjustmentMode.exact => quantity,
    };

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: _actionForMode(_mode),
      resourceType: 'product',
      resourceId: product.id?.toString(),
      reason: 'Ajustar stock',
    );
    if (!authorized || !mounted) return;

    setState(() => _saving = true);
    try {
      final movementId = await _stockRepository.adjustStock(
        productId: product.id!,
        type: movementType,
        quantity: quantity,
        note: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        userId: await SessionManager.userId(),
      );
      final persistedProduct = await _productsRepository.getById(product.id!);
      if (persistedProduct == null ||
          (persistedProduct.stock - expectedStock).abs() > 0.0001) {
        throw StateError(
          'No se pudo verificar el nuevo stock en la base de datos.',
        );
      }
      final movement = await _stockRepository.getByProductId(
        product.id!,
        limit: 1,
      );
      if (movementId <= 0 ||
          movement.isEmpty ||
          movement.first.id != movementId) {
        throw StateError(
          'El stock cambió, pero no se pudo confirmar su movimiento de auditoría.',
        );
      }
      _quantityController.clear();
      _notesController.clear();
      await _loadData();
      if (mounted) {
        setState(() {
          _selectedProduct = persistedProduct;
          _searchController.text = persistedProduct.code;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock ajustado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el ajuste: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedProduct = _selectedProduct;
    final previewStock = _previewNewStock();
    final visibleProducts = _visibleProducts();

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: productsResponsivePagePadding(
              constraints,
              top: 10,
              bottom: 14,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    children: [
                      ProductsSurface(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        radius: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildWorkspaceHeader(
                              theme,
                              scheme,
                              _products.length,
                            ),
                            const SizedBox(height: 10),
                            if (_products.isEmpty && !_loading)
                              ProductsEmptyState(
                                icon: Icons.inventory_2_outlined,
                                title: 'No hay productos disponibles',
                                message:
                                    'Crea un producto activo antes de registrar movimientos de stock.',
                                action: OutlinedButton.icon(
                                  onPressed: _loadData,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Actualizar'),
                                ),
                              )
                            else
                              _buildSearchAndFilters(theme, scheme),
                            const SizedBox(height: 10),
                            Form(
                              key: _formKey,
                              child: _buildAdjustmentStrip(
                                theme,
                                scheme,
                                selectedProduct,
                                previewStock,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _workspaceView == _StockWorkspaceView.products
                            ? _buildProductsSection(
                                theme,
                                scheme,
                                visibleProducts,
                              )
                            : _buildMovementsSection(theme, scheme),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceHeader(
    ThemeData theme,
    ColorScheme scheme,
    int productCount,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFD9E3F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$productCount productos',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _workspaceView =
                      _workspaceView == _StockWorkspaceView.products
                      ? _StockWorkspaceView.movements
                      : _StockWorkspaceView.products;
                }),
                icon: Icon(
                  _workspaceView == _StockWorkspaceView.products
                      ? Icons.history_rounded
                      : Icons.inventory_2_outlined,
                  size: 17,
                ),
                label: Text(
                  _workspaceView == _StockWorkspaceView.products
                      ? 'Ver movimientos'
                      : 'Ver productos',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFD9E3F0)),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        );

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'INVENTARIO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF1A56DB),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ajuste de stock',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
                letterSpacing: 0,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Ajusta inventario con trazabilidad.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
                fontFamily: 'Inter',
                height: 1.2,
              ),
            ),
          ],
        );

        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 10), actions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildSearchAndFilters(ThemeData theme, ColorScheme scheme) {
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: const BorderSide(color: Color(0xFFD9E3F0)),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD9E3F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final search = SizedBox(
            height: 42,
            width: compact ? constraints.maxWidth : 390,
            child: TextField(
              controller: _searchController,
              onSubmitted: _submitProductSearch,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar por código o nombre...',
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                isDense: true,
                filled: true,
                fillColor: scheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder.copyWith(
                  borderSide: BorderSide(color: scheme.primary, width: 1.2),
                ),
              ),
            ),
          );

          final category = SizedBox(
            height: 42,
            width: compact ? constraints.maxWidth : 230,
            child: DropdownButtonFormField<int?>(
              value: _selectedCategoryId,
              isExpanded: true,
              elevation: 0,
              menuMaxHeight: 220,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(5),
              itemHeight: 48,
              selectedItemBuilder: (context) => [
                const Text('Todas', overflow: TextOverflow.ellipsis),
                ..._categories
                    .where((item) => item.id != null)
                    .map(
                      (category) =>
                          Text(category.name, overflow: TextOverflow.ellipsis),
                    ),
              ],
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
              decoration: InputDecoration(
                labelText: 'Categoría',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                isDense: true,
                filled: true,
                fillColor: scheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder.copyWith(
                  borderSide: BorderSide(color: scheme.primary, width: 1.2),
                ),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
                ..._categories
                    .where((item) => item.id != null)
                    .map(
                      (category) => DropdownMenuItem<int?>(
                        value: category.id,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            category.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.15),
                          ),
                        ),
                      ),
                    ),
              ],
              onChanged: (value) => setState(() {
                _selectedCategoryId = value;
                _showAllProducts = value == null;
              }),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [search, category],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _InventoryStockFilter.values.map((filter) {
                  final labels = {
                    _InventoryStockFilter.all: 'Todos',
                    _InventoryStockFilter.available: 'Disponibles',
                    _InventoryStockFilter.low: 'Stock bajo',
                    _InventoryStockFilter.out: 'Agotados',
                    _InventoryStockFilter.high: 'Stock alto',
                    _InventoryStockFilter.priority: 'Prioridad',
                  };
                  final selected = _stockFilter == filter;
                  return ChoiceChip(
                    label: Text(labels[filter]!),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _stockFilter = filter;
                      _showAllProducts = filter == _InventoryStockFilter.all;
                    }),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? scheme.primary
                          : const Color(0xFF475569),
                    ),
                    side: BorderSide(
                      color: selected
                          ? scheme.primary.withOpacity(0.35)
                          : const Color(0xFFD9E3F0),
                    ),
                    backgroundColor: Colors.white,
                    selectedColor: scheme.primary.withOpacity(0.10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdjustmentStrip(
    ThemeData theme,
    ColorScheme scheme,
    ProductModel? product,
    double? previewStock,
  ) {
    final status = product == null ? null : _stockStatus(product, scheme);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: const BorderSide(color: Color(0xFFD9E3F0)),
    );
    final inputDecoration = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.2),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD9E3F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 960;
          final productInfo = SizedBox(
            width: compact ? constraints.maxWidth : 420,
            child: Row(
              children: [
                if (product != null)
                  ProductThumbnail.fromProduct(
                    product,
                    size: 42,
                    showBorder: false,
                    showShadow: false,
                    borderRadius: BorderRadius.circular(10),
                  )
                else
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product?.name ?? 'Selecciona un producto',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product == null
                            ? 'Elige una fila para preparar el ajuste.'
                            : '${product.code}  ·  ${_categoryName(product)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontFamily: 'Inter',
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final metrics = product == null
              ? const SizedBox.shrink()
              : Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _compactSummaryValue(
                      'Stock',
                      _numberFormat.format(product.stock),
                    ),
                    _compactSummaryValue(
                      'Mínimo',
                      _numberFormat.format(product.stockMin),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: status!.$2.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: status.$2.withOpacity(0.16)),
                      ),
                      child: Text(
                        status.$1,
                        style: TextStyle(
                          color: status.$2,
                          fontSize: 11,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                );

          final formFields = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: compact ? 220 : 190,
                child: DropdownButtonFormField<_InventoryAdjustmentMode>(
                  value: _mode,
                  elevation: 0,
                  menuMaxHeight: 180,
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  itemHeight: 48,
                  selectedItemBuilder: (context) => const [
                    Text('Incrementar', overflow: TextOverflow.ellipsis),
                    Text('Disminuir', overflow: TextOverflow.ellipsis),
                    Text('Fijar exacto', overflow: TextOverflow.ellipsis),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _mode = value);
                        },
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Tipo',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _InventoryAdjustmentMode.increase,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Incrementar stock',
                          style: TextStyle(height: 1.15),
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: _InventoryAdjustmentMode.decrease,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Disminuir stock',
                          style: TextStyle(height: 1.15),
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: _InventoryAdjustmentMode.exact,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Fijar stock exacto',
                          style: TextStyle(height: 1.15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: compact ? 150 : 116,
                child: TextFormField(
                  controller: _quantityController,
                  focusNode: _quantityFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                  decoration: inputDecoration.copyWith(
                    labelText: _mode == _InventoryAdjustmentMode.exact
                        ? 'Exacto'
                        : 'Cantidad',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(
                      value?.trim().replaceAll(',', '.') ?? '',
                    );
                    if (parsed == null) return 'Cantidad inválida';
                    if (parsed <= 0) return 'Debe ser mayor que 0';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) {
                    if (_parsedQuantity() != null &&
                        product != null &&
                        !_saving) {
                      _saveAdjustment();
                    }
                  },
                ),
              ),
              SizedBox(
                width: compact ? constraints.maxWidth : 220,
                child: TextFormField(
                  controller: _notesController,
                  minLines: 1,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Razón o notas',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    hintText: 'Conteo físico, merma...',
                    hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 42,
                child: FilledButton.icon(
                  onPressed: _loading || _saving || product == null
                      ? null
                      : _saveAdjustment,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 17),
                  label: const Text('Aplicar ajuste'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          );

          final preview = previewStock == null || product == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Nuevo stock: ${_numberFormat.format(previewStock)}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );

          return Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              productInfo,
              if (product != null) metrics,
              ?preview,
              formFields,
            ],
          );
        },
      ),
    );
  }

  Widget _compactSummaryValue(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10.5,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12.5,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsSection(
    ThemeData theme,
    ColorScheme scheme,
    List<ProductModel> products,
  ) {
    final waitingForFilter = !_hasActiveProductFilter;
    return ProductsSurface(
      key: ValueKey('products-$waitingForFilter'),
      padding: EdgeInsets.zero,
      radius: 14,
      child: Column(
        children: [
          _sectionTitle(
            theme,
            'Productos',
            waitingForFilter
                ? 'Busca o aplica un filtro para mostrar productos'
                : '${products.length} resultados disponibles',
          ),
          if (waitingForFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.manage_search_rounded,
                      size: 34,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Filtra para seleccionar un producto',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Escribe un código, nombre o elige una categoría. La lista queda oculta por defecto para mantener la pantalla limpia.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'Inter',
                        color: const Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  _inventoryHeaderCell('PRODUCTO', flex: 5),
                  _inventoryHeaderCell('CÓDIGO', flex: 2),
                  _inventoryHeaderCell('STOCK'),
                  _inventoryHeaderCell('MÍNIMO'),
                  _inventoryHeaderCell('ESTADO', flex: 2),
                ],
              ),
            ),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text('No hay productos con estos filtros.'),
              )
            else
              SizedBox(
                height: 430,
                child: Scrollbar(
                  controller: _productsScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _productsScrollController,
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final status = _stockStatus(product, scheme);
                      final selected = _selectedProduct?.id == product.id;
                      return InkWell(
                        hoverColor: const Color(0xFFF8FAFC),
                        onTap: () => _selectProduct(product),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? scheme.primary.withOpacity(0.06)
                                : Colors.transparent,
                            border: const Border(
                              top: BorderSide(color: Color(0xFFF1F5F9)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Row(
                                  children: [
                                    ProductThumbnail.fromProduct(
                                      product,
                                      size: 32,
                                      showBorder: false,
                                      showShadow: false,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12.8,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  product.code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _numberFormat.format(product.stock),
                                  style: TextStyle(
                                    color: status.$2,
                                    fontFamily: 'Inter',
                                    fontSize: 12.3,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _numberFormat.format(product.stockMin),
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontFamily: 'Inter',
                                    fontSize: 12.3,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: status.$2.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: status.$2.withOpacity(0.14),
                                      ),
                                    ),
                                    child: Text(
                                      status.$1,
                                      style: TextStyle(
                                        color: status.$2,
                                        fontSize: 10.5,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMovementsSection(ThemeData theme, ColorScheme scheme) {
    final movements = _recentAdjustments.take(8).toList();
    return ProductsSurface(
      key: const ValueKey('movements'),
      padding: EdgeInsets.zero,
      radius: 16,
      child: Column(
        children: [
          _sectionTitle(
            theme,
            'Movimientos recientes',
            'Últimos movimientos confirmados en la base de datos',
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
            )
          else if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text('Aún no hay movimientos registrados.'),
            )
          else
            ...movements.map((detail) {
              final movement = detail.movement;
              final positive =
                  movement.isInput ||
                  (movement.isAdjust && movement.quantity >= 0);
              final color = positive ? Colors.green.shade700 : scheme.error;
              return Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: color.withOpacity(0.10),
                      child: Icon(
                        positive
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        size: 17,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.productLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${movement.type.label}  ·  '
                            '${DateFormat('dd/MM/yyyy HH:mm').format(movement.createdAt)}  ·  '
                            '${movement.note?.trim().isNotEmpty == true ? movement.note!.trim() : 'Sin nota'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${positive ? '+' : '-'}${_numberFormat.format(movement.quantity.abs())}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _inventoryHeaderCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontFamily: 'Inter',
          fontSize: 10.8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontFamily: 'Inter',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _workspaceView == _StockWorkspaceView.products
                    ? Icons.inventory_2_outlined
                    : Icons.history_rounded,
                color: const Color(0xFF1A56DB),
                size: 19,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class InventoryMovementsPage extends StatelessWidget {
  const InventoryMovementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = productsResponsivePagePadding(constraints);
        return Padding(
          padding: padding,
          child: const Column(
            children: [
              _InventoryMovementsHeader(),
              SizedBox(height: 14),
              Expanded(child: _InventoryMovementsWorkspace()),
            ],
          ),
        );
      },
    );
  }
}

class _InventoryMovementsHeader extends StatelessWidget {
  const _InventoryMovementsHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ProductsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProductsSectionHeader(
            title: 'Movimientos de inventario',
            subtitle:
                'Consulta entradas, salidas y ajustes del stock con filtros por fecha, tipo y producto.',
            eyebrow: 'Inventario',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              'Nota: el historial actual no guarda instantáneas de stock anterior y nuevo por movimiento, así que esos valores no están disponibles en la base actual.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryMovementsWorkspace extends StatefulWidget {
  const _InventoryMovementsWorkspace();

  @override
  State<_InventoryMovementsWorkspace> createState() =>
      _InventoryMovementsWorkspaceState();
}

class _InventoryMovementsWorkspaceState
    extends State<_InventoryMovementsWorkspace> {
  final StockRepository _stockRepository = StockRepository();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tableScrollController = ScrollController();
  final ScrollController _rowsScrollController = ScrollController();
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  final NumberFormat _numberFormat = NumberFormat.decimalPattern('en_US');

  List<StockMovementDetail> _history = [];
  StockMovementType? _typeFilter;
  DateTimeRange? _dateRange;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableScrollController.dispose();
    _rowsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final items = await _stockRepository.getDetailedHistory(
        type: _typeFilter,
        from: _dateRange?.start,
        to: _dateRange?.end,
        limit: 250,
      );
      if (!mounted) return;
      setState(() => _history = items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el historial: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showFiltersPanel() async {
    final result = await showDialog<_InventoryMovementFiltersResult>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.18),
      useSafeArea: false,
      builder: (context) => _InventoryMovementFiltersPanel(
        initialType: _typeFilter,
        initialRange: _dateRange,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _typeFilter = result.type;
      _dateRange = result.range;
    });
    _loadHistory();
  }

  void _clearAllFilters() {
    setState(() {
      _typeFilter = null;
      _dateRange = null;
      _searchController.clear();
    });
    _loadHistory();
  }

  int get _activeFilterCount {
    var count = 0;
    if (_typeFilter != null) count++;
    if (_dateRange != null) count++;
    if (_searchController.text.trim().isNotEmpty) count++;
    return count;
  }

  String get _typeFilterLabel {
    switch (_typeFilter) {
      case StockMovementType.input:
        return 'Entradas';
      case StockMovementType.output:
        return 'Salidas';
      case StockMovementType.adjust:
        return 'Ajustes';
      case null:
        return 'Todos';
    }
  }

  String _rangeLabel(DateTimeRange range) {
    final formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
  }

  List<StockMovementDetail> _filteredHistory() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _history;
    return _history.where((detail) {
      return detail.productLabel.toLowerCase().contains(query) ||
          (detail.productCode?.toLowerCase().contains(query) ?? false) ||
          (detail.movement.note?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  String _movementLabel(StockMovementModel movement) {
    if (movement.isInput) return 'Entrada';
    if (movement.isOutput) return 'Salida';
    return 'Ajuste';
  }

  Color _movementColor(BuildContext context, StockMovementModel movement) {
    final scheme = Theme.of(context).colorScheme;
    if (movement.isInput) return Colors.green.shade700;
    if (movement.isOutput) return scheme.error;
    return scheme.primary;
  }

  String _qtyText(StockMovementModel movement) {
    if (movement.isOutput) {
      return '-${_numberFormat.format(movement.quantity.abs())}';
    }
    if (movement.isInput) {
      return '+${_numberFormat.format(movement.quantity.abs())}';
    }
    return '${movement.quantity >= 0 ? '+' : ''}${_numberFormat.format(movement.quantity)}';
  }

  Widget _tableHeaderCell(
    String label, {
    required double width,
    TextAlign align = TextAlign.left,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.visible,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Color(0xFF64748B),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _tableTextCell(
    String text, {
    required double width,
    TextAlign align = TextAlign.left,
    int maxLines = 1,
    Color color = const Color(0xFF111827),
    FontWeight weight = FontWeight.w700,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: align,
        maxLines: maxLines,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12.6,
          height: 1.25,
          fontWeight: weight,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTableHeader(ColorScheme scheme) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withOpacity(0.85)),
        ),
      ),
      child: Row(
        children: [
          _tableHeaderCell('Fecha', width: 160),
          _tableHeaderCell('Producto', width: 340),
          _tableHeaderCell('Tipo', width: 120),
          _tableHeaderCell('Cantidad', width: 110, align: TextAlign.right),
          _tableHeaderCell('Stock anterior', width: 135),
          _tableHeaderCell('Stock nuevo', width: 125),
          _tableHeaderCell('Usuario', width: 150),
          _tableHeaderCell('Referencia / notas', width: 430),
        ],
      ),
    );
  }

  Widget _buildMovementRow(
    BuildContext context,
    StockMovementDetail detail,
    int index,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final movement = detail.movement;
    final color = _movementColor(context, movement);
    final productLabel = detail.productCode == null
        ? detail.productLabel
        : '${detail.productLabel} • ${detail.productCode}';
    final note = detail.movement.note?.trim().isNotEmpty == true
        ? detail.movement.note!.trim()
        : 'Sin referencia';

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      color: index.isEven ? Colors.white : const Color(0xFFFBFDFF),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _tableTextCell(
            _dateTimeFormat.format(movement.createdAt),
            width: 160,
            color: const Color(0xFF334155),
          ),
          _tableTextCell(productLabel, width: 340, maxLines: 2),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _movementLabel(movement),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          ),
          _tableTextCell(
            _qtyText(movement),
            width: 110,
            align: TextAlign.right,
            color: color,
            weight: FontWeight.w900,
          ),
          _tableTextCell('N/D', width: 135, color: scheme.onSurfaceVariant),
          _tableTextCell('N/D', width: 125, color: scheme.onSurfaceVariant),
          _tableTextCell(detail.userLabel, width: 150, maxLines: 1),
          _tableTextCell(note, width: 430, maxLines: 2),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visibleItems = _filteredHistory();

    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SizedBox(
                    height: 46,
                    child: TextField(
                      controller: _searchController,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar producto, código o referencia',
                        hintStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 21),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar búsqueda',
                                onPressed: () =>
                                    setState(() => _searchController.clear()),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: scheme.outlineVariant,
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: scheme.outlineVariant,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _showFiltersPanel,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(
                      _activeFilterCount > 0 ? 'Filtros activos' : 'Filtrar',
                    ),
                    style: FilledButton.styleFrom(
                      foregroundColor: scheme.primary,
                      backgroundColor: scheme.primary.withOpacity(0.10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (_activeFilterCount > 0)
                    Positioned(
                      top: -7,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FilterSummaryChip(
                  icon: Icons.swap_vert_rounded,
                  label: 'Tipo: $_typeFilterLabel',
                ),
                if (_dateRange != null)
                  _FilterSummaryChip(
                    icon: Icons.date_range_rounded,
                    label: _rangeLabel(_dateRange!),
                  ),
                if (_searchController.text.trim().isNotEmpty)
                  _FilterSummaryChip(
                    icon: Icons.search_rounded,
                    label: _searchController.text.trim(),
                  ),
                TextButton.icon(
                  onPressed: _clearAllFilters,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (visibleItems.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No se encontraron movimientos con los filtros actuales.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = math.max(constraints.maxWidth, 1570.0);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.78),
                        ),
                      ),
                      child: Scrollbar(
                        controller: _tableScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _tableScrollController,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            height: constraints.maxHeight,
                            child: Column(
                              children: [
                                _buildTableHeader(scheme),
                                Expanded(
                                  child: Scrollbar(
                                    controller: _rowsScrollController,
                                    thumbVisibility: true,
                                    child: ListView.separated(
                                      controller: _rowsScrollController,
                                      primary: false,
                                      padding: EdgeInsets.zero,
                                      itemCount: visibleItems.length,
                                      separatorBuilder: (context, index) =>
                                          Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: scheme.outlineVariant
                                                .withOpacity(0.65),
                                          ),
                                      itemBuilder: (context, index) {
                                        return _buildMovementRow(
                                          context,
                                          visibleItems[index],
                                          index,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _InventoryMovementFiltersResult {
  const _InventoryMovementFiltersResult({
    required this.type,
    required this.range,
  });

  final StockMovementType? type;
  final DateTimeRange? range;
}

class _InventoryMovementFiltersPanel extends StatefulWidget {
  const _InventoryMovementFiltersPanel({
    required this.initialType,
    required this.initialRange,
  });

  final StockMovementType? initialType;
  final DateTimeRange? initialRange;

  @override
  State<_InventoryMovementFiltersPanel> createState() =>
      _InventoryMovementFiltersPanelState();
}

class _InventoryMovementFiltersPanelState
    extends State<_InventoryMovementFiltersPanel> {
  StockMovementType? _type;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _range = widget.initialRange;
  }

  int get _activeCount {
    var count = 0;
    if (_type != null) count++;
    if (_range != null) count++;
    return count;
  }

  String _rangeLabel(DateTimeRange range) {
    final formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange:
          _range ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );
    if (range == null || !mounted) return;
    setState(() => _range = range);
  }

  void _clear() {
    setState(() {
      _type = null;
      _range = null;
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _InventoryMovementFiltersResult(type: _type, range: _range),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final panelWidth = viewport.width < 620
        ? viewport.width
        : (viewport.width * 0.28).clamp(390.0, 460.0);

    return Align(
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: scheme.outlineVariant.withOpacity(0.85),
                        ),
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
                          child: Icon(
                            Icons.tune_rounded,
                            color: scheme.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Filtros de movimientos',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0F172A),
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _activeCount == 0
                                    ? 'Sin filtros activos'
                                    : '$_activeCount filtros activos',
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
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                      children: [
                        Text(
                          'Ajusta fecha y tipo de movimiento sin cubrir la tabla.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _MovementFilterSection(
                          title: 'Tipo de movimiento',
                          icon: Icons.swap_vert_rounded,
                          child: Column(
                            children: [
                              _movementOption(theme, scheme, null, 'Todos'),
                              _movementOption(
                                theme,
                                scheme,
                                StockMovementType.input,
                                'Entradas',
                              ),
                              _movementOption(
                                theme,
                                scheme,
                                StockMovementType.output,
                                'Salidas',
                              ),
                              _movementOption(
                                theme,
                                scheme,
                                StockMovementType.adjust,
                                'Ajustes',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _MovementFilterSection(
                          title: 'Rango de fechas',
                          icon: Icons.date_range_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withOpacity(
                                      0.75,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _range == null
                                      ? 'Sin rango seleccionado'
                                      : _rangeLabel(_range!),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.tonalIcon(
                                onPressed: _pickRange,
                                icon: const Icon(Icons.calendar_month_rounded),
                                label: const Text('Seleccionar rango'),
                              ),
                              if (_range != null) ...[
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _range = null),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('Quitar rango'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: scheme.outlineVariant.withOpacity(0.85),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _clear,
                            child: const Text('Limpiar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _apply,
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _movementOption(
    ThemeData theme,
    ColorScheme scheme,
    StockMovementType? value,
    String label,
  ) {
    final selected = _type == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _type = value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementFilterSection extends StatelessWidget {
  const _MovementFilterSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

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

class _FilterSummaryChip extends StatelessWidget {
  const _FilterSummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.primary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class InventoryCountPage extends StatefulWidget {
  const InventoryCountPage({super.key});

  @override
  State<InventoryCountPage> createState() => _InventoryCountPageState();
}

class _InventoryCountPageState extends State<InventoryCountPage> {
  final ProductsRepository _productsRepo = ProductsRepository();
  final CategoriesRepository _categoriesRepo = CategoriesRepository();
  final ScrollController _categoryTableScrollController = ScrollController();
  final ScrollController _supplierTableScrollController = ScrollController();

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD\$ ',
    decimalDigits: 2,
  );

  final NumberFormat _unitsFormat = NumberFormat.decimalPattern('en_US');

  bool _isLoading = true;
  int _totalProducts = 0;
  double _totalUnits = 0;
  double _totalInventoryValue = 0;
  double _totalPotentialRevenue = 0;
  double _totalPotentialProfit = 0;
  double _averageMargin = 0;

  List<Map<String, dynamic>> _inventoryByCategory = [];
  List<Map<String, dynamic>> _inventoryBySupplier = [];
  Map<int, String> _categoryNameById = <int, String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadReportData);
  }

  @override
  void dispose() {
    _categoryTableScrollController.dispose();
    _supplierTableScrollController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  String _firstText(
    Map<String, dynamic> row,
    List<String> keys, {
    required String fallback,
  }) {
    for (final key in keys) {
      final value = row[key];
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  int? _firstId(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      if (!row.containsKey(key)) continue;
      final value = row[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString().trim() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _resolvedCategoryName(Map<String, dynamic> row) {
    final directName = _firstText(row, const [
      'name',
      'category_name',
      'category',
      'category_label',
      'label',
      'group_name',
    ], fallback: '');
    if (directName.isNotEmpty &&
        !RegExp(
          r'^Categoría\s*#?\d+$',
          caseSensitive: false,
        ).hasMatch(directName)) {
      return directName;
    }

    final categoryId = _firstId(row, const ['category_id', 'categoryId', 'id']);
    if (categoryId != null) {
      return _categoryNameById[categoryId] ?? 'Categoría sin nombre';
    }

    return 'Sin categoría';
  }

  String _resolvedSupplierName(Map<String, dynamic> row) {
    final directName = _firstText(row, const [
      'name',
      'supplier_name',
      'provider_name',
      'supplier',
      'provider',
      'supplier_label',
      'provider_label',
      'label',
      'group_name',
    ], fallback: '');

    if (directName.isNotEmpty &&
        !RegExp(
          r'^(Suplidor|Proveedor)\s*#?\d+$',
          caseSensitive: false,
        ).hasMatch(directName)) {
      return directName;
    }

    return 'Sin suplidor';
  }

  double _firstNumber(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      if (!row.containsKey(key)) continue;
      final value = _toDouble(row[key]);
      if (value != 0 || row[key] != null) return value;
    }
    return 0;
  }

  dynamic _readDynamic(ProductModel product, String field) {
    final dynamic value = product;
    try {
      switch (field) {
        case 'cost':
          return value.cost;
        case 'costPrice':
          return value.costPrice;
        case 'purchasePrice':
          return value.purchasePrice;
        case 'priceCost':
          return value.priceCost;
        case 'unitCost':
          return value.unitCost;
        case 'price':
          return value.price;
        case 'salePrice':
          return value.salePrice;
        case 'sellingPrice':
          return value.sellingPrice;
        case 'unitPrice':
          return value.unitPrice;
        case 'supplierId':
          return value.supplierId;
        case 'providerId':
          return value.providerId;
        case 'supplierName':
          return value.supplierName;
        case 'providerName':
          return value.providerName;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  double _productCost(ProductModel product) {
    for (final field in const [
      'cost',
      'costPrice',
      'purchasePrice',
      'priceCost',
      'unitCost',
    ]) {
      final value = _readDynamic(product, field);
      if (value != null) return _toDouble(value);
    }
    return 0;
  }

  double _productSalePrice(ProductModel product) {
    for (final field in const [
      'price',
      'salePrice',
      'sellingPrice',
      'unitPrice',
    ]) {
      final value = _readDynamic(product, field);
      if (value != null) return _toDouble(value);
    }
    return 0;
  }

  String _productSupplierName(ProductModel product) {
    for (final field in const ['supplierName', 'providerName']) {
      final value = _readDynamic(product, field);
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }

    return 'Sin suplidor';
  }

  List<Map<String, dynamic>> _normalizeBreakdownRows(
    List<Map<String, dynamic>> source, {
    required String Function(Map<String, dynamic> row) resolveName,
  }) {
    return source
        .map((raw) {
          final row = Map<String, dynamic>.from(raw);

          final name = resolveName(row);

          final count = _firstNumber(row, const [
            'product_count',
            'products_count',
            'count',
            'total_products',
            'products',
          ]);

          final units = _firstNumber(row, const [
            'total_units',
            'units',
            'stock',
            'total_stock',
            'stock_units',
          ]);

          final inventoryValue = _firstNumber(row, const [
            'inventory_value',
            'total_inventory_value',
            'cost_value',
            'total_cost',
            'total_value',
            'investment',
            'inversion',
          ]);

          final revenue = _firstNumber(row, const [
            'potential_revenue',
            'total_potential_revenue',
            'sale_value',
            'sales_value',
            'total_sale_value',
            'total_revenue',
            'revenue',
            'venta',
          ]);

          var profit = _firstNumber(row, const [
            'potential_profit',
            'total_potential_profit',
            'total_profit',
            'profit',
            'ganancia',
          ]);

          if (profit == 0 && (revenue != 0 || inventoryValue != 0)) {
            profit = revenue - inventoryValue;
          }

          return <String, dynamic>{
            'name': name,
            'product_count': count.toInt(),
            'total_units': units,
            'inventory_value': inventoryValue,
            'potential_revenue': revenue,
            'potential_profit': profit,
          };
        })
        .where((row) {
          return _toInt(row['product_count']) > 0 ||
              _toDouble(row['total_units']).abs() > 0.0001 ||
              _toDouble(row['inventory_value']).abs() > 0.0001 ||
              _toDouble(row['potential_revenue']).abs() > 0.0001 ||
              _toDouble(row['potential_profit']).abs() > 0.0001;
        })
        .toList()
      ..sort(
        (a, b) => _toDouble(
          b['inventory_value'],
        ).compareTo(_toDouble(a['inventory_value'])),
      );
  }

  List<Map<String, dynamic>> _buildCategoryFallback(
    List<ProductModel> products,
  ) {
    final groups = <String, Map<String, dynamic>>{};

    for (final product in products) {
      final categoryName = product.categoryId == null
          ? 'Sin categoría'
          : _categoryNameById[product.categoryId!] ?? 'Categoría sin nombre';

      final row = groups.putIfAbsent(
        categoryName,
        () => <String, dynamic>{
          'name': categoryName,
          'product_count': 0,
          'total_units': 0.0,
          'inventory_value': 0.0,
          'potential_revenue': 0.0,
          'potential_profit': 0.0,
        },
      );

      final stock = product.stock;
      final cost = _productCost(product);
      final price = _productSalePrice(product);

      row['product_count'] = _toInt(row['product_count']) + 1;
      row['total_units'] = _toDouble(row['total_units']) + stock;
      row['inventory_value'] =
          _toDouble(row['inventory_value']) + (stock * cost);
      row['potential_revenue'] =
          _toDouble(row['potential_revenue']) + (stock * price);
      row['potential_profit'] =
          _toDouble(row['potential_profit']) + (stock * (price - cost));
    }

    return groups.values.toList()..sort(
      (a, b) => _toDouble(
        b['inventory_value'],
      ).compareTo(_toDouble(a['inventory_value'])),
    );
  }

  List<Map<String, dynamic>> _buildSupplierFallback(
    List<ProductModel> products,
  ) {
    final groups = <String, Map<String, dynamic>>{};

    for (final product in products) {
      final supplierName = _productSupplierName(product);

      final row = groups.putIfAbsent(
        supplierName,
        () => <String, dynamic>{
          'name': supplierName,
          'product_count': 0,
          'total_units': 0.0,
          'inventory_value': 0.0,
          'potential_revenue': 0.0,
          'potential_profit': 0.0,
        },
      );

      final stock = product.stock;
      final cost = _productCost(product);
      final price = _productSalePrice(product);

      row['product_count'] = _toInt(row['product_count']) + 1;
      row['total_units'] = _toDouble(row['total_units']) + stock;
      row['inventory_value'] =
          _toDouble(row['inventory_value']) + (stock * cost);
      row['potential_revenue'] =
          _toDouble(row['potential_revenue']) + (stock * price);
      row['potential_profit'] =
          _toDouble(row['potential_profit']) + (stock * (price - cost));
    }

    return groups.values.toList()..sort(
      (a, b) => _toDouble(
        b['inventory_value'],
      ).compareTo(_toDouble(a['inventory_value'])),
    );
  }

  bool _breakdownHasFinancialValues(List<Map<String, dynamic>> rows) {
    return rows.any(
      (row) =>
          _toDouble(row['inventory_value']).abs() > 0.0001 ||
          _toDouble(row['potential_revenue']).abs() > 0.0001 ||
          _toDouble(row['potential_profit']).abs() > 0.0001,
    );
  }

  Future<void> _loadReportData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _productsRepo.getAll(filters: const ProductFilters(isActive: true)),
        _productsRepo.calculateTotalInventoryValue(),
        _productsRepo.calculateTotalPotentialRevenue(),
        _productsRepo.calculateTotalPotentialProfit(),
        _productsRepo.getInventoryByCategory(),
        _productsRepo.getInventoryBySupplier(),
        _categoriesRepo.getAll(),
      ]);

      final products = results[0] as List<ProductModel>;
      final repositoryInventoryValue = _toDouble(results[1]);
      final repositoryPotentialRevenue = _toDouble(results[2]);
      final repositoryPotentialProfit = _toDouble(results[3]);

      final rawCategory = (results[4] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final rawSupplier = (results[5] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final categories = results[6] as List<CategoryModel>;
      _categoryNameById = <int, String>{
        for (final category in categories)
          if (category.id != null && category.name.trim().isNotEmpty)
            category.id!: category.name.trim(),
      };

      final normalizedCategory = _normalizeBreakdownRows(
        rawCategory,
        resolveName: _resolvedCategoryName,
      );

      final normalizedSupplier = _normalizeBreakdownRows(
        rawSupplier,
        resolveName: _resolvedSupplierName,
      );

      final categoryFallback = _buildCategoryFallback(products);
      final supplierFallback = _buildSupplierFallback(products);

      final categoryHasRealNames = normalizedCategory.any(
        (row) =>
            (row['name']?.toString().trim().isNotEmpty ?? false) &&
            row['name'] != 'Sin categoría' &&
            row['name'] != 'Categoría sin nombre',
      );

      final supplierHasRealNames = normalizedSupplier.any(
        (row) =>
            (row['name']?.toString().trim().isNotEmpty ?? false) &&
            row['name'] != 'Sin suplidor',
      );

      final byCategory =
          categoryHasRealNames ||
              _breakdownHasFinancialValues(normalizedCategory)
          ? normalizedCategory
          : categoryFallback;

      final bySupplier =
          supplierHasRealNames ||
              _breakdownHasFinancialValues(normalizedSupplier)
          ? normalizedSupplier
          : supplierFallback;

      final totalUnits = products.fold<double>(
        0,
        (sum, product) => sum + product.stock,
      );

      final fallbackInventoryValue = products.fold<double>(
        0,
        (sum, product) => sum + (product.stock * _productCost(product)),
      );

      final fallbackRevenue = products.fold<double>(
        0,
        (sum, product) => sum + (product.stock * _productSalePrice(product)),
      );

      final fallbackProfit = fallbackRevenue - fallbackInventoryValue;

      final inventoryValue = repositoryInventoryValue.abs() > 0.0001
          ? repositoryInventoryValue
          : fallbackInventoryValue;

      final potentialRevenue = repositoryPotentialRevenue.abs() > 0.0001
          ? repositoryPotentialRevenue
          : fallbackRevenue;

      final potentialProfit = repositoryPotentialProfit.abs() > 0.0001
          ? repositoryPotentialProfit
          : fallbackProfit;

      if (!mounted) return;

      setState(() {
        _totalProducts = products.length;
        _totalUnits = totalUnits;
        _totalInventoryValue = inventoryValue;
        _totalPotentialRevenue = potentialRevenue;
        _totalPotentialProfit = potentialProfit;
        _averageMargin = potentialRevenue > 0
            ? (potentialProfit / potentialRevenue) * 100
            : 0;
        _inventoryByCategory = byCategory;
        _inventoryBySupplier = bySupplier;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar reporte: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _loadReportData,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              _buildHeader(theme, scheme),
              const SizedBox(height: 14),
              if (_isLoading)
                const ProductsSurface(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _buildKpiGrid(theme, scheme),
                const SizedBox(height: 14),
                _buildCategoryBreakdown(theme, scheme),
                const SizedBox(height: 14),
                _buildSupplierBreakdown(theme, scheme),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme scheme) {
    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      radius: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'INVENTARIO',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Reporte de inventario',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    letterSpacing: -0.6,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Resumen de productos, inversión y ganancia potencial.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<_ReportAction>(
            onSelected: (action) {
              switch (action) {
                case _ReportAction.exportPdf:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exportar PDF - próximamente'),
                    ),
                  );
                  break;
                case _ReportAction.exportExcel:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exportar Excel - próximamente'),
                    ),
                  );
                  break;
                case _ReportAction.print:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Imprimir - próximamente')),
                  );
                  break;
                case _ReportAction.refresh:
                  _loadReportData();
                  break;
              }
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 4,
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black.withOpacity(0.10),
            offset: const Offset(0, 6),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ReportAction.exportPdf,
                height: 42,
                child: Row(
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 18,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Exportar PDF',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _ReportAction.exportExcel,
                height: 42,
                child: Row(
                  children: [
                    Icon(
                      Icons.table_chart_outlined,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Exportar Excel',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _ReportAction.print,
                height: 42,
                child: Row(
                  children: [
                    Icon(Icons.print_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    const Text(
                      'Imprimir',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 6),
              PopupMenuItem(
                value: _ReportAction.refresh,
                height: 42,
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Actualizar datos',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: const Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(ThemeData theme, ColorScheme scheme) {
    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.dashboard_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Resumen general',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1450
                  ? 6
                  : width >= 1050
                  ? 3
                  : width >= 680
                  ? 2
                  : 1;
              const gap = 10.0;
              final cardWidth = (width - (gap * (columns - 1))) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _buildKpiCard(
                    width: cardWidth,
                    scheme: scheme,
                    icon: Icons.inventory_2_rounded,
                    label: 'Productos activos',
                    value: _unitsFormat.format(_totalProducts),
                    color: Colors.indigo,
                  ),
                  _buildKpiCard(
                    width: cardWidth,
                    scheme: scheme,
                    icon: Icons.inventory_rounded,
                    label: 'Unidades en stock',
                    value: _unitsFormat.format(_totalUnits),
                    color: Colors.blue,
                  ),
                  _buildKpiCard(
                    width: cardWidth,
                    scheme: scheme,
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Inversión total',
                    value: _currencyFormat.format(_totalInventoryValue),
                    color: Colors.teal,
                  ),
                  _buildKpiCard(
                    width: cardWidth,
                    scheme: scheme,
                    icon: Icons.attach_money_rounded,
                    label: 'Valor de venta',
                    value: _currencyFormat.format(_totalPotentialRevenue),
                    color: Colors.green,
                  ),
                  _buildKpiCard(
                    width: cardWidth,
                    scheme: scheme,
                    icon: Icons.trending_up_rounded,
                    label: 'Ganancia potencial',
                    value: _currencyFormat.format(_totalPotentialProfit),
                    color: Colors.purple,
                  ),
                  _buildKpiCard(
                    width: cardWidth,
                    scheme: scheme,
                    icon: Icons.percent_rounded,
                    label: 'Margen sobre venta',
                    value: '${_averageMargin.toStringAsFixed(1)}%',
                    color: Colors.orange,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required double width,
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15), width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Inter',
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(ThemeData theme, ColorScheme scheme) {
    return _buildBreakdownCard(
      theme: theme,
      scheme: scheme,
      title: 'Por categoría',
      icon: Icons.category_rounded,
      accent: scheme.primary,
      countLabel: '${_inventoryByCategory.length} categorías',
      emptyText: 'No hay datos de inventario por categoría',
      firstColumnTitle: 'Categoría',
      rows: _inventoryByCategory,
      scrollController: _categoryTableScrollController,
    );
  }

  Widget _buildSupplierBreakdown(ThemeData theme, ColorScheme scheme) {
    return _buildBreakdownCard(
      theme: theme,
      scheme: scheme,
      title: 'Por suplidor',
      icon: Icons.local_shipping_rounded,
      accent: scheme.tertiary,
      countLabel: '${_inventoryBySupplier.length} suplidores',
      emptyText: 'No hay datos de inventario por suplidor',
      firstColumnTitle: 'Suplidor',
      rows: _inventoryBySupplier,
      scrollController: _supplierTableScrollController,
    );
  }

  Widget _buildBreakdownCard({
    required ThemeData theme,
    required ColorScheme scheme,
    required String title,
    required IconData icon,
    required Color accent,
    required String countLabel,
    required String emptyText,
    required String firstColumnTitle,
    required List<Map<String, dynamic>> rows,
    required ScrollController scrollController,
  }) {
    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Text(
                countLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  emptyText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        headingRowHeight: 42,
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 54,
                        columnSpacing: 26,
                        horizontalMargin: 12,
                        headingTextStyle: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'Inter',
                          fontSize: 11,
                        ),
                        columns: [
                          DataColumn(label: Text(firstColumnTitle)),
                          const DataColumn(
                            label: Text('Productos'),
                            numeric: true,
                          ),
                          const DataColumn(
                            label: Text('Unidades'),
                            numeric: true,
                          ),
                          const DataColumn(
                            label: Text('Inversión'),
                            numeric: true,
                          ),
                          const DataColumn(
                            label: Text('Valor venta'),
                            numeric: true,
                          ),
                          const DataColumn(
                            label: Text('Ganancia'),
                            numeric: true,
                          ),
                        ],
                        rows: rows.map((item) {
                          final name =
                              item['name']?.toString().trim().isNotEmpty == true
                              ? item['name'].toString().trim()
                              : firstColumnTitle == 'Categoría'
                              ? 'Sin categoría'
                              : 'Sin suplidor';

                          final count = _toInt(item['product_count']);
                          final units = _toDouble(item['total_units']);
                          final invValue = _toDouble(item['inventory_value']);
                          final revValue = _toDouble(item['potential_revenue']);
                          final profit = _toDouble(item['potential_profit']);

                          final profitColor = profit < 0
                              ? scheme.error
                              : Colors.green.shade700;

                          return DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _unitsFormat.format(count),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _unitsFormat.format(units),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _currencyFormat.format(invValue),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _currencyFormat.format(revValue),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _currencyFormat.format(profit),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: profitColor,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

enum _ReportAction { exportPdf, exportExcel, print, refresh }
