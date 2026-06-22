import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/session/session_manager.dart';
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
        return ListView(
          padding: productsResponsivePagePadding(constraints),
          children: const [
            _InventoryMovementsHeader(),
            SizedBox(height: 14),
            _InventoryMovementsWorkspace(),
          ],
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange:
          _dateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );
    if (range == null) return;
    setState(() => _dateRange = range);
    _loadHistory();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visibleItems = _filteredHistory();
    final rangeLabel = _dateRange == null
        ? 'Rango de fechas'
        : '${DateFormat('dd/MM/yyyy').format(_dateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_dateRange!.end)}';

    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 240,
                child: FilledButton.tonalIcon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(rangeLabel),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<StockMovementType?>(
                  value: _typeFilter,
                  decoration: InputDecoration(
                    labelText: 'Tipo de movimiento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem<StockMovementType?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem<StockMovementType?>(
                      value: StockMovementType.input,
                      child: Text('Entradas'),
                    ),
                    DropdownMenuItem<StockMovementType?>(
                      value: StockMovementType.output,
                      child: Text('Salidas'),
                    ),
                    DropdownMenuItem<StockMovementType?>(
                      value: StockMovementType.adjust,
                      child: Text('Ajustes'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _typeFilter = value);
                    _loadHistory();
                  },
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Buscar producto',
                    hintText: 'Nombre, código o nota',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              if (_dateRange != null)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _dateRange = null);
                    _loadHistory();
                  },
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Limpiar rango'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visibleItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No se encontraron movimientos con los filtros actuales.',
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 46,
                dataRowMinHeight: 58,
                dataRowMaxHeight: 66,
                columnSpacing: 20,
                headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'Inter',
                ),
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Producto')),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Cantidad')),
                  DataColumn(label: Text('Stock anterior')),
                  DataColumn(label: Text('Stock nuevo')),
                  DataColumn(label: Text('Usuario')),
                  DataColumn(label: Text('Referencia / notas')),
                ],
                rows: visibleItems.map((detail) {
                  final movement = detail.movement;
                  final color = _movementColor(context, movement);
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(_dateTimeFormat.format(movement.createdAt)),
                      ),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            detail.productCode == null
                                ? detail.productLabel
                                : '${detail.productLabel} • ${detail.productCode}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
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
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${movement.quantity >= 0 ? '+' : ''}${_numberFormat.format(movement.quantity)}',
                        ),
                      ),
                      const DataCell(Text('N/D')),
                      const DataCell(Text('N/D')),
                      DataCell(Text(detail.userLabel)),
                      DataCell(
                        SizedBox(
                          width: 260,
                          child: Text(
                            detail.movement.note?.trim().isNotEmpty == true
                                ? detail.movement.note!.trim()
                                : 'Sin referencia',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
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
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD\$ ',
    decimalDigits: 2,
  );
  final NumberFormat _unitsFormat = NumberFormat.decimalPattern();

  bool _isLoading = true;
  int _totalProducts = 0;
  double _totalUnits = 0;
  double _totalInventoryValue = 0;
  double _totalPotentialRevenue = 0;
  double _totalPotentialProfit = 0;
  double _averageMargin = 0;
  List<Map<String, dynamic>> _inventoryByCategory = [];
  List<Map<String, dynamic>> _inventoryBySupplier = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadReportData);
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
      ]);

      final products = results[0] as List<ProductModel>;
      final inventoryValue = results[1] as double;
      final potentialRevenue = results[2] as double;
      final potentialProfit = results[3] as double;
      final byCategory = results[4] as List<Map<String, dynamic>>;
      final bySupplier = results[5] as List<Map<String, dynamic>>;

      final totalUnits = products.fold<double>(0, (sum, p) => sum + p.stock);

      if (!mounted) return;

      setState(() {
        _totalProducts = products.length;
        _totalUnits = totalUnits;
        _totalInventoryValue = inventoryValue;
        _totalPotentialRevenue = potentialRevenue;
        _totalPotentialProfit = potentialProfit;
        _averageMargin = inventoryValue > 0
            ? (potentialProfit / inventoryValue) * 100
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
                case _ReportAction.exportExcel:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exportar Excel - próximamente'),
                    ),
                  );
                case _ReportAction.print:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Imprimir - próximamente')),
                  );
                case _ReportAction.refresh:
                  _loadReportData();
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
                    Text(
                      'Exportar PDF',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
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
                    Text(
                      'Exportar Excel',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
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
                    Text(
                      'Imprimir',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
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
                    Text(
                      'Actualizar datos',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
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
              child: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: const Color(0xFF0F172A),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildKpiCard(
                scheme: scheme,
                icon: Icons.inventory_2_rounded,
                label: 'Productos activos',
                value: _unitsFormat.format(_totalProducts),
                color: Colors.indigo,
              ),
              _buildKpiCard(
                scheme: scheme,
                icon: Icons.inventory_rounded,
                label: 'Unidades en stock',
                value: _unitsFormat.format(_totalUnits),
                color: Colors.blue,
              ),
              _buildKpiCard(
                scheme: scheme,
                icon: Icons.account_balance_wallet_rounded,
                label: 'Inversión total',
                value: _currencyFormat.format(_totalInventoryValue),
                color: Colors.teal,
              ),
              _buildKpiCard(
                scheme: scheme,
                icon: Icons.attach_money_rounded,
                label: 'Valor de venta',
                value: _currencyFormat.format(_totalPotentialRevenue),
                color: Colors.green,
              ),
              _buildKpiCard(
                scheme: scheme,
                icon: Icons.trending_up_rounded,
                label: 'Ganancia potencial',
                value: _currencyFormat.format(_totalPotentialProfit),
                color: Colors.purple,
              ),
              _buildKpiCard(
                scheme: scheme,
                icon: Icons.percent_rounded,
                label: 'Margen promedio',
                value: '${_averageMargin.toStringAsFixed(1)}%',
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15), width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Inter',
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
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
                  Icons.category_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Por categoría',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Text(
                '${_inventoryByCategory.length} categorías',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_inventoryByCategory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No hay datos de inventario por categoría',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 46,
                dataRowMaxHeight: 50,
                columnSpacing: 20,
                headingTextStyle: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'Inter',
                  fontSize: 11,
                ),
                columns: const [
                  DataColumn(label: Text('Categoría')),
                  DataColumn(label: Text('Prod.'), numeric: true),
                  DataColumn(label: Text('Unds.'), numeric: true),
                  DataColumn(label: Text('Inversión'), numeric: true),
                  DataColumn(label: Text('Venta'), numeric: true),
                  DataColumn(label: Text('Ganancia'), numeric: true),
                ],
                rows: _inventoryByCategory.map((item) {
                  final name = (item['name'] as String?) ?? 'Sin categoría';
                  final count = (item['product_count'] as num?)?.toInt() ?? 0;
                  final units = (item['total_units'] as num?)?.toDouble() ?? 0;
                  final invValue =
                      (item['inventory_value'] as num?)?.toDouble() ?? 0;
                  final revValue =
                      (item['potential_revenue'] as num?)?.toDouble() ?? 0;
                  final profit =
                      (item['potential_profit'] as num?)?.toDouble() ?? 0;

                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 160,
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
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DataCell(
                        Text(
                          _currencyFormat.format(revValue),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DataCell(
                        Text(
                          _currencyFormat.format(profit),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSupplierBreakdown(ThemeData theme, ColorScheme scheme) {
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
                  color: scheme.tertiary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  size: 15,
                  color: scheme.tertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Por suplidor',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Text(
                '${_inventoryBySupplier.length} suplidores',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_inventoryBySupplier.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No hay datos de inventario por suplidor',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 46,
                dataRowMaxHeight: 50,
                columnSpacing: 20,
                headingTextStyle: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'Inter',
                  fontSize: 11,
                ),
                columns: const [
                  DataColumn(label: Text('Suplidor')),
                  DataColumn(label: Text('Prod.'), numeric: true),
                  DataColumn(label: Text('Unds.'), numeric: true),
                  DataColumn(label: Text('Inversión'), numeric: true),
                  DataColumn(label: Text('Venta'), numeric: true),
                  DataColumn(label: Text('Ganancia'), numeric: true),
                ],
                rows: _inventoryBySupplier.map((item) {
                  final name = (item['name'] as String?) ?? 'Sin suplidor';
                  final count = (item['product_count'] as num?)?.toInt() ?? 0;
                  final units = (item['total_units'] as num?)?.toDouble() ?? 0;
                  final invValue =
                      (item['inventory_value'] as num?)?.toDouble() ?? 0;
                  final revValue =
                      (item['potential_revenue'] as num?)?.toDouble() ?? 0;
                  final profit =
                      (item['potential_profit'] as num?)?.toDouble() ?? 0;

                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 160,
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
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DataCell(
                        Text(
                          _currencyFormat.format(revValue),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DataCell(
                        Text(
                          _currencyFormat.format(profit),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

enum _ReportAction { exportPdf, exportExcel, print, refresh }
