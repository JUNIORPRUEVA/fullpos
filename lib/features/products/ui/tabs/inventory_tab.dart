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
  const InventoryTab({super.key, required this.onBackToCatalog});

  final VoidCallback onBackToCatalog;

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
  double _totalInventoryValue = 0;
  double _totalPotentialRevenue = 0;
  double _totalPotentialProfit = 0;
  double _totalUnits = 0;
  int _productCount = 0;
  StockSummary? _stockSummary;
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  List<ProductModel> _lowStockProducts = [];
  List<ProductModel> _outOfStockProducts = [];
  List<StockMovementDetail> _recentMovements = [];
  List<Map<String, dynamic>> _inventoryByCategory = [];
  List<Map<String, dynamic>> _inventoryBySupplier = [];

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
        _productsRepo.calculateTotalInventoryValue(),
        _productsRepo.calculateTotalPotentialRevenue(),
        _productsRepo.calculateTotalPotentialProfit(),
        _productsRepo.getLowStock(),
        _productsRepo.getOutOfStock(),
        _productsRepo.calculateTotalUnits(),
        _productsRepo.countActive(),
        _stockRepo.summarize(),
        _stockRepo.getDetailedHistory(limit: 15),
        _productsRepo.getInventoryByCategory(),
        _productsRepo.getInventoryBySupplier(),
      ]);

      _totalInventoryValue = results[0] as double;
      _totalPotentialRevenue = results[1] as double;
      _totalPotentialProfit = results[2] as double;
      _lowStockProducts = results[3] as List<ProductModel>;
      _outOfStockProducts = results[4] as List<ProductModel>;
      _totalUnits = results[5] as double;
      _productCount = results[6] as int;
      _stockSummary = results[7] as StockSummary;
      _recentMovements = results[8] as List<StockMovementDetail>;
      _inventoryByCategory = results[9] as List<Map<String, dynamic>>;
      _inventoryBySupplier = results[10] as List<Map<String, dynamic>>;
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
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2).clamp(12.0, 40.0);
    return EdgeInsets.fromLTRB(side, 12, side, 14);
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    Widget? trailing,
    bool stackOnCompact = true,
  }) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 860;
    final titleWidget = Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        fontFamily: 'Inter',
        color: AppColors.textPrimary,
      ),
    );

    if (trailing == null) {
      return titleWidget;
    }

    if (compact && stackOnCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titleWidget, const SizedBox(height: 10), trailing],
      );
    }

    return Row(
      children: [
        Expanded(child: titleWidget),
        const SizedBox(width: 12),
        trailing,
      ],
    );
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
      symbol: '\$',
      decimalDigits: 0,
    );
    final unitsFormat = NumberFormat.decimalPattern();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final showPurchasePrice = _isAdmin || _permissions.canViewPurchasePrice;
    final showProfit = _isAdmin || _permissions.canViewProfit;
    final stockSummary = _stockSummary;

    final kpis = <Widget>[
      KpiCard(
        title: 'Inversión Total',
        value: showPurchasePrice
            ? currencyFormat.format(_totalInventoryValue)
            : 'Oculto',
        icon: Icons.account_balance_wallet,
        color: Colors.blue,
      ),
      KpiCard(
        title: 'Valor de Venta',
        value: currencyFormat.format(_totalPotentialRevenue),
        icon: Icons.attach_money,
        color: Colors.green,
      ),
      KpiCard(
        title: 'Ganancia Potencial',
        value: showProfit
            ? currencyFormat.format(_totalPotentialProfit)
            : 'Oculto',
        icon: Icons.trending_up,
        color: Colors.purple,
      ),
      KpiCard(
        title: 'Margen Promedio',
        value: (showProfit && showPurchasePrice)
            ? (_totalInventoryValue > 0
                  ? '${((_totalPotentialProfit / _totalInventoryValue) * 100).toStringAsFixed(1)}%'
                  : '0%')
            : 'Oculto',
        icon: Icons.percent,
        color: Colors.teal,
      ),
      KpiCard(
        title: 'Unidades en Stock',
        value: unitsFormat.format(_totalUnits),
        icon: Icons.inventory_2_outlined,
        color: Colors.indigo,
      ),
      KpiCard(
        title: 'Productos Activos',
        value: _productCount.toString(),
        icon: Icons.checklist_rtl,
        color: Colors.cyan,
      ),
      if (stockSummary != null) ...[
        KpiCard(
          title: 'Entradas registradas',
          value: unitsFormat.format(
            stockSummary.totalInputs +
                (stockSummary.totalAdjustments > 0
                    ? stockSummary.totalAdjustments
                    : 0),
          ),
          icon: Icons.call_made,
          color: Colors.green,
        ),
        KpiCard(
          title: 'Salidas registradas',
          value: unitsFormat.format(stockSummary.totalOutputs),
          icon: Icons.call_received,
          color: Colors.red,
        ),
        KpiCard(
          title: 'Ajustes netos',
          value: stockSummary.totalAdjustments >= 0
              ? '+${unitsFormat.format(stockSummary.totalAdjustments)}'
              : unitsFormat.format(stockSummary.totalAdjustments),
          icon: Icons.tune,
          color: stockSummary.totalAdjustments >= 0
              ? Colors.orange
              : Colors.deepOrange,
        ),
      ],
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

        const kpiTargetWidth = 236.0;
        const kpiSpacing = 6.0;
        final computedColumns =
            ((usableWidth + kpiSpacing) / (kpiTargetWidth + kpiSpacing))
                .floor()
                .clamp(1, 5);
        final kpiCrossAxisCount = computedColumns;
        final kpiAspectRatio = usableWidth >= 1400
            ? 2.6
            : (usableWidth >= 1100 ? 2.3 : (usableWidth >= 780 ? 2.08 : 1.9));

        final compactAlerts = usableWidth < 780;
        final sectionPadding = EdgeInsets.all(usableWidth < 760 ? 12 : 14);
        final historyButton = FilledButton.tonalIcon(
          onPressed: _openHistory,
          icon: const Icon(Icons.history),
          label: const Text('Historial'),
          style: FilledButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
            backgroundColor: AppColors.lightBlueHover,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        return RefreshIndicator(
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
                        padding: sectionPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: widget.onBackToCatalog,
                                  icon: const Icon(
                                    Icons.arrow_back_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Catálogo'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryBlue,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                historyButton,
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ProductsStatChip(
                                  label: 'Productos activos',
                                  value: _productCount.toString(),
                                  icon: Icons.inventory_2_outlined,
                                ),
                                ProductsStatChip(
                                  label: 'Alertas stock bajo',
                                  value: _lowStockCount.toString(),
                                  icon: Icons.warning_amber_outlined,
                                  color: const Color(0xFFF59E0B),
                                ),
                                ProductsStatChip(
                                  label: 'Agotados',
                                  value: _outOfStockCount.toString(),
                                  icon: Icons.error_outline,
                                  color: scheme.error,
                                ),
                                ProductsStatChip(
                                  label: 'Movimientos recientes',
                                  value: _recentMovements.length.toString(),
                                  icon: Icons.swap_horiz_outlined,
                                  color: scheme.tertiary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ProductsSurface(
                        padding: sectionPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(context, title: 'Resumen'),
                            const SizedBox(height: 10),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: kpis.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: kpiCrossAxisCount,
                                    crossAxisSpacing: kpiSpacing,
                                    mainAxisSpacing: kpiSpacing,
                                    childAspectRatio: kpiAspectRatio,
                                  ),
                              itemBuilder: (context, index) => kpis[index],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ProductsSurface(
                        padding: sectionPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(context, title: 'Distribución'),
                            const SizedBox(height: 10),
                            isWide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                      const SizedBox(height: 10),
                                      _buildBreakdownPanel(
                                        title: 'Suplidores',
                                        items: _inventoryBySupplier,
                                        money: currencyFormat,
                                        accent: scheme.tertiary,
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ProductsSurface(
                        padding: sectionPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              title: 'Alertas',
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${_lowStockCount + _outOfStockCount} alertas',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.error,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            compactAlerts
                                ? Column(
                                    children: [
                                      KpiCard(
                                        title: 'Stock Bajo',
                                        value: _lowStockCount.toString(),
                                        icon: Icons.warning,
                                        color: const Color(0xFFF59E0B),
                                        onTap: _lowStockCount > 0
                                            ? _showLowStockDetails
                                            : null,
                                      ),
                                      const SizedBox(height: 10),
                                      KpiCard(
                                        title: 'Agotados',
                                        value: _outOfStockCount.toString(),
                                        icon: Icons.error,
                                        color: scheme.error,
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
                                          color: const Color(0xFFF59E0B),
                                          onTap: _lowStockCount > 0
                                              ? _showLowStockDetails
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: KpiCard(
                                          title: 'Agotados',
                                          value: _outOfStockCount.toString(),
                                          icon: Icons.error,
                                          color: scheme.error,
                                          onTap: _outOfStockCount > 0
                                              ? _showOutOfStockDetails
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                            if (_lowStockCount == 0 &&
                                _outOfStockCount == 0) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackgroundAlt,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.borderSoft,
                                  ),
                                ),
                                child: Text(
                                  'Sin alertas',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ProductsSurface(
                        padding: sectionPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              title: 'Movimientos',
                              trailing: stockSummary == null
                                  ? null
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '${stockSummary.movementsCount} movimientos',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: mutedText,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            if (_recentMovements.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackgroundAlt,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.borderSoft,
                                  ),
                                ),
                                child: Text(
                                  'Sin movimientos',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
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
                        ),
                      ),
                    ],
                  ),
                ),
        );
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackgroundAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Text(
          'Sin datos',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSoft),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
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
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderSoft),
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
