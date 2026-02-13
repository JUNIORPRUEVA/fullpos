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
import '../dialogs/product_details_dialog.dart';
import '../widgets/kpi_card.dart';
import '../widgets/compact_product_card.dart';
import '../widgets/product_thumbnail.dart';

/// Tab de Inventario con KPIs y alertas
class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final ProductsRepository _productsRepo = ProductsRepository();
  final StockRepository _stockRepo = StockRepository();

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

  ProductModel? _selectedProduct;
  bool _isSelectingProduct = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _loadPermissions();
      await _loadInventoryData();
    });
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
                      final canDock =
                          MediaQuery.sizeOf(this.context).width >= 1150;
                      if (canDock) {
                        setState(() => _selectedProduct = product);
                      } else {
                        _showProductDetails(product);
                      }
                    },
                    onAddStockTap: canAdjustStock
                        ? () async {
                            Navigator.pop(context);
                            final result = await context.push(
                              '/products/add-stock/${product.id}',
                            );
                            // Si retorna true, recargar datos
                            if (result == true && mounted) {
                              await _loadInventoryData();
                            }
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
                      final canDock =
                          MediaQuery.sizeOf(this.context).width >= 1150;
                      if (canDock) {
                        setState(() => _selectedProduct = product);
                      } else {
                        _showProductDetails(product);
                      }
                    },
                    onAddStockTap: canAdjustStock
                        ? () async {
                            Navigator.pop(context);
                            final result = await context.push(
                              '/products/add-stock/${product.id}',
                            );
                            // Si retorna true, recargar datos
                            if (result == true && mounted) {
                              await _loadInventoryData();
                            }
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

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2).clamp(12.0, 40.0);
    return EdgeInsets.fromLTRB(side, 16, side, 16);
  }

  Widget _buildMovementTile(
    StockMovementDetail detail,
    NumberFormat numberFormat,
    DateFormat dateFormat,
    bool dockDetails,
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
          if (dockDetails) {
            await _selectProductById(id);
            return;
          }

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

  Future<void> _selectProductById(int productId) async {
    if (_isSelectingProduct) return;
    if (!mounted) return;

    setState(() => _isSelectingProduct = true);
    try {
      final product = await _productsRepo.getById(productId);
      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cargar el producto.')),
        );
        return;
      }
      setState(() => _selectedProduct = product);
    } finally {
      if (mounted) setState(() => _isSelectingProduct = false);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.7);
    final currencyFormat = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: 2,
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
        const sidePanelWidth = 420.0;
        const sideGap = 12.0;

        final canDockDetails = constraints.maxWidth >= 1150;
        final showDockPanel = canDockDetails;
        final mainWidth = showDockPanel
            ? (constraints.maxWidth - sidePanelWidth - sideGap)
            : constraints.maxWidth;
        final mainConstraints = BoxConstraints(maxWidth: mainWidth);

        final padding = _contentPadding(mainConstraints);
        final isWide = mainWidth >= 1100;

        // Tarjetas KPI: mantenerlas estrechas y elegantes en pantallas anchas.
        // A mayor ancho disponible, aumentamos columnas para evitar KPIs gigantes.
        const kpiTargetWidth = 240.0;
        const kpiSpacing = 8.0;
        final computedColumns =
          ((mainWidth + kpiSpacing) / (kpiTargetWidth + kpiSpacing))
                .floor();
        final kpiCrossAxisCount = computedColumns < 2
            ? 2
            : (computedColumns > 6 ? 6 : computedColumns);
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
                      // KPIs Principales
                      Row(
                        children: [
                          Text(
                            'Métricas de Inventario',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Panel de Control',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: mutedText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: kpiCrossAxisCount,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: kpiSpacing,
                        mainAxisSpacing: kpiSpacing,
                        // Más compacto (alto menor) para un look más profesional.
                        childAspectRatio: 2.5,
                        children: kpis,
                      ),
                      const SizedBox(height: 20),

                      // Desglose por categoria y suplidor
                      Row(
                        children: [
                          Text(
                            'Inventario por categoría',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'por suplidor',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: mutedText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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

                      // Alertas
                      Row(
                        children: [
                          Text(
                            'Alertas de Inventario',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
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
                              ' alertas',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
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
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Text(
                            'Historial Reciente',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
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
                                ' mov.',
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
                                  showDockPanel,
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),

        if (!showDockPanel) return mainContent;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: mainContent),
            const SizedBox(width: sideGap),
            SizedBox(
              width: sidePanelWidth,
              child: _buildDockedProductDetailsPanel(
                showPurchasePrice: showPurchasePrice,
                showProfit: showProfit,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDockedProductDetailsPanel({
    required bool showPurchasePrice,
    required bool showProfit,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.65);
    final product = _selectedProduct;
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final numberFormat = NumberFormat.decimalPattern();

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
              Icon(Icons.info_outline, size: 18, color: mutedText),
              const SizedBox(width: 8),
              Text(
                'Detalle del producto',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_selectedProduct != null)
                IconButton(
                  tooltip: 'Limpiar selección',
                  onPressed: () => setState(() => _selectedProduct = null),
                  icon: Icon(Icons.close, size: 18, color: mutedText),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isSelectingProduct
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Cargando producto...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: mutedText,
                          ),
                        ),
                      ],
                    ),
                  )
                : (product == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 44,
                              color: scheme.onSurface.withOpacity(0.35),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Seleccione un producto',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Toque un movimiento del historial o un producto de alertas para ver sus detalles aquí.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedText,
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    product.code,
                                    style: TextStyle(
                                      color: scheme.onPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    product.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (product.isDeleted)
                                  _buildBadge('ELIMINADO', scheme.error),
                                if (!product.isActive && !product.isDeleted)
                                  _buildBadge('INACTIVO', scheme.outline),
                                if (product.isOutOfStock && product.isActive)
                                  _buildBadge('AGOTADO', scheme.error),
                                if (product.hasLowStock && product.isActive)
                                  _buildBadge('STOCK BAJO', scheme.tertiary),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 150,
                              width: double.infinity,
                              child: ProductThumbnail.fromProduct(
                                product,
                                width: double.infinity,
                                height: 150,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildDockInfoRow(
                              icon: Icons.inventory_2_outlined,
                              label: 'Stock',
                              value: numberFormat.format(product.stock),
                              valueColor: product.isOutOfStock
                                  ? scheme.error
                                  : (product.hasLowStock
                                      ? scheme.tertiary
                                      : scheme.onSurface),
                            ),
                            _buildDockInfoRow(
                              icon: Icons.warning_amber,
                              label: 'Stock mínimo',
                              value: numberFormat.format(product.stockMin),
                              valueColor: scheme.tertiary,
                            ),
                            _buildDockInfoRow(
                              icon: Icons.sell,
                              label: 'Precio venta',
                              value: currencyFormat.format(product.salePrice),
                              valueColor: scheme.tertiary,
                            ),
                            if (showPurchasePrice)
                              _buildDockInfoRow(
                                icon: Icons.shopping_cart_outlined,
                                label: 'Precio compra',
                                value: currencyFormat.format(product.purchasePrice),
                                valueColor: scheme.primary,
                              ),
                            if (showProfit)
                              _buildDockInfoRow(
                                icon: Icons.trending_up,
                                label: 'Ganancia unitaria',
                                value: currencyFormat.format(product.profit),
                                valueColor: product.profit > 0
                                    ? scheme.tertiary
                                    : scheme.error,
                              ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _showProductDetails(product),
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Abrir diálogo completo'),
                              ),
                            ),
                          ],
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildDockInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.65);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: mutedText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
        ],
      ),
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
