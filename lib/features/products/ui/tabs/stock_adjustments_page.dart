import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/categories_repository.dart';
import '../../data/products_repository.dart';
import '../../data/stock_repository.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../models/stock_movement_model.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../settings/data/user_model.dart';
import '../dialogs/product_details_dialog.dart';
import '../dialogs/stock_adjust_dialog.dart';
import '../widgets/product_thumbnail.dart';
import '../widgets/products_surface.dart';

enum _StockFilter {
  all('Todos', Icons.all_inclusive_rounded),
  available('Disponible', Icons.check_circle_outline_rounded),
  lowStock('Stock bajo', Icons.inventory_2_outlined),
  outOfStock('Agotados', Icons.error_outline_rounded),
  highStock('Stock alto', Icons.trending_up_rounded),
  attention('Prioridad', Icons.priority_high_rounded);

  final String label;
  final IconData icon;

  const _StockFilter(this.label, this.icon);
}

class StockAdjustmentsPage extends StatefulWidget {
  const StockAdjustmentsPage({super.key, this.onOpenInventory});

  final VoidCallback? onOpenInventory;

  @override
  State<StockAdjustmentsPage> createState() => _StockAdjustmentsPageState();
}

class _StockAdjustmentsPageState extends State<StockAdjustmentsPage> {
  final ProductsRepository _productsRepo = ProductsRepository();
  final CategoriesRepository _categoriesRepo = CategoriesRepository();
  final StockRepository _stockRepo = StockRepository();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final FocusNode _codeFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _quantityFocusNode = FocusNode();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final NumberFormat _numberFormat = NumberFormat.decimalPattern('en_US');

  Timer? _debounce;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isAdmin = false;
  bool _showProducts = false;

  UserPermissions _permissions = UserPermissions.cashier();

  List<ProductModel> _allProducts = [];
  List<ProductModel> _lowStockProducts = [];
  List<ProductModel> _outOfStockProducts = [];
  List<CategoryModel> _categories = [];
  List<StockMovementDetail> _recentAdjustments = [];

  _StockFilter _filter = _StockFilter.all;
  int? _selectedCategoryId;
  ProductModel? _selectedProduct;
  StockMovementType _adjustmentMode = StockMovementType.input;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _codeController.addListener(_onCodeChanged);
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _codeController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    _codeFocusNode.dispose();
    _searchFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _onCodeChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _autoSelectByCode();
    });
  }

  Future<void> _autoSelectByCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final localMatch = _allProducts.where((product) {
      return product.code.toLowerCase() == code.toLowerCase();
    }).toList();

    if (localMatch.isNotEmpty) {
      setState(() => _selectedProduct = localMatch.first);
      return;
    }

    final found = await _productsRepo.getByCode(code);

    if (!mounted) return;

    if (found != null) {
      setState(() => _selectedProduct = found);
    }
  }

  Future<void> _selectProductFromInput(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) return;

    ProductModel? match;

    for (final product in _allProducts) {
      final sameCode = product.code.toLowerCase() == value.toLowerCase();
      final sameName = product.name.toLowerCase() == value.toLowerCase();

      if (sameCode || sameName) {
        match = product;
        break;
      }
    }

    match ??= _allProducts.cast<ProductModel?>().firstWhere((product) {
      if (product == null) return false;

      final query = value.toLowerCase();
      return product.code.toLowerCase().contains(query) ||
          product.name.toLowerCase().contains(query);
    }, orElse: () => null);

    match ??= await _productsRepo.getByCode(value);

    if (!mounted) return;

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró un producto con ese código o nombre.'),
        ),
      );
      return;
    }

    setState(() {
      _selectedProduct = match;
      _codeController.text = match!.code;
      _codeController.selection = TextSelection.collapsed(
        offset: _codeController.text.length,
      );
    });

    _quantityFocusNode.requestFocus();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        AuthRepository.getCurrentPermissions(),
        AuthRepository.isAdmin(),
        _productsRepo.getAll(),
        _productsRepo.getLowStock(),
        _productsRepo.getOutOfStock(),
        _categoriesRepo.getAll(),
        _stockRepo.getDetailedHistory(type: StockMovementType.adjust, limit: 8),
      ]);

      if (!mounted) return;

      setState(() {
        _permissions = results[0] as UserPermissions;
        _isAdmin = results[1] as bool;
        _allProducts = results[2] as List<ProductModel>;
        _lowStockProducts = results[3] as List<ProductModel>;
        _outOfStockProducts = results[4] as List<ProductModel>;
        _categories = results[5] as List<CategoryModel>;
        _recentAdjustments = results[6] as List<StockMovementDetail>;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<ProductModel> get _attentionProducts {
    final ids = <int>{};
    final merged = <ProductModel>[];

    for (final product in [..._outOfStockProducts, ..._lowStockProducts]) {
      final id = product.id;
      if (id == null || ids.add(id)) {
        merged.add(product);
      }
    }

    return merged;
  }

  List<ProductModel> get _baseFiltered {
    final List<ProductModel> items = switch (_filter) {
      _StockFilter.attention => _attentionProducts,
      _StockFilter.lowStock => _lowStockProducts,
      _StockFilter.outOfStock => _outOfStockProducts,
      _StockFilter.available => _allProducts.where((product) {
        return product.isActive &&
            !product.isOutOfStock &&
            !product.hasLowStock;
      }).toList(),
      _StockFilter.highStock => _allProducts.where((product) {
        final min = product.stockMin <= 0 ? 1 : product.stockMin;
        return product.isActive &&
            !product.isOutOfStock &&
            !product.hasLowStock &&
            product.stock >= min * 2;
      }).toList(),
      _StockFilter.all => _allProducts.where((p) => p.isActive).toList(),
    };

    if (_selectedCategoryId == null) return items;

    return items.where((p) => p.categoryId == _selectedCategoryId).toList();
  }

  List<ProductModel> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    final items = _baseFiltered;

    if (query.isEmpty) return items;

    return items.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);
    }).toList();
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

    switch (_adjustmentMode) {
      case StockMovementType.input:
        return product.stock + quantity;
      case StockMovementType.output:
        return product.stock - quantity;
      case StockMovementType.adjust:
        return quantity;
    }
  }

  Future<void> _openAdjustDialog(ProductModel product) async {
    final fresh = await _productsRepo.getById(product.id!);

    if (!mounted || fresh == null) return;

    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockAdjustDialog(product: fresh),
    );

    if (!mounted) return;

    if (result == true || (result is Map && result['ok'] == true)) {
      await _loadData();
    }
  }

  void _showProductDetails(ProductModel product) {
    final showPurchasePrice = _isAdmin || _permissions.canViewPurchasePrice;
    final showProfit = _isAdmin || _permissions.canViewProfit;

    showDialog(
      context: context,
      builder: (context) => ProductDetailsDialog(
        product: product,
        showPurchasePrice: showPurchasePrice,
        showProfit: showProfit,
      ),
    );
  }

  String _statusLabel(ProductModel product) {
    if (product.isOutOfStock) return 'Agotado';
    if (product.hasLowStock) return 'Stock bajo';
    return 'Disponible';
  }

  Color _statusColor(ProductModel product, ColorScheme scheme) {
    if (product.isOutOfStock) return scheme.error;
    if (product.hasLowStock) return const Color(0xFFF59E0B);
    return scheme.primary;
  }

  Future<void> _saveQuickAdjustment() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) {
      return;
    }

    final product = _selectedProduct!;
    final quantity = _parsedQuantity()!;

    if (_adjustmentMode == StockMovementType.output &&
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

    setState(() => _isSaving = true);

    try {
      await _stockRepo.adjustStock(
        productId: product.id!,
        type: _adjustmentMode,
        quantity: quantity,
        note: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        userId: 1,
      );

      _quantityController.clear();
      _notesController.clear();

      await _loadData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock ajustado correctamente')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al ajustar stock: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 1100;
    final products = _filteredProducts;
    final canAdjustStock = _isAdmin || _permissions.canAdjustStock;
    final previewStock = _previewNewStock();

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          const maxContentWidth = 1100.0;

          final hasBoundedHeight = constraints.hasBoundedHeight;
          final cardWidth = math.min(constraints.maxWidth, maxContentWidth);
          final horizontalMargin = ((constraints.maxWidth - cardWidth) / 2)
              .clamp(12.0, 44.0);

          final content = Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalMargin,
              16,
              horizontalMargin,
              16,
            ),
            child: Center(
              child: SizedBox(
                width: maxContentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFixedTopPanel(
                      theme: theme,
                      scheme: scheme,
                      productsCount: products.length,
                      previewStock: previewStock,
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _showProducts
                            ? _buildProductsTable(
                                key: const ValueKey('products-table'),
                                theme: theme,
                                scheme: scheme,
                                products: products,
                                canAdjustStock: canAdjustStock,
                                isCompact: isCompact,
                              )
                            : _buildRecentAdjustments(
                                key: const ValueKey('recent-adjustments'),
                                theme: theme,
                                scheme: scheme,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          if (!hasBoundedHeight) {
            return SingleChildScrollView(
              child: SizedBox(height: 900, child: content),
            );
          }

          return SizedBox(height: constraints.maxHeight, child: content);
        },
      ),
    );
  }

  Widget _buildFixedTopPanel({
    required ThemeData theme,
    required ColorScheme scheme,
    required int productsCount,
    required double? previewStock,
  }) {
    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopTitle(theme, scheme, productsCount),
          const SizedBox(height: 18),
          _buildSearchAndFilters(theme, scheme),
          const SizedBox(height: 18),
          _buildQuickStockForm(theme, scheme, previewStock),
        ],
      ),
    );
  }

  Widget _buildTopTitle(
    ThemeData theme,
    ColorScheme scheme,
    int productsCount,
  ) {
    return Row(
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
                'Ajuste de stock',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  letterSpacing: -0.8,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Agrega, descuenta o fija inventario desde una zona rápida, limpia y precisa.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'Inter',
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.55),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$productsCount productos',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () {
                setState(() => _showProducts = !_showProducts);
              },
              icon: Icon(
                _showProducts
                    ? Icons.visibility_off_outlined
                    : Icons.table_rows_rounded,
                size: 18,
              ),
              label: Text(
                _showProducts ? 'Ocultar productos' : 'Ver productos',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 7,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onSubmitted: _selectProductFromInput,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o código...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(
                        color: scheme.primary.withOpacity(0.75),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<int?>(
                  value: _selectedCategoryId,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Categoría',
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(
                        color: scheme.primary.withOpacity(0.75),
                      ),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Todas las categorías'),
                    ),
                    ..._categories.map(
                      (category) => DropdownMenuItem<int?>(
                        value: category.id,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedCategoryId = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Disponibilidad',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _StockFilter.values.map((filter) {
                    return _buildFilterChip(
                      theme: theme,
                      scheme: scheme,
                      filter: filter,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required ThemeData theme,
    required ColorScheme scheme,
    required _StockFilter filter,
  }) {
    final selected = _filter == filter;

    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(
        filter.icon,
        size: 15,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      label: Text(filter.label),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: scheme.primary.withOpacity(0.11),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected
            ? scheme.primary.withOpacity(0.35)
            : const Color(0xFFE2E8F0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (_) {
        setState(() => _filter = filter);
      },
    );
  }

  Widget _buildQuickStockForm(
    ThemeData theme,
    ColorScheme scheme,
    double? previewStock,
  ) {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _sectionBadge(
                  scheme: scheme,
                  icon: Icons.tune_rounded,
                  label: 'Agregar stock',
                ),
                const Spacer(),
                if (_selectedProduct != null)
                  _selectedProductBadge(theme, scheme),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 190,
                  child: TextFormField(
                    controller: _codeController,
                    focusNode: _codeFocusNode,
                    onFieldSubmitted: _selectProductFromInput,
                    decoration: _fieldDecoration(
                      scheme: scheme,
                      label: 'Código',
                      hint: 'Código + Enter',
                      icon: Icons.qr_code_scanner_rounded,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9\-_\.]'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    value: _selectedProduct?.id,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    decoration: _fieldDecoration(
                      scheme: scheme,
                      label: 'Producto',
                      hint: 'Seleccionar producto',
                      icon: Icons.inventory_2_outlined,
                    ),
                    items: _allProducts
                        .where((p) => p.isActive && p.id != null)
                        .map(
                          (product) => DropdownMenuItem<int>(
                            value: product.id,
                            child: Text(
                              '${product.name} • ${product.code}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;

                            setState(() {
                              _selectedProduct = _allProducts.firstWhere(
                                (product) => product.id == value,
                              );
                              _codeController.text = _selectedProduct!.code;
                              _codeController.selection =
                                  TextSelection.collapsed(
                                    offset: _codeController.text.length,
                                  );
                            });
                          },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<StockMovementType>(
                    value: _adjustmentMode,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    decoration: _fieldDecoration(
                      scheme: scheme,
                      label: 'Tipo',
                      hint: 'Tipo',
                      icon: Icons.swap_vert_rounded,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: StockMovementType.input,
                        child: Text('Incrementar'),
                      ),
                      DropdownMenuItem(
                        value: StockMovementType.output,
                        child: Text('Disminuir'),
                      ),
                      DropdownMenuItem(
                        value: StockMovementType.adjust,
                        child: Text('Fijar exacto'),
                      ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _adjustmentMode = value);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: _quantityController,
                    focusNode: _quantityFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      scheme: scheme,
                      label: _adjustmentMode == StockMovementType.adjust
                          ? 'Stock final'
                          : 'Cantidad',
                      hint: '0',
                      icon: Icons.add_chart_rounded,
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(
                        value?.trim().replaceAll(',', '.') ?? '',
                      );

                      if (parsed == null) return 'Cantidad inválida';
                      if (parsed <= 0) return 'Debe ser mayor a 0';

                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) {
                      if (_selectedProduct != null) {
                        _saveQuickAdjustment();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _notesController,
                    minLines: 1,
                    maxLines: 1,
                    decoration: _fieldDecoration(
                      scheme: scheme,
                      label: 'Nota',
                      hint: 'Motivo del ajuste (opcional)',
                      icon: Icons.notes_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed:
                        (_isLoading || _isSaving || _selectedProduct == null)
                        ? null
                        : _saveQuickAdjustment,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: previewStock == null || _selectedProduct == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: const ValueKey('preview'),
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildPreviewStock(theme, scheme, previewStock),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required ColorScheme scheme,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 19),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(
          color: scheme.primary.withOpacity(0.8),
          width: 1.2,
        ),
      ),
    );
  }

  Widget _sectionBadge({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _selectedProductBadge(ThemeData theme, ColorScheme scheme) {
    final product = _selectedProduct!;

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_rounded, size: 15, color: scheme.primary),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${product.name} · Stock ${_numberFormat.format(product.stock)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStock(
    ThemeData theme,
    ColorScheme scheme,
    double previewStock,
  ) {
    final product = _selectedProduct!;
    final isRisk = previewStock < product.stockMin;
    final color = isRisk ? scheme.error : const Color(0xFF16A34A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Icon(
            isRisk
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: 'Stock actual: ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: _numberFormat.format(product.stock),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const TextSpan(text: '  →  '),
                  TextSpan(
                    text: 'Nuevo stock: ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: _numberFormat.format(previewStock),
                    style: TextStyle(fontWeight: FontWeight.w900, color: color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(
    String label, {
    int flex = 1,
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          label,
          textAlign: align,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF64748B),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildProductsTable({
    required Key key,
    required ThemeData theme,
    required ColorScheme scheme,
    required List<ProductModel> products,
    required bool canAdjustStock,
    required bool isCompact,
  }) {
    return ProductsSurface(
      key: key,
      padding: EdgeInsets.zero,
      radius: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withOpacity(0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.table_rows_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Productos',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter',
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${products.length} resultados',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withOpacity(0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  _headerCell('Producto', flex: 3),
                  _headerCell('Código', flex: 2),
                  _headerCell('Stock', flex: 1, align: TextAlign.right),
                  _headerCell('Mínimo', flex: 1, align: TextAlign.right),
                  _headerCell('Estado', flex: 2),
                  SizedBox(
                    width: isCompact ? 80 : 96,
                    child: const Text(
                      'Acción',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : products.isEmpty
                  ? _buildEmptyProductsState(theme, scheme)
                  : ListView.builder(
                      itemCount: products.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (context, index) {
                        return _buildProductRow(
                          theme: theme,
                          scheme: scheme,
                          product: products[index],
                          canAdjustStock: canAdjustStock,
                          isCompact: isCompact,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyProductsState(ThemeData theme, ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: scheme.onSurface.withOpacity(0.30),
          ),
          const SizedBox(height: 12),
          Text(
            'No se encontraron productos',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cambia la búsqueda, categoría o disponibilidad.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow({
    required ThemeData theme,
    required ColorScheme scheme,
    required ProductModel product,
    required bool canAdjustStock,
    required bool isCompact,
  }) {
    final color = _statusColor(product, scheme);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _showProductDetails(product),
        hoverColor: scheme.primary.withOpacity(0.035),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: ProductThumbnail.fromProduct(
                  product,
                  width: 36,
                  height: 36,
                  borderRadius: BorderRadius.circular(10),
                  showBorder: false,
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    product.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    product.stock.toStringAsFixed(0),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.8,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    product.stockMin.toStringAsFixed(0),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.8,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 128,
                        maxWidth: 180,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(product),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: isCompact ? 80 : 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: canAdjustStock
                        ? () => _openAdjustDialog(product)
                        : null,
                    tooltip: 'Ajustar stock',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: canAdjustStock
                          ? scheme.primary
                          : scheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentAdjustments({
    required Key key,
    required ThemeData theme,
    required ColorScheme scheme,
  }) {
    return ProductsSurface(
      key: key,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Ajustes recientes',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                ),
              ),
              const Spacer(),
              Text(
                'Últimos 8 movimientos',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recentAdjustments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 42,
                          color: scheme.onSurface.withOpacity(0.28),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Sin ajustes recientes',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _showProducts = true);
                          },
                          icon: const Icon(Icons.table_rows_rounded),
                          label: const Text('Ver productos'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 14),
                    itemCount: _recentAdjustments.length,
                    itemBuilder: (context, index) {
                      return _buildRecentAdjustmentRow(
                        theme: theme,
                        scheme: scheme,
                        detail: _recentAdjustments[index],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAdjustmentRow({
    required ThemeData theme,
    required ColorScheme scheme,
    required StockMovementDetail detail,
  }) {
    final movement = detail.movement;
    final isInput = movement.isInput;
    final isOutput = movement.isOutput;

    final icon = isInput
        ? Icons.add_circle_outline
        : isOutput
        ? Icons.remove_circle_outline
        : Icons.tune_rounded;

    final iconColor = isInput
        ? const Color(0xFF16A34A)
        : isOutput
        ? scheme.error
        : const Color(0xFFF59E0B);

    final sign = isInput
        ? '+'
        : isOutput
        ? '-'
        : '→';

    final qty = movement.quantity.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              detail.productLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              detail.productCode ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '$sign $qty',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            DateFormat('dd/MM/yy HH:mm').format(movement.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
