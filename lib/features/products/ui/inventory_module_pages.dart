import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/session/session_manager.dart';
import '../data/products_repository.dart';
import '../data/stock_repository.dart';
import '../models/product_model.dart';
import '../models/stock_movement_model.dart';
import 'tabs/catalog_tab.dart';
import 'widgets/products_surface.dart';

class ProductsServicesPage extends StatelessWidget {
  const ProductsServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CatalogTab();
  }
}

enum _InventoryAdjustmentMode { increase, decrease, exact }

class StockAdjustmentWorkspacePage extends StatefulWidget {
  const StockAdjustmentWorkspacePage({super.key});

  @override
  State<StockAdjustmentWorkspacePage> createState() =>
      _StockAdjustmentWorkspacePageState();
}

class _StockAdjustmentWorkspacePageState
    extends State<StockAdjustmentWorkspacePage> {
  final ProductsRepository _productsRepository = ProductsRepository();
  final StockRepository _stockRepository = StockRepository();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final NumberFormat _numberFormat = NumberFormat.decimalPattern('en_US');
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  List<ProductModel> _products = [];
  List<StockMovementDetail> _recentAdjustments = [];
  ProductModel? _selectedProduct;
  _InventoryAdjustmentMode _mode = _InventoryAdjustmentMode.increase;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _productsRepository.getAll(),
        _stockRepository.getDetailedHistory(
          type: StockMovementType.adjust,
          limit: 12,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _products = (results[0] as List<ProductModel>)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _recentAdjustments = results[1] as List<StockMovementDetail>;
        _selectedProduct ??= _products.isNotEmpty ? _products.first : null;
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

    setState(() => _saving = true);
    try {
      await _stockRepository.adjustStock(
        productId: product.id!,
        type: movementType,
        quantity: quantity,
        note: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        userId: await SessionManager.userId(),
      );
      _quantityController.clear();
      _notesController.clear();
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajuste guardado correctamente')),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              ProductsSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProductsSectionHeader(
                      title: 'Ajuste de stock',
                      subtitle:
                          'Ajusta cantidades del inventario y deja trazabilidad clara de cada cambio realizado.',
                      eyebrow: 'Inventario',
                    ),
                    const SizedBox(height: 16),
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
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: DropdownButtonFormField<int>(
                          value: selectedProduct?.id,
                          isExpanded: true,
                          items: _products
                              .where((product) => product.id != null)
                              .map(
                                (product) => DropdownMenuItem<int>(
                                  value: product.id,
                                  child: Text(
                                    '${product.name}  ·  ${product.code}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedProduct = _products.firstWhere(
                                      (product) => product.id == value,
                                    );
                                  });
                                },
                          decoration: InputDecoration(
                            labelText: 'Producto a ajustar',
                            prefixIcon: const Icon(Icons.search_rounded),
                            helperText:
                                '${_products.length} productos disponibles',
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest
                                .withOpacity(0.22),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _InventoryMetricCard(
                          title: 'Stock actual',
                          value: selectedProduct == null
                              ? 'Selecciona un producto'
                              : _numberFormat.format(selectedProduct.stock),
                          icon: Icons.inventory_2_outlined,
                          color: scheme.primary,
                        ),
                        _InventoryMetricCard(
                          title: 'Código',
                          value: selectedProduct?.code ?? 'Sin selección',
                          icon: Icons.qr_code_2_rounded,
                          color: scheme.secondary,
                        ),
                        _InventoryMetricCard(
                          title: 'Nuevo stock',
                          value: previewStock == null
                              ? 'Pendiente'
                              : _numberFormat.format(previewStock),
                          icon: Icons.swap_horiz_rounded,
                          color: scheme.tertiary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Form(
                      key: _formKey,
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          SizedBox(
                            width: 320,
                            child:
                                DropdownButtonFormField<
                                  _InventoryAdjustmentMode
                                >(
                                  value: _mode,
                                  onChanged: _saving
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          setState(() => _mode = value);
                                        },
                                  decoration: InputDecoration(
                                    labelText: 'Tipo de ajuste',
                                    filled: true,
                                    fillColor: scheme.surfaceContainerHighest
                                        .withOpacity(0.22),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: _InventoryAdjustmentMode.increase,
                                      child: Text('Incrementar stock'),
                                    ),
                                    DropdownMenuItem(
                                      value: _InventoryAdjustmentMode.decrease,
                                      child: Text('Disminuir stock'),
                                    ),
                                    DropdownMenuItem(
                                      value: _InventoryAdjustmentMode.exact,
                                      child: Text('Fijar cantidad exacta'),
                                    ),
                                  ],
                                ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: _quantityController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    _mode == _InventoryAdjustmentMode.exact
                                    ? 'Cantidad exacta'
                                    : 'Cantidad',
                                filled: true,
                                fillColor: scheme.surfaceContainerHighest
                                    .withOpacity(0.22),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              validator: (value) {
                                final parsed = double.tryParse(
                                  value?.trim().replaceAll(',', '.') ?? '',
                                );
                                if (parsed == null) {
                                  return 'Ingresa una cantidad válida';
                                }
                                if (parsed <= 0) {
                                  return 'Debe ser mayor que 0';
                                }
                                return null;
                              },
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          SizedBox(
                            width: 420,
                            child: TextFormField(
                              controller: _notesController,
                              minLines: 1,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Razón o notas',
                                hintText:
                                    'Ejemplo: corrección por conteo físico',
                                filled: true,
                                fillColor: scheme.surfaceContainerHighest
                                    .withOpacity(0.22),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed:
                                _loading || _saving || selectedProduct == null
                                ? null
                                : _saveAdjustment,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: const Text('Guardar ajuste'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ProductsSurface(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ajustes recientes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Se muestran los últimos movimientos registrados como ajustes de inventario.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_recentAdjustments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aún no hay ajustes registrados.'),
                      )
                    else
                      ..._recentAdjustments.map(
                        (detail) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: scheme.primary.withOpacity(0.10),
                            foregroundColor: scheme.primary,
                            child: const Icon(Icons.history_rounded, size: 18),
                          ),
                          title: Text(
                            '${detail.productLabel} • ${detail.movement.type.label}',
                          ),
                          subtitle: Text(
                            '${DateFormat('dd/MM/yyyy HH:mm').format(detail.movement.createdAt)} • ${detail.movement.note?.trim().isNotEmpty == true ? detail.movement.note!.trim() : 'Sin nota'}',
                          ),
                          trailing: Text(
                            '${detail.movement.quantity >= 0 ? '+' : ''}${_numberFormat.format(detail.movement.quantity)}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
              ProductsSurface(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
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
                      'Recuento y reporte de inventario',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
                        letterSpacing: -0.8,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Resumen completo del inventario: productos, inversión, ganancia potencial y distribución por categoría y suplidor.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: 'Inter',
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
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

  Widget _buildKpiGrid(ThemeData theme, ColorScheme scheme) {
    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  Icons.dashboard_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Resumen general',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
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
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'Inter',
              color: const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(ThemeData theme, ColorScheme scheme) {
    return ProductsSurface(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  Icons.category_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Inventario por categoría',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_inventoryByCategory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No hay datos de inventario por categoría',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 56,
                columnSpacing: 24,
                headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'Inter',
                ),
                columns: const [
                  DataColumn(label: Text('Categoría')),
                  DataColumn(label: Text('Productos'), numeric: true),
                  DataColumn(label: Text('Unidades'), numeric: true),
                  DataColumn(label: Text('Inversión'), numeric: true),
                  DataColumn(label: Text('Venta potencial'), numeric: true),
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
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(Text(_unitsFormat.format(count))),
                      DataCell(Text(_unitsFormat.format(units))),
                      DataCell(Text(_currencyFormat.format(invValue))),
                      DataCell(Text(_currencyFormat.format(revValue))),
                      DataCell(Text(_currencyFormat.format(profit))),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.tertiary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  size: 18,
                  color: scheme.tertiary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Inventario por suplidor',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_inventoryBySupplier.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No hay datos de inventario por suplidor',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 56,
                columnSpacing: 24,
                headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'Inter',
                ),
                columns: const [
                  DataColumn(label: Text('Suplidor')),
                  DataColumn(label: Text('Productos'), numeric: true),
                  DataColumn(label: Text('Unidades'), numeric: true),
                  DataColumn(label: Text('Inversión'), numeric: true),
                  DataColumn(label: Text('Venta potencial'), numeric: true),
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
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(Text(_unitsFormat.format(count))),
                      DataCell(Text(_unitsFormat.format(units))),
                      DataCell(Text(_currencyFormat.format(invValue))),
                      DataCell(Text(_currencyFormat.format(revValue))),
                      DataCell(Text(_currencyFormat.format(profit))),
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

class _InventoryMetricCard extends StatelessWidget {
  const _InventoryMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
