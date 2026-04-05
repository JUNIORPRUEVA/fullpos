import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/products_repository.dart';
import '../../models/product_model.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../settings/data/user_model.dart';
import '../dialogs/product_details_dialog.dart';
import '../dialogs/stock_adjust_dialog.dart';
import '../widgets/product_thumbnail.dart';
import '../widgets/products_surface.dart';

enum _StockAdjustmentFilter { attention, low, out, all }

class StockAdjustmentsPage extends StatefulWidget {
  const StockAdjustmentsPage({super.key, this.onOpenInventory});

  final VoidCallback? onOpenInventory;

  @override
  State<StockAdjustmentsPage> createState() => _StockAdjustmentsPageState();
}

class _StockAdjustmentsPageState extends State<StockAdjustmentsPage> {
  final ProductsRepository _productsRepo = ProductsRepository();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  bool _isLoading = false;
  bool _isAdmin = false;
  UserPermissions _permissions = UserPermissions.cashier();
  _StockAdjustmentFilter _filter = _StockAdjustmentFilter.attention;
  List<ProductModel> _allProducts = [];
  List<ProductModel> _lowStockProducts = [];
  List<ProductModel> _outOfStockProducts = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _handleSearchSubmit(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty || _isLoading) return;

    final normalized = query.toLowerCase();
    ProductModel? matchedProduct;

    for (final product in _allProducts) {
      if (product.code.toLowerCase() == normalized) {
        matchedProduct = product;
        break;
      }
    }

    if (matchedProduct == null) {
      final searched = await _productsRepo.search(query);
      for (final product in searched) {
        if (product.code.toLowerCase() == normalized) {
          matchedProduct = product;
          break;
        }
      }
    }

    if (!mounted) return;

    if (matchedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró un producto con el código "$query".')),
      );
      return;
    }

    await _openAdjustDialog(matchedProduct);
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
      ]);

      if (!mounted) return;
      setState(() {
        _permissions = results[0] as UserPermissions;
        _isAdmin = results[1] as bool;
        _allProducts = results[2] as List<ProductModel>;
        _lowStockProducts = results[3] as List<ProductModel>;
        _outOfStockProducts = results[4] as List<ProductModel>;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar ajustes de stock: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  List<ProductModel> get _baseProducts {
    switch (_filter) {
      case _StockAdjustmentFilter.attention:
        return _attentionProducts;
      case _StockAdjustmentFilter.low:
        return _lowStockProducts;
      case _StockAdjustmentFilter.out:
        return _outOfStockProducts;
      case _StockAdjustmentFilter.all:
        return _allProducts.where((product) => product.isActive).toList();
    }
  }

  List<ProductModel> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    final items = _baseProducts;
    if (query.isEmpty) return items;

    return items.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);
    }).toList();
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

  String _filterLabel(_StockAdjustmentFilter filter) {
    switch (filter) {
      case _StockAdjustmentFilter.attention:
        return 'Prioridad';
      case _StockAdjustmentFilter.low:
        return 'Stock bajo';
      case _StockAdjustmentFilter.out:
        return 'Agotados';
      case _StockAdjustmentFilter.all:
        return 'Todos';
    }
  }

  Color _statusColor(ProductModel product, ColorScheme scheme) {
    if (product.isOutOfStock) return scheme.error;
    if (product.hasLowStock) return scheme.tertiary;
    return scheme.primary;
  }

  String _statusLabel(ProductModel product) {
    if (product.isOutOfStock) return 'Agotado';
    if (product.hasLowStock) return 'Stock bajo';
    return 'Estable';
  }

  String _filterSummary(_StockAdjustmentFilter filter) {
    switch (filter) {
      case _StockAdjustmentFilter.attention:
        return 'Productos que requieren atención inmediata.';
      case _StockAdjustmentFilter.low:
        return 'Artículos por debajo del mínimo configurado.';
      case _StockAdjustmentFilter.out:
        return 'Productos sin existencia disponibles para venta.';
      case _StockAdjustmentFilter.all:
        return 'Vista completa para revisar y ajustar inventario.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filteredProducts = _filteredProducts;
    final canAdjustStock = _isAdmin || _permissions.canAdjustStock;
    final attentionCount = _attentionProducts.length;
    final lowCount = _lowStockProducts.length;
    final outCount = _outOfStockProducts.length;
    final isCompact = MediaQuery.of(context).size.width < 1100;

    Widget headerCell(
      String label, {
      required int flex,
      TextAlign textAlign = TextAlign.left,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            label,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.25,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        ProductsSurface(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductsSectionHeader(
                eyebrow: 'Control de inventario',
                title: 'Ajustes de stock',
                subtitle: _filterSummary(_filter),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.primary.withOpacity(0.14)),
                  ),
                  child: Text(
                    '${filteredProducts.length} productos',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ProductsStatChip(
                    label: 'Prioridad',
                    value: '$attentionCount',
                    icon: Icons.priority_high_rounded,
                    color: scheme.primary,
                  ),
                  ProductsStatChip(
                    label: 'Stock bajo',
                    value: '$lowCount',
                    icon: Icons.inventory_2_outlined,
                    color: scheme.tertiary,
                  ),
                  ProductsStatChip(
                    label: 'Agotados',
                    value: '$outCount',
                    icon: Icons.error_outline_rounded,
                    color: scheme.error,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.36),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.7),
                  ),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _handleSearchSubmit,
                      decoration: InputDecoration(
                        hintText: 'Buscar producto por nombre o código...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                onPressed: _searchController.clear,
                                icon: const Icon(Icons.close_rounded),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _StockAdjustmentFilter.values
                            .map(
                              (filter) => ChoiceChip(
                                label: Text(_filterLabel(filter)),
                                selected: _filter == filter,
                                onSelected: (_) =>
                                    setState(() => _filter = filter),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ProductsSurface(
            padding: EdgeInsets.zero,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredProducts.isEmpty
                  ? const ProductsEmptyState(
                      icon: Icons.tune_rounded,
                      title: 'Sin productos para ajustar',
                      message:
                          'No hay coincidencias para el filtro actual o no existen alertas de inventario en este momento.',
                    )
                  : Column(
                      children: [
                        Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withOpacity(
                              0.48,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(22),
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: scheme.outlineVariant.withOpacity(0.9),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 56),
                              headerCell('Producto', flex: 24),
                              headerCell('Código', flex: 12),
                              headerCell(
                                'Actual',
                                flex: 10,
                                textAlign: TextAlign.right,
                              ),
                              headerCell(
                                'Mínimo',
                                flex: 10,
                                textAlign: TextAlign.right,
                              ),
                              headerCell('Estado', flex: 12),
                              SizedBox(
                                width: isCompact ? 96 : 120,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    'Acciones',
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurfaceVariant,
                                      letterSpacing: 0.25,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: filteredProducts.length,
                              itemBuilder: (context, index) {
                                final product = filteredProducts[index];
                                final color = _statusColor(product, scheme);
                                final rowColor = index.isEven
                                    ? scheme.surface.withOpacity(0.72)
                                    : scheme.surface.withOpacity(0.94);

                                return Material(
                                  color: rowColor,
                                  child: InkWell(
                                    onTap: () => _showProductDetails(product),
                                    hoverColor: scheme.primary.withOpacity(0.04),
                                    child: Container(
                                      height: 64,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: scheme.outlineVariant
                                                .withOpacity(0.32),
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 56,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: ProductThumbnail.fromProduct(
                                                product,
                                                width: 40,
                                                height: 40,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                showBorder: false,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 24,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              child: Text(
                                                product.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 12,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              child: Text(
                                                product.code,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 10,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              child: Text(
                                                product.stock.toStringAsFixed(0),
                                                textAlign: TextAlign.right,
                                                style: theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: color,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 10,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              child: Text(
                                                product.stockMin.toStringAsFixed(
                                                  0,
                                                ),
                                                textAlign: TextAlign.right,
                                                style: theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 12,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: color.withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  _statusLabel(product),
                                                  style: theme
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: color,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: isCompact ? 96 : 120,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: scheme
                                                      .surfaceContainerHighest
                                                      .withOpacity(0.42),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      onPressed: () =>
                                                          _showProductDetails(
                                                            product,
                                                          ),
                                                      tooltip: 'Ver detalle',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      icon: const Icon(
                                                        Icons.visibility_outlined,
                                                        size: 18,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: canAdjustStock
                                                          ? () =>
                                                                _openAdjustDialog(
                                                                  product,
                                                                )
                                                          : null,
                                                      tooltip: 'Ajustar stock',
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      icon: const Icon(
                                                        Icons.tune_rounded,
                                                        size: 18,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
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
      ],
    );
  }
}
