import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/products_repository.dart';
import '../../data/stock_repository.dart';
import '../../models/product_model.dart';
import '../../models/stock_movement_model.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../settings/data/user_model.dart';
import '../../../../core/sync/product_sync_event_bus.dart';
import '../../../../theme/app_colors.dart';
import '../dialogs/product_details_dialog.dart';
import '../dialogs/stock_adjust_dialog.dart';
import '../widgets/kpi_card.dart';
import '../widgets/compact_product_card.dart';
import '../widgets/products_surface.dart';

/// Tab de Inventario con KPIs y alertas
class InventoryTab extends StatefulWidget {
  const InventoryTab({
    super.key,
    required this.onBackToCatalog,
    this.embedded = false,
  });

  final VoidCallback onBackToCatalog;
  final bool embedded;

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final ProductsRepository _productsRepo = ProductsRepository();
  final StockRepository _stockRepo = StockRepository();
  Timer? _syncRefreshDebounce;
  StreamSubscription<ProductSyncChange>? _syncSubscription;

  bool _isLoading = false;
  bool _isAdmin = false;
  UserPermissions _permissions = UserPermissions.cashier();
  StockSummary? _stockSummary;
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  List<ProductModel> _inventoryProducts = [];
  List<ProductModel> _lowStockProducts = [];
  List<ProductModel> _outOfStockProducts = [];
  List<StockMovementDetail> _recentMovements = [];
  List<Map<String, dynamic>> _inventoryByCategory = [];
  List<Map<String, dynamic>> _inventoryBySupplier = [];
  int? _selectedCategoryId;
  bool _showExpandedInventory = false;

  @override
  void initState() {
    super.initState();
    _syncSubscription = ProductSyncEventBus.instance.stream.listen((_) {
      _syncRefreshDebounce?.cancel();
      _syncRefreshDebounce = Timer(
        const Duration(milliseconds: 250),
        _loadInventoryData,
      );
    });
    Future.microtask(() async {
      await _loadPermissions();
      await _loadInventoryData();
    });
  }

  @override
  void dispose() {
    _syncRefreshDebounce?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final permissions = await AuthRepository.getCurrentPermissions();
    final isAdmin = await AuthRepository.isAdmin();
    if (mounted) {
      setState(() {
        _permissions = permissions;
        _isAdmin = isAdmin;
      });
    }
  }

  Future<void> _loadInventoryData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _productsRepo.getAll(filters: const ProductFilters(isActive: true)),
        _productsRepo.getLowStock(),
        _productsRepo.getOutOfStock(),
        _stockRepo.summarize(),
        _stockRepo.getDetailedHistory(limit: 15),
        _productsRepo.getInventoryByCategory(),
        _productsRepo.getInventoryBySupplier(),
      ]);

      _inventoryProducts = results[0] as List<ProductModel>;
      _lowStockProducts = results[1] as List<ProductModel>;
      _outOfStockProducts = results[2] as List<ProductModel>;
      _stockSummary = results[3] as StockSummary;
      _recentMovements = results[4] as List<StockMovementDetail>;
      _inventoryByCategory = results[5] as List<Map<String, dynamic>>;
      _inventoryBySupplier = results[6] as List<Map<String, dynamic>>;
      _lowStockCount = _lowStockProducts.length;
      _outOfStockCount = _outOfStockProducts.length;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar inventario: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLowStockDetails() {
    final showPurchasePrice = _isAdmin || _permissions.canViewPurchasePrice;
    final showProfit = _isAdmin || _permissions.canViewProfit;
    final canAdjustStock = _isAdmin || _permissions.canAdjustStock;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.tertiary.withOpacity(0.12),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: scheme.tertiary, size: 32),
                  const SizedBox(width: 12),
                  const Text(
                    'Productos con Stock Bajo',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _lowStockProducts.length,
                itemBuilder: (context, index) {
                  final product = _lowStockProducts[index];
                  return CompactProductCard(
                    product: product,
                    onTap: () {
                      Navigator.pop(context);
                      _showProductDetails(product);
                    },
                    onAddStockTap: canAdjustStock
                        ? () async {
                            Navigator.pop(context);
                            await _openAdjustStockDialog(product);
                          }
                        : null,
                    showPurchasePrice: showPurchasePrice,
                    showProfit: showProfit,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOutOfStockDetails() {
    final showPurchasePrice = _isAdmin || _permissions.canViewPurchasePrice;
    final showProfit = _isAdmin || _permissions.canViewProfit;
    final canAdjustStock = _isAdmin || _permissions.canAdjustStock;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.error.withOpacity(0.12),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: scheme.error, size: 32),
                  const SizedBox(width: 12),
                  const Text(
                    'Productos Agotados',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _outOfStockProducts.length,
                itemBuilder: (context, index) {
                  final product = _outOfStockProducts[index];
                  return CompactProductCard(
                    product: product,
                    onTap: () {
                      Navigator.pop(context);
                      _showProductDetails(product);
                    },
                    onAddStockTap: canAdjustStock
                        ? () async {
                            Navigator.pop(context);
                            await _openAdjustStockDialog(product);
                          }
                        : null,
                    showPurchasePrice: showPurchasePrice,
                    showProfit: showProfit,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openHistory() {
    context.push('/products/history');
  }

  Future<void> _openAdjustStockDialog(ProductModel product) async {
    final fresh = await _productsRepo.getById(product.id!);
    if (!mounted || fresh == null) return;

    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockAdjustDialog(product: fresh),
    );

    if (!mounted) return;
    if (result is Map && result['ok'] == true) {
      final productId = result['productId'] as int?;
      final updatedStockNum = result['updatedStock'] as num?;
      if (productId != null && updatedStockNum != null) {
        final updatedStock = updatedStockNum.toDouble();
        setState(() {
          _lowStockProducts = _lowStockProducts
              .map(
                (p) => p.id == productId ? p.copyWith(stock: updatedStock) : p,
              )
              .toList();
          _outOfStockProducts = _outOfStockProducts
              .map(
                (p) => p.id == productId ? p.copyWith(stock: updatedStock) : p,
              )
              .toList();
        });
      }
      await _loadInventoryData();
      return;
    }

    if (result == true) {
      await _loadInventoryData();
    }
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    return productsResponsivePagePadding(
      constraints,
      top: widget.embedded ? 8 : 14,
      bottom: 18,
    );
  }

  bool _matchesSelectedCategory(ProductModel product) {
    if (_selectedCategoryId == null) return true;
    if (_selectedCategoryId == -1) return product.categoryId == null;
    return product.categoryId == _selectedCategoryId;
  }

  Widget _buildMovementTile(
    StockMovementDetail detail,
    NumberFormat numberFormat,
    DateFormat dateFormat,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.7);
    final movement = detail.movement;
    final isPositive =
        movement.isInput || (movement.isAdjust && movement.quantity >= 0);
    final color = movement.isInput
        ? scheme.tertiary
        : movement.isOutput
        ? scheme.error
        : (movement.quantity >= 0 ? scheme.primary : scheme.error);
    final qtyValue = numberFormat.format(movement.quantity.abs());
    String qtyLabel;
    if (movement.isAdjust) {
      qtyLabel = movement.quantity >= 0 ? '+$qtyValue' : '-$qtyValue';
    } else if (movement.isInput) {
      qtyLabel = '+$qtyValue';
    } else {
      qtyLabel = '-$qtyValue';
    }

    final dateLabel = dateFormat.format(movement.createdAt.toLocal());
    final codeLabel = detail.productCode?.trim();
    final noteLabel = movement.note?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final id = detail.movement.productId;
          final product = await _productsRepo.getById(id);
          if (!mounted) return;
          if (product == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se pudo cargar el producto.')),
            );
            return;
          }
          _showProductDetails(product);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  movement.isInput
                      ? Icons.call_made
                      : movement.isOutput
                      ? Icons.call_received
                      : Icons.tune,
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        detail.productLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (codeLabel != null && codeLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        'COD $codeLabel',
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      movement.type.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$dateLabel • ${detail.userLabel}',
                        style: TextStyle(color: mutedText, fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (noteLabel != null && noteLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: noteLabel,
                        child: Icon(
                          Icons.note_alt_outlined,
                          size: 14,
                          color: mutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                qtyLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 12,
                ),
              ),
              if (movement.isAdjust)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.analytics_outlined,
                    size: 14,
                    color: isPositive ? scheme.primary : scheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.7);
    final currencyFormat = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );
    final unitsFormat = NumberFormat.decimalPattern();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final showPurchasePrice = _isAdmin || _permissions.canViewPurchasePrice;
    final showProfit = _isAdmin || _permissions.canViewProfit;
    final stockSummary = _stockSummary;
    final filteredInventoryProducts = _inventoryProducts
        .where(_matchesSelectedCategory)
        .toList();
    final filteredLowStockProducts = _lowStockProducts
        .where(_matchesSelectedCategory)
        .toList();
    final filteredOutOfStockProducts = _outOfStockProducts
        .where(_matchesSelectedCategory)
        .toList();
    final categoryFilterOptions = _inventoryByCategory
        .map(
          (item) => (
            id: (item['id'] as num?)?.toInt(),
            name: ((item['name'] as String?) ?? 'Sin categoría').trim(),
          ),
        )
        .toList();
    final filteredInventoryValue = filteredInventoryProducts.fold<double>(
      0,
      (sum, product) => sum + product.inventoryValue,
    );
    final filteredPotentialRevenue = filteredInventoryProducts.fold<double>(
      0,
      (sum, product) => sum + product.potentialRevenue,
    );
    final filteredPotentialProfit = filteredInventoryProducts.fold<double>(
      0,
      (sum, product) => sum + (product.stock * product.profit),
    );
    final filteredUnits = filteredInventoryProducts.fold<double>(
      0,
      (sum, product) => sum + product.stock,
    );
    final filteredProductCount = filteredInventoryProducts.length;
    final filteredAlertCount =
        filteredLowStockProducts.length + filteredOutOfStockProducts.length;
    final filteredAverageMargin = filteredInventoryValue > 0
        ? (filteredPotentialProfit / filteredInventoryValue) * 100
        : 0.0;

    final compactDashboardKpis = <Widget>[
      KpiCard(
        title: 'Inversión Total',
        value: showPurchasePrice
            ? currencyFormat.format(filteredInventoryValue)
            : 'Oculto',
        icon: Icons.account_balance_wallet,
        color: Colors.blue,
      ),
      KpiCard(
        title: 'Valor de Venta',
        value: currencyFormat.format(filteredPotentialRevenue),
        icon: Icons.attach_money,
        color: Colors.green,
      ),
      KpiCard(
        title: 'Ganancia Potencial',
        value: showProfit
            ? currencyFormat.format(filteredPotentialProfit)
            : 'Oculto',
        icon: Icons.trending_up,
        color: Colors.purple,
      ),
      KpiCard(
        title: 'Margen Promedio',
        value: (showProfit && showPurchasePrice)
            ? '${filteredAverageMargin.toStringAsFixed(1)}%'
            : 'Oculto',
        icon: Icons.percent,
        color: Colors.teal,
      ),
      KpiCard(
        title: 'Unidades en Stock',
        value: unitsFormat.format(filteredUnits),
        icon: Icons.inventory_2_outlined,
        color: Colors.indigo,
      ),
      KpiCard(
        title: 'Productos Activos',
        value: filteredProductCount.toString(),
        icon: Icons.checklist_rtl,
        color: Colors.cyan,
      ),
      KpiCard(
        title: 'Alertas activas',
        value: filteredAlertCount.toString(),
        icon: Icons.warning_amber_rounded,
        color: filteredAlertCount > 0 ? Colors.orange : Colors.green,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final mainWidth = constraints.maxWidth;
        final mainConstraints = BoxConstraints(maxWidth: mainWidth);

        final padding = _contentPadding(mainConstraints);
        final usableWidth = math.max(
          0,
          mainWidth - padding.left - padding.right,
        );

        final isWide = usableWidth >= 1100;

        const kpiTargetWidth = 230.0;
        const kpiSpacing = 8.0;
        final computedColumns =
            ((usableWidth + kpiSpacing) / (kpiTargetWidth + kpiSpacing))
                .floor()
                .clamp(1, 5);
        final kpiCardWidth = computedColumns <= 1
            ? usableWidth
            : ((usableWidth - ((computedColumns - 1) * kpiSpacing)) /
                      computedColumns)
                  .clamp(220.0, 320.0);

        final compactAlerts = usableWidth < 780;
        final mainContent = RefreshIndicator(
          onRefresh: _loadInventoryData,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProductsSurface(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withOpacity(0.35),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: scheme.outlineVariant.withOpacity(
                                    0.75,
                                  ),
                                ),
                              ),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    child: DropdownButtonFormField<int?>(
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
                                          child: Text('Todas las categorías'),
                                        ),
                                        ...categoryFilterOptions.map(
                                          (option) => DropdownMenuItem<int?>(
                                            value: option.id,
                                            child: Text(option.name),
                                          ),
                                        ),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedCategoryId = value;
                                        });
                                      },
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: scheme.outlineVariant
                                            .withOpacity(0.7),
                                      ),
                                    ),
                                    child: Text(
                                      '$filteredProductCount visibles',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: scheme.onSurface,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'Inter',
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (filteredProductCount == 0)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 34,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'No hay productos para esta categoría',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'Inter',
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Selecciona otra categoría o usa Todas las categorías para ver el dashboard completo.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Inter',
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Wrap(
                                spacing: kpiSpacing,
                                runSpacing: kpiSpacing,
                                children: compactDashboardKpis
                                    .map(
                                      (kpi) => SizedBox(
                                        width: kpiCardWidth.toDouble(),
                                        child: kpi,
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.center,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _showExpandedInventory = !_showExpandedInventory;
                            });
                          },
                          icon: Icon(
                            _showExpandedInventory
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _showExpandedInventory ? 'Ver menos' : 'Ver más',
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: AppColors.primaryBlue,
                            backgroundColor: AppColors.lightBlueHover,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Inter',
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      if (_showExpandedInventory) ...[
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Text(
                              'Inventario por categoría',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Resumen del valor y las unidades agrupadas por categoría y suplidor.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 12),
                        isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildBreakdownPanel(
                                      title: 'Categorías',
                                      items: _inventoryByCategory,
                                      money: currencyFormat,
                                      accent: scheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildBreakdownPanel(
                                      title: 'Suplidores',
                                      items: _inventoryBySupplier,
                                      money: currencyFormat,
                                      accent: scheme.tertiary,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildBreakdownPanel(
                                    title: 'Categorías',
                                    items: _inventoryByCategory,
                                    money: currencyFormat,
                                    accent: scheme.primary,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildBreakdownPanel(
                                    title: 'Suplidores',
                                    items: _inventoryBySupplier,
                                    money: currencyFormat,
                                    accent: scheme.tertiary,
                                  ),
                                ],
                              ),

                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Text(
                              'Alertas de Inventario',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_lowStockCount + _outOfStockCount} alertas',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        compactAlerts
                            ? Column(
                                children: [
                                  KpiCard(
                                    title: 'Stock Bajo',
                                    value: _lowStockCount.toString(),
                                    icon: Icons.warning,
                                    color: Colors.orange,
                                    onTap: _lowStockCount > 0
                                        ? _showLowStockDetails
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  KpiCard(
                                    title: 'Agotados',
                                    value: _outOfStockCount.toString(),
                                    icon: Icons.error,
                                    color: Colors.red,
                                    onTap: _outOfStockCount > 0
                                        ? _showOutOfStockDetails
                                        : null,
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: KpiCard(
                                      title: 'Stock Bajo',
                                      value: _lowStockCount.toString(),
                                      icon: Icons.warning,
                                      color: Colors.orange,
                                      onTap: _lowStockCount > 0
                                          ? _showLowStockDetails
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: KpiCard(
                                      title: 'Agotados',
                                      value: _outOfStockCount.toString(),
                                      icon: Icons.error,
                                      color: Colors.red,
                                      onTap: _outOfStockCount > 0
                                          ? _showOutOfStockDetails
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                        if (_lowStockCount == 0 && _outOfStockCount == 0) ...[
                          const SizedBox(height: 32),
                          Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 64,
                                  color: scheme.tertiary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '¡Todo bajo control!',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.tertiary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No hay productos con stock bajo o agotados',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Text(
                              'Historial Reciente',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (stockSummary != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_recentMovements.length} mov.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: mutedText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: _openHistory,
                              icon: const Icon(Icons.history),
                              label: const Text('Ver historial completo'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_recentMovements.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 48,
                                  color: scheme.onSurface.withOpacity(0.4),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Sin movimientos recientes',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Cada entrada, salida o ajuste quedará registrado aquí.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        else
                          Column(
                            children: _recentMovements
                                .take(10)
                                .map(
                                  (m) => _buildMovementTile(
                                    m,
                                    unitsFormat,
                                    dateFormat,
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ],
                  ),
                ),
        );

        return mainContent;
      },
    );
  }

  Widget _buildBreakdownPanel({
    required String title,
    required List<Map<String, dynamic>> items,
    required NumberFormat money,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.65);

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          'Sin datos',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, index) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = items[index];
              final name = (item['name'] as String?) ?? 'N/A';
              final totalValue =
                  (item['total_value'] as num?)?.toDouble() ?? 0.0;
              final totalUnits =
                  (item['total_units'] as num?)?.toDouble() ?? 0.0;
              final productCount =
                  (item['product_count'] as num?)?.toInt() ?? 0;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${totalUnits.toStringAsFixed(0)} u',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$productCount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      money.format(totalValue),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
