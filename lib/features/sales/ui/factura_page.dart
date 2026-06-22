import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/notifications/fullpos_notifications.dart';
import '../../../core/theme/app_gradient_theme.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/utils/currency_display.dart';
import '../../../theme/app_colors.dart';
import '../../cash/data/cash_movement_model.dart';
import '../../cash/data/cash_repository.dart';
import '../../cash/ui/cash_movement_dialog.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../data/sales_model.dart';
import '../data/sales_repository.dart';
import '../data/returns_repository.dart';
import '../data/refund_calculator.dart';

/// Filtros de fecha predefinidos
enum DateFilter { all, today, yesterday, thisWeek, thisMonth, custom }

enum _InvoiceStatusFilter { all, active, withRefund, partialRefund, refunded }

String _normalizeElectronicDocumentType(SaleModel sale) {
  final explicitType = (sale.electronicDocumentType ?? '').trim().toUpperCase();
  if (explicitType.isNotEmpty) return explicitType;

  final code = (sale.electronicInvoiceCode ?? '').trim().toUpperCase();
  if (code.startsWith('E31')) return '31';
  if (code.startsWith('E32')) return '32';
  return '';
}

bool _supportsElectronicCreditNote(SaleModel sale) {
  final hasElectronicReference =
      sale.electronicInvoiceEnabled == 1 ||
      (sale.electronicInvoiceCode ?? '').trim().isNotEmpty;
  if (!hasElectronicReference) return false;

  final documentType = _normalizeElectronicDocumentType(sale);
  return documentType == '31' || documentType == '32';
}

enum SaleRefundOutcome { refunded, cancelled }

Future<SaleRefundOutcome?> showSaleRefundDialog(
  BuildContext context,
  SaleModel sale,
) async {
  final saleId = sale.id;
  if (saleId == null) {
    throw StateError('No se puede procesar una factura sin ID.');
  }

  final currentSale = await SalesRepository.getSaleById(saleId);
  if (currentSale == null) {
    throw StateError('La factura ya no está disponible.');
  }
  final status = currentSale.status.trim().toUpperCase();
  if (status == 'CANCELLED' || status == 'REFUNDED') {
    throw StateError('Esta factura ya no admite devoluciones.');
  }

  final items = await SalesRepository.getItemsBySaleId(saleId);
  final returnedQuantities = await ReturnsRepository.returnedQuantitiesForSale(
    saleId,
  );
  if (!context.mounted) return null;

  if (items.isEmpty) {
    throw StateError('La factura no contiene productos para devolver.');
  }
  if (items.any((item) => item.id == null)) {
    throw StateError(
      'No se puede procesar: hay productos de la factura sin ID.',
    );
  }

  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 20));
  if (!context.mounted) return null;

  final result = await showDialog<_RefundDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RefundDialog(
      sale: currentSale,
      items: items,
      returnedQuantities: returnedQuantities,
    ),
  );

  return switch (result) {
    _RefundDialogResult.refunded => SaleRefundOutcome.refunded,
    _RefundDialogResult.cancelled => SaleRefundOutcome.cancelled,
    null => null,
  };
}

/// Pantalla de facturas con devolucion integrada por factura.
class FacturaPage extends StatefulWidget {
  const FacturaPage({super.key, this.initialSaleId, this.openRefund = false});

  final int? initialSaleId;
  final bool openRefund;

  @override
  State<FacturaPage> createState() => _FacturaPageState();
}

class _FacturaPageState extends State<FacturaPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  SaleModel? _selectedSale;
  int? _selectedSaleId;

  List<SaleModel> _completedSales = [];
  List<Map<String, dynamic>> _returns = [];
  Map<int, String> _cashierNameBySessionId = <int, String>{};
  final Map<int, Future<List<SaleItemModel>>> _saleItemsFutureCache =
      <int, Future<List<SaleItemModel>>>{};
  bool _isLoading = false;
  String _searchQuery = '';
  int _loadSeq = 0;
  bool _initialRefundHandled = false;

  // Filtros de fecha
  DateFilter _selectedFilter = DateFilter.thisMonth;
  DateTime? _customDateFrom;
  DateTime? _customDateTo;
  int? _selectedSessionId;
  _InvoiceStatusFilter _statusFilter = _InvoiceStatusFilter.active;

  ColorScheme get scheme => Theme.of(context).colorScheme;
  AppStatusTheme get status =>
      Theme.of(context).extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: scheme.tertiary,
        warning: scheme.tertiary,
        error: scheme.error,
        info: scheme.primary,
      );
  Color readableOn(Color bg) => ColorUtils.readableTextColor(bg);

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedFilter != DateFilter.thisMonth) count++;
    if (_selectedSessionId != null) count++;
    if (_statusFilter != _InvoiceStatusFilter.active) count++;
    return count;
  }

  @override
  void initState() {
    super.initState();
    _selectedSaleId = widget.initialSaleId;
    if (widget.initialSaleId != null) {
      _selectedFilter = DateFilter.all;
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openFiltersPanel() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _clearFilters() {
    _searchController.clear();
    _safeSetState(() {
      _searchQuery = '';
      _selectedFilter = DateFilter.thisMonth;
      _customDateFrom = null;
      _customDateTo = null;
      _selectedSessionId = null;
      _statusFilter = _InvoiceStatusFilter.active;
      _ensureSelection();
    });
    _loadData();
  }

  void _primeSaleItemsCache(SaleModel? sale) {
    final saleId = sale?.id;
    if (saleId == null) return;
    _saleItemsFutureCache.putIfAbsent(
      saleId,
      () => SalesRepository.getItemsBySaleId(saleId),
    );
  }

  Future<List<SaleItemModel>> _loadSaleItemsForSale(SaleModel sale) {
    final saleId = sale.id;
    if (saleId == null) return Future.value(const <SaleItemModel>[]);
    return _saleItemsFutureCache.putIfAbsent(
      saleId,
      () => SalesRepository.getItemsBySaleId(saleId),
    );
  }

  void _updateStatusFilter(_InvoiceStatusFilter value) {
    _safeSetState(() {
      _statusFilter = value;
      _ensureSelection();
    });
  }

  void _updateCashierFilter(int? value) {
    _safeSetState(() {
      _selectedSessionId = value;
      _ensureSelection();
    });
  }

  Future<void> _updateDateFilter(DateFilter value) async {
    if (value == DateFilter.custom) {
      await _selectCustomDateRange();
      return;
    }
    _safeSetState(() => _selectedFilter = value);
    _loadData();
  }

  (DateTime?, DateTime?) _getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedFilter) {
      case DateFilter.all:
        return (null, null);
      case DateFilter.today:
        return (today, now);
      case DateFilter.yesterday:
        final yesterday = today.subtract(const Duration(days: 1));
        return (yesterday, today.subtract(const Duration(milliseconds: 1)));
      case DateFilter.thisWeek:
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        return (startOfWeek, now);
      case DateFilter.thisMonth:
        final from = DateTime(now.year, now.month - 1, 1);
        return (from, now);
      case DateFilter.custom:
        final to = _customDateTo;
        if (to == null) return (_customDateFrom, null);
        return (
          _customDateFrom,
          DateTime(to.year, to.month, to.day, 23, 59, 59, 999),
        );
    }
  }

  Future<Map<int, String>> _loadCashierNames(Iterable<int> sessionIds) async {
    final uniqueIds = sessionIds.toSet().toList()..sort();
    if (uniqueIds.isEmpty) return <int, String>{};

    final entries = await Future.wait(
      uniqueIds.map((sessionId) async {
        final session = await CashRepository.getSessionById(sessionId);
        return MapEntry(sessionId, session?.userName ?? 'Cajero #$sessionId');
      }),
    );

    return <int, String>{for (final entry in entries) entry.key: entry.value};
  }

  bool _matchesCashier(int? sessionId) {
    return _selectedSessionId == null || sessionId == _selectedSessionId;
  }

  String _cashierLabelForSessionId(int? sessionId) {
    if (sessionId == null) return 'Sin cajero';
    return _cashierNameBySessionId[sessionId] ?? 'Cajero #$sessionId';
  }

  List<Map<String, dynamic>> _returnsForSale(SaleModel sale) {
    final saleId = sale.id;
    if (saleId == null) return const [];
    return _returns.where((ret) => ret['original_sale_id'] == saleId).toList()
      ..sort(
        (a, b) => ((b['created_at_ms'] as int?) ?? 0).compareTo(
          (a['created_at_ms'] as int?) ?? 0,
        ),
      );
  }

  double _refundedAmountForSale(SaleModel sale) {
    return _returnsForSale(sale).fold<double>(
      0,
      (sum, ret) => sum + (((ret['total'] as num?)?.toDouble() ?? 0).abs()),
    );
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    _safeSetState(() => _isLoading = true);
    try {
      final (dateFrom, dateTo) = _getDateRange();

      final result = await DbHardening.instance
          .runDbSafe<(List<SaleModel>, List<Map<String, dynamic>>)>(() async {
            final sales = await SalesRepository.listCompletedSales(
              dateFrom: dateFrom,
              dateTo: dateTo,
            );
            final returns = await ReturnsRepository.listReturns(
              dateFrom: dateFrom,
              dateTo: dateTo,
            );
            return (sales, returns);
          }, stage: 'sales/returns_list/load');
      final (sales, returns) = result;
      final cashierNames = await _loadCashierNames([
        ...sales.map((sale) => sale.sessionId).whereType<int>(),
        ...returns.map((ret) => ret['session_id'] as int?).whereType<int>(),
      ]);

      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() {
        _completedSales = sales.where((sale) {
          final normalizedKind = sale.kind.trim().toLowerCase();
          final normalizedStatus = sale.status.trim().toLowerCase();
          return const {'invoice', 'sale'}.contains(normalizedKind) &&
              normalizedStatus != 'cancelled' &&
              normalizedStatus != 'canceled';
        }).toList();
        _returns = returns;
        _cashierNameBySessionId = cashierNames;
        if (_selectedSessionId != null &&
            !_cashierNameBySessionId.containsKey(_selectedSessionId)) {
          _selectedSessionId = null;
        }

        _ensureSelection();
      });
      final selected = _selectedSale;
      if (widget.openRefund &&
          !_initialRefundHandled &&
          selected != null &&
          selected.status.toUpperCase() != 'REFUNDED') {
        _initialRefundHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_showRefundDialog(selected));
        });
      }
    } catch (e, st) {
      if (!mounted || seq != _loadSeq) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadData,
        module: 'sales/returns_list/load',
      );
    } finally {
      if (mounted && seq == _loadSeq) {
        _safeSetState(() => _isLoading = false);
      }
    }
  }

  List<SaleModel> get _filteredSales {
    final query = _searchQuery.toLowerCase();
    return _completedSales.where((sale) {
      if (!_matchesCashier(sale.sessionId)) return false;
      if (!_matchesStatusFilter(sale)) return false;
      if (query.isEmpty) return true;

      return sale.localCode.toLowerCase().contains(query) ||
          (sale.customerNameSnapshot?.toLowerCase().contains(query) ?? false) ||
          sale.total.toString().contains(query) ||
          _cashierLabelForSessionId(
            sale.sessionId,
          ).toLowerCase().contains(query);
    }).toList();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _safeSetState(() {
        _searchQuery = value.trim();
        _ensureSelection();
      });
    });
  }

  bool _matchesStatusFilter(SaleModel sale) {
    final statusValue = sale.status.trim().toUpperCase();
    final hasRefund =
        statusValue == 'PARTIAL_REFUND' || statusValue == 'REFUNDED';

    switch (_statusFilter) {
      case _InvoiceStatusFilter.all:
        return true;
      case _InvoiceStatusFilter.active:
        return !hasRefund;
      case _InvoiceStatusFilter.withRefund:
        return hasRefund;
      case _InvoiceStatusFilter.partialRefund:
        return statusValue == 'PARTIAL_REFUND';
      case _InvoiceStatusFilter.refunded:
        return statusValue == 'REFUNDED';
    }
  }

  String _statusFilterLabel(_InvoiceStatusFilter filter) {
    switch (filter) {
      case _InvoiceStatusFilter.all:
        return 'Todas incl. devueltas';
      case _InvoiceStatusFilter.active:
        return 'Activas';
      case _InvoiceStatusFilter.withRefund:
        return 'Con devolución';
      case _InvoiceStatusFilter.partialRefund:
        return 'Parcial';
      case _InvoiceStatusFilter.refunded:
        return 'Devueltas';
    }
  }

  void _ensureSelection() {
    final list = _filteredSales;
    if (list.isEmpty) {
      _selectedSale = null;
      _selectedSaleId = null;
      return;
    }

    final currentId = _selectedSaleId;
    if (currentId == null) {
      _selectedSale = null;
      return;
    }

    final matchingSales = list.where((sale) => sale.id == currentId);
    if (matchingSales.isEmpty) {
      _selectedSale = null;
      _selectedSaleId = null;
      return;
    }

    final match = matchingSales.first;
    _selectedSale = match;
    _primeSaleItemsCache(match);
  }

  void _selectSale(SaleModel sale, {required bool showDetails}) {
    _safeSetState(() {
      _selectedSale = sale;
      _selectedSaleId = sale.id;
    });
    _primeSaleItemsCache(sale);
    if (showDetails) {
      _showSaleDetails(sale);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: status.error),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: status.success),
    );
  }

  void _handleBack() {
    final router = GoRouter.of(context);
    final canPopRouter =
        router.routerDelegate.currentConfiguration.matches.length > 1;
    if (canPopRouter) {
      context.pop();
      return;
    }

    // Esta pantalla suele abrirse con context.go('/factura'),
    // así que no hay stack para hacer pop. Volver a Ventas.
    context.go('/sales');
  }

  String _getFilterLabel(DateFilter filter) {
    switch (filter) {
      case DateFilter.all:
        return 'Todas';
      case DateFilter.today:
        return 'Hoy';
      case DateFilter.yesterday:
        return 'Ayer';
      case DateFilter.thisWeek:
        return 'Esta Semana';
      case DateFilter.thisMonth:
        return 'Último mes';
      case DateFilter.custom:
        if (_customDateFrom != null && _customDateTo != null) {
          final format = DateFormat('dd/MM');
          return '${format.format(_customDateFrom!)} - ${format.format(_customDateTo!)}';
        }
        return 'Personalizado';
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _customDateFrom ?? now.subtract(const Duration(days: 7)),
        end: _customDateTo ?? now,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: scheme.primary,
              onPrimary: scheme.onPrimary,
              surface: scheme.surface,
              onSurface: scheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (!mounted) return;
    if (result != null) {
      _safeSetState(() {
        _customDateFrom = result.start;
        _customDateTo = result.end;
        _selectedFilter = DateFilter.custom;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: scheme.surface,
      endDrawerEnableOpenDragGesture: false,
      endDrawer: _buildFiltersDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = (constraints.maxWidth * 0.018).clamp(
            12.0,
            28.0,
          );
          final verticalPadding = 10.0;
          final isWide = constraints.maxWidth >= 1200;
          final detailWidth = constraints.maxWidth < 1300
              ? 520.0
              : constraints.maxWidth < 1600
              ? 590.0
              : 640.0;

          final listPadding = EdgeInsets.fromLTRB(
            horizontalPadding,
            verticalPadding,
            horizontalPadding,
            22.0,
          );

          return Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildSalesTab(
                              listPadding: listPadding,
                              isWide: true,
                            ),
                          ),
                          if (_selectedSale != null) ...[
                            const SizedBox(width: 16),
                            SizedBox(
                              width: detailWidth,
                              child: _buildDetailsPanel(),
                            ),
                          ],
                        ],
                      )
                    : _buildSalesTab(listPadding: listPadding, isWide: false),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasActiveFilters = _activeFilterCount > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 850;

        final horizontalPadding = (constraints.maxWidth * 0.018).clamp(
          14.0,
          26.0,
        );

        const elementHeight = 44.0;
        const gap = 10.0;

        final normalBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDCE5EF), width: 1),
        );

        final searchField = SizedBox(
          height: elementHeight,
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar por código, cliente o total...',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 21,
                color: Color(0xFF64748B),
              ),
              suffixIcon: _searchQuery.trim().isNotEmpty
                  ? IconButton(
                      tooltip: 'Limpiar búsqueda',
                      splashRadius: 18,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: Color(0xFF64748B),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: normalBorder,
              enabledBorder: normalBorder,
              focusedBorder: normalBorder.copyWith(
                borderSide: BorderSide(color: scheme.primary, width: 1.4),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
            ),
          ),
        );

        final filterButton = SizedBox(
          height: elementHeight,
          child: FilledButton.icon(
            onPressed: _openFiltersPanel,
            icon: Icon(
              hasActiveFilters ? Icons.tune_rounded : Icons.filter_alt_outlined,
              size: 19,
            ),
            label: Text(
              hasActiveFilters ? 'Filtro ($_activeFilterCount)' : 'Filtro',
            ),
            style: FilledButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
        );

        final backButton = SizedBox(
          width: elementHeight,
          height: elementHeight,
          child: IconButton(
            tooltip: 'Volver',
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 21),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFDCE5EF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );

        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 11,
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        backButton,
                        const SizedBox(width: gap),
                        Expanded(child: searchField),
                        const SizedBox(width: gap),
                        filterButton,
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildHeaderSummary(),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    backButton,
                    const SizedBox(width: gap),

                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: searchField,
                      ),
                    ),

                    const SizedBox(width: gap),

                    filterButton,

                    const Spacer(),

                    _buildHeaderSummary(),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildFiltersDrawer() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Drawer(
      width: 324,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Filtrar facturas',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ajusta estado, fechas y cajero desde este panel.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar filtros',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.5)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                children: [
                  _buildDrawerSectionTitle('Estado'),
                  ..._InvoiceStatusFilter.values.map(
                    (filter) => RadioListTile<_InvoiceStatusFilter>(
                      value: filter,
                      groupValue: _statusFilter,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(_statusFilterLabel(filter)),
                      onChanged: (value) {
                        if (value == null) return;
                        _updateStatusFilter(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDrawerSectionTitle('Periodo'),
                  ...const [
                    DateFilter.today,
                    DateFilter.yesterday,
                    DateFilter.thisWeek,
                    DateFilter.thisMonth,
                    DateFilter.all,
                    DateFilter.custom,
                  ].map(
                    (filter) => RadioListTile<DateFilter>(
                      value: filter,
                      groupValue: _selectedFilter,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(_drawerDateFilterLabel(filter)),
                      onChanged: (value) {
                        if (value == null) return;
                        _updateDateFilter(value);
                      },
                    ),
                  ),
                  if (_selectedFilter == DateFilter.custom) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _selectCustomDateRange,
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        _customDateFrom != null && _customDateTo != null
                            ? _getFilterLabel(DateFilter.custom)
                            : 'Seleccionar rango',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildDrawerSectionTitle('Cajero'),
                  DropdownButtonFormField<int?>(
                    value: _selectedSessionId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Todos los cajeros'),
                      ),
                      ..._cashierNameBySessionId.entries.map(
                        (entry) => DropdownMenuItem<int?>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      ),
                    ],
                    onChanged: _updateCashierFilter,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
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
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerSectionTitle(String title) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  String _drawerDateFilterLabel(DateFilter filter) {
    switch (filter) {
      case DateFilter.today:
        return 'Hoy';
      case DateFilter.yesterday:
        return 'Ayer';
      case DateFilter.thisWeek:
        return 'Esta semana';
      case DateFilter.thisMonth:
        return 'Último mes';
      case DateFilter.all:
        return 'Todas';
      case DateFilter.custom:
        return 'Personalizado';
    }
  }

  Widget _buildSalesTab({
    required EdgeInsets listPadding,
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    final sales = _filteredSales;
    if (sales.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 34,
                color: scheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                _searchQuery.trim().isEmpty
                    ? 'No hay facturas en este periodo'
                    : 'No se encontraron resultados',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba otro rango, otro cajero o cambia el filtro de devolucion.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: listPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Listado de facturas',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 15.2,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Selecciona una factura para ver el resumen completo a la derecha.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWide) ...[
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      _statusFilter == _InvoiceStatusFilter.all
                          ? 'Mostrando todas las facturas'
                          : _statusFilter == _InvoiceStatusFilter.active
                          ? 'Mostrando facturas activas'
                          : 'Filtro: ${_statusFilterLabel(_statusFilter)}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: sales.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderSoft,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (context, index) {
                final sale = sales[index];
                final isSelected =
                    sale.id != null && sale.id == _selectedSaleId;
                final date = DateTime.fromMillisecondsSinceEpoch(
                  sale.createdAtMs,
                );
                final customer = sale.customerNameSnapshot ?? 'Cliente General';
                final compactInvoiceCode = _compactInvoiceCode(sale.localCode);
                final isFiscal = _isFiscalSale(sale);
                final fiscalStyle = _fiscalStyle(sale);
                final statusStyle = _saleStatusStyle(sale);
                final canRefund = sale.status.toUpperCase() != 'REFUNDED';

                return Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.lightBlueHover.withOpacity(0.30)
                          : isFiscal
                          ? fiscalStyle.rowBackground
                          : Colors.transparent,
                      border: isFiscal
                          ? Border(
                              left: BorderSide(
                                color: fiscalStyle.accent,
                                width: 4,
                              ),
                            )
                          : null,
                    ),
                    child: InkWell(
                      onTap: () => _selectSale(sale, showDetails: !isWide),
                      hoverColor: AppColors.lightBlueHover.withOpacity(0.22),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 17,
                        ),
                        child: LayoutBuilder(
                          builder: (context, rowConstraints) {
                            final compact = rowConstraints.maxWidth < 860;
                            if (compact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    compactInvoiceCode,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontSize: 14.2,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontFamily: 'Inter',
                                                          height: 1.35,
                                                        ),
                                                  ),
                                                ),
                                                if (isFiscal) ...[
                                                  const SizedBox(width: 8),
                                                  _buildFiscalChip(
                                                    sale,
                                                    compact: true,
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              customer,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: scheme.onSurface,
                                                    fontSize: 13.4,
                                                    fontWeight: FontWeight.w400,
                                                    fontFamily: 'Inter',
                                                    height: 1.35,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _buildStatusChip(statusStyle),
                                      _buildSaleRowActions(
                                        sale,
                                        canRefund: canRefund,
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        dateFormat.format(date),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                              fontFamily: 'Inter',
                                              fontSize: 12.8,
                                              fontWeight: FontWeight.w400,
                                              height: 1.35,
                                            ),
                                      ),
                                      Text(
                                        _cashierLabelForSessionId(
                                          sale.sessionId,
                                        ),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                              fontFamily: 'Inter',
                                              fontSize: 12.8,
                                              fontWeight: FontWeight.w400,
                                              height: 1.35,
                                            ),
                                      ),
                                      if (isFiscal)
                                        _buildFiscalMetaText(
                                          sale,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: fiscalStyle.accent,
                                                fontWeight: FontWeight.w500,
                                                fontFamily: 'Inter',
                                                height: 1.3,
                                              ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: _buildMoneyText(
                                      amount: sale.total,
                                      bigStyle: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontSize: 15.4,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Inter',
                                            height: 1.25,
                                          ),
                                      smallStyle: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w400,
                                            fontFamily: 'Inter',
                                            color: AppColors.textSecondary,
                                            height: 1.25,
                                          ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              compactInvoiceCode,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontSize: 14.2,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: 'Inter',
                                                    height: 1.35,
                                                  ),
                                            ),
                                          ),
                                          if (isFiscal) ...[
                                            const SizedBox(width: 8),
                                            _buildFiscalChip(
                                              sale,
                                              compact: true,
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _cashierLabelForSessionId(
                                          sale.sessionId,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                              fontFamily: 'Inter',
                                              fontSize: 12.8,
                                              fontWeight: FontWeight.w400,
                                              height: 1.35,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    customer,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Inter',
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dateFormat.format(date),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                              fontFamily: 'Inter',
                                              fontSize: 12.8,
                                              fontWeight: FontWeight.w400,
                                              height: 1.35,
                                            ),
                                      ),
                                      if (isFiscal) ...[
                                        const SizedBox(height: 4),
                                        _buildFiscalMetaText(
                                          sale,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: fiscalStyle.accent,
                                                fontWeight: FontWeight.w500,
                                                fontFamily: 'Inter',
                                                height: 1.3,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                _buildStatusChip(statusStyle),
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _buildMoneyText(
                                      amount: sale.total,
                                      bigStyle: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontSize: 15.4,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Inter',
                                            height: 1.25,
                                          ),
                                      smallStyle: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w400,
                                            fontFamily: 'Inter',
                                            color: AppColors.textSecondary,
                                            height: 1.25,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildSaleRowActions(
                                  sale,
                                  canRefund: canRefund,
                                ),
                              ],
                            );
                          },
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

  Widget _buildSaleRowActions(
    SaleModel sale, {
    required bool canRefund,
    bool compact = false,
  }) {
    Widget actionButton({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
      Color? color,
    }) {
      return Semantics(
        button: true,
        label: label,
        child: IconButton(
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints.tightFor(
            width: compact ? 32 : 34,
            height: compact ? 32 : 34,
          ),
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 18, color: color),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        actionButton(
          label: 'Ver factura',
          icon: Icons.visibility_outlined,
          onPressed: () => _showSaleDetails(sale),
        ),
        if (canRefund) ...[
          const SizedBox(width: 2),
          actionButton(
            label: 'Reembolsar factura',
            icon: Icons.assignment_return_outlined,
            color: const Color(0xFFB45309),
            onPressed: () => _showRefundDialog(sale),
          ),
        ],
      ],
    );
  }

  Widget _buildHeaderSummary() {
    final money = CurrencyDisplay.currency();

    final sales = _filteredSales;
    final invoiceCount = sales.length;

    final totalSold = sales.fold<double>(0, (sum, sale) => sum + sale.total);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE5EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeaderMetric(
            icon: Icons.receipt_long_outlined,
            label: 'FACTURAS',
            value: invoiceCount.toString(),
          ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFFE2E8F0),
          ),
          _buildHeaderMetric(
            icon: Icons.payments_outlined,
            label: 'TOTAL VENDIDO',
            value: money.format(totalSold),
            emphasizeValue: true,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric({
    required IconData icon,
    required String label,
    required String value,
    bool emphasizeValue = false,
  }) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: const Color(0xFF2563EB)),
        ),
        const SizedBox(width: 9),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF64748B),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.45,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: emphasizeValue
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF334155),
                fontSize: emphasizeValue ? 14.5 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailsPanel() {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: DefaultTextStyle(
          style:
              theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Inter',
                height: 1.35,
                fontWeight: FontWeight.w400,
              ) ??
              const TextStyle(fontFamily: 'Inter', height: 1.35),
          child: _buildSaleDetailsPanel(_selectedSale),
        ),
      ),
    );
  }

  ({String label, Color background, Color foreground}) _saleStatusStyle(
    SaleModel sale,
  ) {
    switch (sale.status.toUpperCase()) {
      case 'REFUNDED':
        return (
          label: 'DEVUELTA',
          background: const Color(0xFFFEE2E2),
          foreground: const Color(0xFF991B1B),
        );
      case 'PARTIAL_REFUND':
        return (
          label: 'PARCIAL',
          background: const Color(0xFFFEF3C7),
          foreground: const Color(0xFF92400E),
        );
      default:
        return (
          label: 'ACTIVA',
          background: const Color(0xFFDCFCE7),
          foreground: const Color(0xFF166534),
        );
    }
  }

  bool _isFiscalSale(SaleModel sale) {
    if (sale.electronicInvoiceEnabled == 1) return true;
    if ((sale.electronicInvoiceCode ?? '').trim().isNotEmpty) return true;
    if ((sale.electronicDocumentType ?? '').trim().isNotEmpty) return true;
    return false;
  }

  ({
    String label,
    String meta,
    Color accent,
    Color background,
    Color rowBackground,
  })
  _fiscalStyle(SaleModel sale) {
    final rawType = (sale.electronicDocumentType ?? '').trim().toUpperCase();
    final rawCode = (sale.electronicInvoiceCode ?? '').trim().toUpperCase();
    final type = rawType.isNotEmpty
        ? rawType
        : rawCode.startsWith('E31')
        ? 'E31'
        : rawCode.startsWith('E32')
        ? 'E32'
        : 'eCF';
    final meta = rawCode.isNotEmpty ? rawCode : type;
    return (
      label: 'FISCAL $type',
      meta: meta,
      accent: const Color(0xFFB45309),
      background: const Color(0xFFFFF3D6),
      rowBackground: const Color(0xFFFFFBF2),
    );
  }

  Widget _buildStatusChip(
    ({String label, Color background, Color foreground}) style,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: style.foreground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildFiscalChip(SaleModel sale, {bool compact = false}) {
    final style = _fiscalStyle(sale);
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.accent.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: compact ? 13 : 14,
            color: style.accent,
          ),
          const SizedBox(width: 5),
          Text(
            compact ? style.label.replaceFirst('FISCAL ', '') : style.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: style.accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiscalMetaText(SaleModel sale, {required TextStyle? style}) {
    final fiscalStyle = _fiscalStyle(sale);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_outlined, size: 13, color: fiscalStyle.accent),
        const SizedBox(width: 4),
        Text(fiscalStyle.meta, style: style),
      ],
    );
  }

  Widget _buildSaleDetailsPanel(SaleModel? sale) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    if (sale == null) {
      return const SizedBox.shrink();
    }

    final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
    final rawCustomer = sale.customerNameSnapshot?.trim() ?? '';
    final hasNamedCustomer =
        rawCustomer.isNotEmpty &&
        rawCustomer.toLowerCase() != 'cliente general';
    final customer = hasNamedCustomer ? rawCustomer : 'Cliente General';
    final statusStyle = _saleStatusStyle(sale);
    final canRefund = sale.status.toUpperCase() != 'REFUNDED';
    final relatedReturns = _returnsForSale(sale);
    final refundedAmount = _refundedAmountForSale(sale);
    final netAmount = (sale.total - refundedAmount).clamp(0, sale.total);
    final paymentLabel = sale.paymentMethodDisplayLabel;
    final compactInvoiceCode = _compactInvoiceCode(sale.localCode);
    final isFiscal = _isFiscalSale(sale);
    final fiscalStyle = _fiscalStyle(sale);

    return FutureBuilder<List<SaleItemModel>>(
      future: _loadSaleItemsForSale(sale),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <SaleItemModel>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasNamedCustomer ? customer : compactInvoiceCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasNamedCustomer
                            ? compactInvoiceCode
                            : 'Factura activa',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatusChip(statusStyle),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Cerrar detalle',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          onPressed: () {
                            _safeSetState(() {
                              _selectedSale = null;
                              _selectedSaleId = null;
                            });
                          },
                          icon: const Icon(Icons.close_rounded, size: 19),
                        ),
                      ],
                    ),
                    if (isFiscal) ...[
                      const SizedBox(height: 8),
                      _buildFiscalChip(sale),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildTicketMetaRow('Fecha', dateFormat.format(date)),
            _buildTicketMetaRow(
              'Cajero',
              _cashierLabelForSessionId(sale.sessionId),
            ),
            if (isFiscal)
              _buildTicketMetaRow('Comprobante fiscal', fiscalStyle.meta),
            _buildTicketMetaRow('Pago', paymentLabel),
            if ((sale.customerPhoneSnapshot ?? '').trim().isNotEmpty)
              _buildTicketMetaRow('Telefono', sale.customerPhoneSnapshot!),
            if ((sale.customerRncSnapshot ?? '').trim().isNotEmpty)
              _buildTicketMetaRow('RNC', sale.customerRncSnapshot!),
            const SizedBox(height: 14),
            Divider(color: scheme.outlineVariant.withOpacity(0.45), height: 1),
            const SizedBox(height: 12),
            Text(
              'DETALLE',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty && relatedReturns.isEmpty
                  ? Center(
                      child: Text(
                        'No hay articulos disponibles para esta factura.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: const MaterialScrollBehavior().copyWith(
                        scrollbars: false,
                      ),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          ...items.map((item) => _buildTicketItemRow(item)),
                          if (relatedReturns.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Divider(
                              color: scheme.outlineVariant.withOpacity(0.45),
                              height: 1,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'DEVOLUCIONES',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.0,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...relatedReturns
                                .take(3)
                                .map(_buildRefundEntryLine),
                          ],
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Divider(color: scheme.outlineVariant.withOpacity(0.45), height: 1),
            const SizedBox(height: 12),
            _buildTicketAmountRow('Subtotal', sale.subtotal),
            if (sale.discountTotal > 0.009)
              _buildTicketAmountRow('Descuento', -sale.discountTotal),
            if (sale.itbisAmount > 0.009)
              _buildTicketAmountRow('ITBIS', sale.itbisAmount),
            _buildTicketAmountRow(
              'Total factura',
              sale.total,
              emphasized: true,
            ),
            if (refundedAmount > 0.009)
              _buildTicketAmountRow('Devuelto', -refundedAmount),
            _buildTicketAmountRow(
              'Neto vigente',
              netAmount.toDouble(),
              emphasized: refundedAmount > 0.009,
            ),
            if (sale.paidAmount > 0.009 &&
                (sale.paidAmount - sale.total).abs() > 0.009) ...[
              const SizedBox(height: 8),
              _buildTicketAmountRow('Recibido', sale.paidAmount),
              if (sale.changeAmount > 0.009)
                _buildTicketAmountRow('Cambio', -sale.changeAmount),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (canRefund) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showRefundDialog(sale),
                      icon: const Icon(
                        Icons.assignment_return_outlined,
                        size: 18,
                      ),
                      label: const Text('Devolver'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        snapshot.connectionState == ConnectionState.waiting
                        ? null
                        : () => _printTicket(sale, items),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Imprimir'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTicketMetaRow(String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 12.8,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.8,
                fontWeight: FontWeight.w400,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketItemRow(SaleItemModel item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 6,
            child: Text(
              item.productNameSnapshot,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.6,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              item.discountLine > 0.009
                  ? '${_formatQty(item.qty)} x ${CurrencyDisplay.format(item.unitPrice, symbol: 'RD\$')}  Desc ${CurrencyDisplay.format(item.discountLine, symbol: 'RD\$')}'
                  : '${_formatQty(item.qty)} x ${CurrencyDisplay.format(item.unitPrice, symbol: 'RD\$')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11.8,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(
              CurrencyDisplay.format(item.totalLine, symbol: 'RD\$'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.6,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketAmountRow(
    String label,
    double amount, {
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: emphasized ? 13.2 : 12.2,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                color: emphasized ? scheme.onSurface : scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          Text(
            CurrencyDisplay.format(amount, symbol: 'RD\$'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: emphasized ? 13.4 : 12.2,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              color: emphasized ? scheme.onSurface : scheme.onSurface,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundEntryLine(Map<String, dynamic> ret) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');
    final code = (ret['local_code'] as String?) ?? 'DEV-${ret['id']}';
    final total = ((ret['total'] as num?)?.toDouble() ?? 0).abs();
    final createdMs = (ret['created_at_ms'] as int?) ?? 0;
    final creditNoteEcf =
        (ret['electronic_credit_note_ecf'] as String?)?.trim() ?? '';
    final originalEcf =
        (ret['original_electronic_ecf'] as String?)?.trim() ?? '';
    final originalDocumentType =
        (ret['original_electronic_document_type'] as String?)?.trim() ?? '';
    final creditNoteStatusRaw =
        (ret['electronic_credit_note_status'] as String?)?.trim() ?? '';
    final creditNoteRequested =
        ((ret['electronic_credit_note_requested'] as int?) ?? 0) == 1;
    final originalRelationLabel = originalEcf.isNotEmpty
        ? 'Sobre $originalEcf'
        : switch (originalDocumentType.toUpperCase()) {
            '31' => 'Sobre factura fiscal E31',
            '32' => 'Sobre factura fiscal E32',
            _ => '',
          };

    String creditNoteStatusLabel() {
      switch (creditNoteStatusRaw.toUpperCase()) {
        case 'ACCEPTED':
        case 'ACEPTADA':
          return 'Aceptada';
        case 'REJECTED':
        case 'RECHAZADA':
          return 'Rechazada';
        case 'IN_PROCESS':
        case 'SUBMITTED':
          return 'Enviada';
        case 'PENDING_SYNC':
          return 'Pendiente sync';
        default:
          return creditNoteRequested ? 'Pendiente' : 'Local';
      }
    }

    Color creditNoteStatusColor() {
      switch (creditNoteStatusRaw.toUpperCase()) {
        case 'ACCEPTED':
        case 'ACEPTADA':
          return status.success;
        case 'REJECTED':
        case 'RECHAZADA':
          return status.error;
        case 'IN_PROCESS':
        case 'SUBMITTED':
        case 'PENDING_SYNC':
          return status.warning;
        default:
          return scheme.onSurfaceVariant;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateFormat.format(
                    DateTime.fromMillisecondsSinceEpoch(createdMs),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10.8,
                  ),
                ),
                if (creditNoteEcf.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'E34 $creditNoteEcf',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.info,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else if (creditNoteRequested)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'E34 pendiente de emisión',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.warning,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (originalRelationLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      originalRelationLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (creditNoteRequested)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: creditNoteStatusColor().withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  creditNoteStatusLabel(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: creditNoteStatusColor(),
                    fontSize: 10.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 10),
          Text(
            CurrencyDisplay.format(total, symbol: 'RD\$'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatQty(double qty) {
    if ((qty - qty.roundToDouble()).abs() < 0.001) {
      return qty.round().toString();
    }
    return qty
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _compactInvoiceCode(String code) {
    final trimmed = code.trim();
    if (trimmed.length <= 16) return trimmed;
    return 'Factura ${trimmed.substring(trimmed.length - 8)}';
  }

  Widget _buildMoneyText({
    required double amount,
    required TextStyle? bigStyle,
    required TextStyle? smallStyle,
  }) {
    final formatter = CurrencyDisplay.currency(symbol: '');

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: 'RD\$ ', style: smallStyle),
          TextSpan(text: formatter.format(amount).trim(), style: bigStyle),
        ],
      ),
    );
  }

  /// Muestra detalles de la venta con opción de imprimir
  Future<void> _showSaleDetails(SaleModel sale) async {
    final items = await SalesRepository.getItemsBySaleId(sale.id!);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _SaleTicketDialog(
        sale: sale,
        items: items,
        onPrint: () => _printTicket(sale, items),
        onRefund: () {
          Navigator.pop(context);
          _showRefundDialog(sale);
        },
      ),
    );
  }

  /// Imprime el ticket
  Future<void> _printTicket(SaleModel sale, List<SaleItemModel> items) async {
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();
      if (settings.selectedPrinterName == null ||
          settings.selectedPrinterName!.isEmpty) {
        _showError('No hay impresora configurada');
        return;
      }

      // Obtener nombre del cajero desde la sesión
      final cashierName = await SessionManager.displayName() ?? 'Cajero';

      final result = await UnifiedTicketPrinter.printSaleTicket(
        sale: sale,
        items: items,
        cashierName: cashierName,
        overrideCopies: 1,
      );
      if (result.success) {
        _showSuccess('Ticket impreso correctamente');
      } else {
        _showError('No se pudo imprimir. Verifique la impresora y reintente.');
      }
    } catch (e, st) {
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _printTicket(sale, items),
        module: 'sales/returns_list/print',
      );
    }
  }

  /// Muestra el diálogo de reembolso
  Future<void> _showRefundDialog(SaleModel sale) async {
    if (sale.id == null) {
      _showError('No se puede procesar: ticket inválido (sin ID).');
      return;
    }

    try {
      final result = await showSaleRefundDialog(context, sale);
      if (!mounted) return;

      if (result == SaleRefundOutcome.refunded) {
        _showSuccess('¡Devolución procesada!');
        _loadData();
      } else if (result == SaleRefundOutcome.cancelled) {
        _showSuccess('✅ Ticket cancelado y stock restaurado');
        _loadData();
      }
    } catch (e, st) {
      if (!mounted) return;
      await AppLogger.instance.logWarn(
        'No se pudo abrir devolución ${sale.localCode}: $e\n$st',
        module: 'sales/returns_list/refund_dialog',
      );
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      FullPosNotifications.error(
        message.isEmpty ? 'No se pudo abrir la devolución.' : message,
        title: 'Devolución no disponible',
        deduplicationKey: 'invoice-refund-open-${sale.id}',
        actionLabel: 'Reintentar',
        onAction: () => _showRefundDialog(sale),
      );
    }
  }
}

enum _RefundDialogResult { refunded, cancelled }

/// Diálogo para ver el ticket de la venta
class _SaleTicketDialog extends StatelessWidget {
  final SaleModel sale;
  final List<SaleItemModel> items;
  final VoidCallback onPrint;
  final VoidCallback onRefund;

  const _SaleTicketDialog({
    required this.sale,
    required this.items,
    required this.onPrint,
    required this.onRefund,
  });

  bool get _supportsE34 => _supportsElectronicCreditNote(sale);

  @override
  Widget build(BuildContext context) {
    final currencyFormat = CurrencyDisplay.currency();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
    final screenSize = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status =
        theme.extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.tertiary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.primary,
        );
    final gradientTheme = theme.extension<AppGradientTheme>();
    final headerGradient =
        gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [scheme.primary, scheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    final headerMid = gradientTheme?.mid ?? scheme.primaryContainer;
    final headerText = ColorUtils.ensureReadableColor(
      scheme.onPrimary,
      headerMid,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.05,
        vertical: screenSize.height * 0.05,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 450,
          maxHeight: screenSize.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: headerGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: headerText.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.receipt_long,
                          color: headerText,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sale.localCode,
                              style: TextStyle(
                                color: headerText,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateFormat.format(date),
                              style: TextStyle(
                                color: headerText.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: headerText),
                        style: IconButton.styleFrom(
                          backgroundColor: headerText.withOpacity(0.16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Info del cliente
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: headerText.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person, color: headerText, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sale.customerNameSnapshot ?? 'Cliente General',
                            style: TextStyle(
                              color: headerText,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: headerText.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sale.paymentMethod?.toUpperCase() ?? 'EFECTIVO',
                            style: TextStyle(
                              color: headerText,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_supportsE34) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: headerText.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: headerText.withOpacity(0.18)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            color: headerText,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Comprobante electronico ${sale.electronicInvoiceCode ?? ''}. La devolución se emitirá como nota de credito E34.',
                              style: TextStyle(
                                color: headerText,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Lista de productos
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${item.qty.toInt()}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: scheme.onSecondaryContainer,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productNameSnapshot,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${currencyFormat.format(item.unitPrice)} c/u',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          currencyFormat.format(item.totalLine),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Totales
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceVariant.withOpacity(0.4),
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Column(
                children: [
                  _buildTotalRow(
                    context,
                    'Subtotal',
                    currencyFormat.format(sale.subtotal),
                  ),
                  if (sale.itbisEnabled == 1)
                    _buildTotalRow(
                      context,
                      'ITBIS (${(sale.itbisRate * 100).toStringAsFixed(0)}%)',
                      currencyFormat.format(sale.itbisAmount),
                    ),
                  if (sale.discountTotal > 0)
                    _buildTotalRow(
                      context,
                      'Descuento',
                      '-${currencyFormat.format(sale.discountTotal)}',
                      valueColor: status.error,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        currencyFormat.format(sale.total),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Botones de acción
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPrint,
                      icon: const Icon(Icons.print, size: 20),
                      label: const Text('Imprimir'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.primary,
                        side: BorderSide(color: scheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onRefund,
                      icon: const Icon(Icons.keyboard_return, size: 20),
                      label: Text(
                        _supportsE34 ? 'Nota de credito E34' : 'Devolver',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          ),
          Text(value, style: TextStyle(fontSize: 14, color: valueColor)),
        ],
      ),
    );
  }
}

/// Diálogo de reembolso
class _RefundDialog extends StatefulWidget {
  final SaleModel sale;
  final List<SaleItemModel> items;
  final Map<int, double> returnedQuantities;

  const _RefundDialog({
    required this.sale,
    required this.items,
    required this.returnedQuantities,
  });

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final List<double> _returnQuantities;
  final _noteController = TextEditingController();
  bool _isProcessing = false;
  bool _refundAll = false;
  String? _noteError;

  bool get _supportsE34 => _supportsElectronicCreditNote(widget.sale);

  String get _refundActionLabel =>
      _supportsE34 ? 'Generar nota de credito E34' : 'Procesar';

  String get _refundDialogTitle =>
      _supportsE34 ? 'Generar Nota de Crédito E34' : 'Procesar Devolución';

  String get _refundDialogSubtitle => _supportsE34
      ? '${widget.sale.localCode} · ${widget.sale.electronicInvoiceCode ?? 'e-CF original'}'
      : widget.sale.localCode;

  String get _refundSelectionHint => _supportsE34
      ? 'Selecciona los productos a acreditar. La DGII recibirá una E34 enlazada al comprobante original.'
      : 'Selecciona los productos que deseas devolver.';

  double _remainingQuantity(int index) {
    final item = widget.items[index];
    final itemId = item.id;
    if (itemId == null) return 0;
    final returned = widget.returnedQuantities[itemId] ?? 0;
    return (item.qty - returned).clamp(0, item.qty).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _returnQuantities = List<double>.filled(widget.items.length, 0);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  double get _totalReturn {
    final items = <({double quantity, double unitPrice})>[];
    for (var i = 0; i < widget.items.length; i++) {
      final qty = _returnQuantities[i];
      if (qty > 0) {
        items.add((
          quantity: qty,
          unitPrice: _refundUnitPrice(widget.items[i]),
        ));
      }
    }
    return RefundCalculator.totals(
      items: items,
      itbisEnabled: widget.sale.itbisEnabled == 1,
      itbisRate: widget.sale.itbisRate,
    ).total;
  }

  double get _refundSubtotal {
    final items = <({double quantity, double unitPrice})>[];
    for (var i = 0; i < widget.items.length; i++) {
      final qty = _returnQuantities[i];
      if (qty > 0) {
        items.add((
          quantity: qty,
          unitPrice: _refundUnitPrice(widget.items[i]),
        ));
      }
    }
    return RefundCalculator.totals(
      items: items,
      itbisEnabled: false,
      itbisRate: widget.sale.itbisRate,
    ).subtotal;
  }

  double get _refundTax => widget.sale.itbisEnabled == 1
      ? RefundCalculator.roundMoney(_refundSubtotal * widget.sale.itbisRate)
      : 0;

  bool get _hasSelectedItems => _returnQuantities.any((qty) => qty > 0);
  bool get _hasPreviousReturns =>
      widget.returnedQuantities.values.any((quantity) => quantity > 0.0001);

  double _refundUnitPrice(SaleItemModel item) {
    final lineNetSubtotal = widget.items.fold<double>(
      0,
      (sum, current) => sum + current.totalLine,
    );
    final factor = RefundCalculator.globalDiscountFactor(
      saleSubtotal: widget.sale.subtotal,
      lineNetSubtotal: lineNetSubtotal,
    );
    return RefundCalculator.refundableUnitPrice(
      quantity: item.qty,
      unitPrice: item.unitPrice,
      lineDiscount: item.discountLine,
      globalDiscountFactor: factor,
    );
  }

  bool _validateReason() {
    final reason = _noteController.text.trim();
    if (reason.length >= 3) {
      if (_noteError != null) setState(() => _noteError = null);
      return true;
    }
    setState(() {
      _noteError = 'Escribe un motivo de al menos 3 caracteres.';
    });
    return false;
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String actionLabel,
    bool destructive = false,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Volver'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: destructive ? scheme.error : scheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _reportRefundFailure(
    Object error,
    StackTrace stackTrace, {
    required String operation,
    required Future<void> Function() retry,
  }) async {
    await AppLogger.instance.logWarn(
      '$operation falló para ${widget.sale.localCode}: $error\n$stackTrace',
      module: 'sales/refund',
    );
    if (!mounted) return;
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    FullPosNotifications.error(
      message.isEmpty
          ? 'No se pudo completar la devolución. Revisa los datos e inténtalo nuevamente.'
          : message,
      title: 'No se pudo completar la devolución',
      deduplicationKey: 'refund-error-${widget.sale.id}-$operation',
      actionLabel: 'Reintentar',
      onAction: retry,
    );
  }

  Future<bool> _ensureCashAvailableForRefund(double amount) async {
    if (amount <= 0) return true;

    final sessionId = await CashRepository.getCurrentSessionId();
    if (sessionId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay caja abierta. Abra caja para procesar devoluciones.',
            ),
          ),
        );
      }
      return false;
    }

    final summary = await CashRepository.buildSummary(sessionId: sessionId);
    final available = summary.expectedCash;
    if (available + 0.009 >= amount) return true;

    final decision = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Caja sin efectivo suficiente'),
        content: Text(
          'Disponible en caja: ${CurrencyDisplay.format(available)}\n'
          'Reembolso requerido: ${CurrencyDisplay.format(amount)}\n\n'
          'Ingrese efectivo a caja antes de continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'add'),
            child: const Text('Agregar efectivo'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (decision == 'add') {
      await CashMovementDialog.show(
        context,
        type: CashMovementType.income,
        sessionId: sessionId,
      );

      final refreshed = await CashRepository.buildSummary(sessionId: sessionId);
      if (refreshed.expectedCash + 0.009 >= amount) {
        return true;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sigue faltando efectivo. Disponible: ${CurrencyDisplay.format(refreshed.expectedCash)}',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    return false;
  }

  Future<bool> _warnIfDifferentSession() async {
    final saleSessionId = widget.sale.sessionId;
    final currentSession = await CashRepository.getOpenSession();
    if (saleSessionId == null || currentSession == null) return true;
    if (saleSessionId == currentSession.id) return true;

    final originalSession = await CashRepository.getSessionById(saleSessionId);
    final originalUser = originalSession?.userName ?? 'otro cajero';
    final originalId = originalSession?.id ?? saleSessionId;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ticket de otra sesión'),
        content: Text(
          'Este ticket se creó en la sesión #$originalId ($originalUser).\n'
          'Tu sesión actual es #${currentSession.id} (${currentSession.userName}).\n\n'
          '¿Deseas anularlo de todos modos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No anular'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular igualmente'),
          ),
        ],
      ),
    );

    return proceed == true;
  }

  void _toggleRefundAll() {
    setState(() {
      _refundAll = !_refundAll;
      for (var i = 0; i < widget.items.length; i++) {
        _returnQuantities[i] = _refundAll ? _remainingQuantity(i) : 0;
      }
    });
  }

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  Future<void> _processRefund() async {
    if (!_hasSelectedItems) return;
    if (!_validateReason()) return;

    if (!await _ensureCashAvailableForRefund(_totalReturn)) {
      return;
    }

    final confirmed = await _confirmAction(
      title: _supportsE34
          ? 'Confirmar nota de crédito'
          : 'Confirmar devolución',
      message:
          'Se devolverán ${CurrencyDisplay.format(_totalReturn)} y se restaurará el inventario seleccionado. Esta acción quedará registrada.',
      actionLabel: _supportsE34 ? 'Generar E34' : 'Confirmar devolución',
    );
    if (!mounted) return;
    if (!confirmed) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.processReturn,
      resourceType: 'sale',
      resourceId: widget.sale.id?.toString(),
      reason: 'Procesar devolucion',
    );
    if (!mounted) return;
    if (!authorized) return;

    setState(() => _isProcessing = true);
    var completed = false;

    try {
      final returnItems = <Map<String, dynamic>>[];
      for (var i = 0; i < widget.items.length; i++) {
        final item = widget.items[i];
        final qty = _returnQuantities[i];
        if (qty > 0) {
          final saleItemId = item.id;
          if (saleItemId == null) {
            throw StateError('Item inválido: sale_item_id nulo');
          }
          returnItems.add({'sale_item_id': saleItemId, 'qty': qty});
        }
      }

      await ReturnsRepository.createReturn(
        originalSaleId: widget.sale.id!,
        returnItems: returnItems,
        cashSessionId: await CashRepository.getCurrentSessionId(),
        note: _noteController.text.trim(),
        electronicCreditNoteRequested: _supportsE34,
      );

      completed = true;
      if (mounted) Navigator.pop(context, _RefundDialogResult.refunded);
    } catch (e, st) {
      await _reportRefundFailure(
        e,
        st,
        operation: 'procesar',
        retry: _processRefund,
      );
    } finally {
      if (!completed && mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _cancelFullSale() async {
    if (_hasPreviousReturns) {
      FullPosNotifications.warning(
        'Esta factura ya tiene devoluciones. Devuelve únicamente los productos restantes.',
        title: 'Anulación no disponible',
        deduplicationKey: 'refund-existing-${widget.sale.id}',
      );
      return;
    }

    if (!_validateReason()) return;

    final proceed = await _warnIfDifferentSession();
    if (!mounted) return;
    if (!proceed) return;

    final confirmed = await _confirmAction(
      title: 'Anular factura completa',
      message:
          'Se anulará ${widget.sale.localCode} y se restaurará todo su inventario. Esta acción no se puede deshacer.',
      actionLabel: 'Anular factura',
      destructive: true,
    );
    if (!mounted || !confirmed) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.cancelSale,
      resourceType: 'sale',
      resourceId: widget.sale.id?.toString(),
      reason: 'Anular ticket',
    );
    if (!mounted) return;
    if (!authorized) return;

    setState(() => _isProcessing = true);

    try {
      final saleId = widget.sale.id;
      if (saleId == null) {
        throw StateError('Ticket inválido (sin ID)');
      }

      final ok = await SalesRepository.cancelSale(
        saleId,
        reason: _noteController.text.trim(),
      );
      if (!ok) {
        throw StateError('No se pudo anular (posiblemente ya estaba anulada)');
      }

      if (mounted) Navigator.pop(context, _RefundDialogResult.cancelled);
    } catch (e, st) {
      await _reportRefundFailure(
        e,
        st,
        operation: 'anular',
        retry: _cancelFullSale,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = CurrencyDisplay.currency();
    final screenSize = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status =
        theme.extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.tertiary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.primary,
        );
    const brandBlue = Color(0xFF1A56DB);
    const brandNavy = Color(0xFF0F172A);
    const borderColor = Color(0xFFD8E0EA);
    const surfaceSoft = Color(0xFFF6F8FB);
    final hasRefundableItems = List.generate(
      widget.items.length,
      _remainingQuantity,
    ).any((quantity) => quantity > 0.0001);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: screenSize.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: brandNavy.withOpacity(0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 17, 14, 17),
              color: brandBlue,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Icon(
                      Icons.assignment_return_outlined,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _refundDialogTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _refundDialogSubtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.pop(context),
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 13),
              decoration: const BoxDecoration(
                color: surfaceSoft,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Productos de la factura',
                          style: TextStyle(
                            color: brandNavy,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _refundSelectionHint,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: hasRefundableItems && !_isProcessing
                        ? _toggleRefundAll
                        : null,
                    icon: Icon(
                      _refundAll
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _refundAll ? 'Quitar selección' : 'Seleccionar todo',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: brandBlue,
                      side: const BorderSide(color: Color(0xFFB8C8E8)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final returnQty = _returnQuantities[index];
                  final isSelected = returnQty > 0;
                  final remainingQty = _remainingQuantity(index);
                  final hasRemaining = remainingQty > 0.0001;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF0F5FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF8FB0F4)
                            : borderColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? brandBlue
                                : const Color(0xFFEFF3F8),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.check_rounded
                                : Icons.inventory_2_outlined,
                            size: 18,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productNameSnapshot,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? brandBlue : brandNavy,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                hasRemaining
                                    ? '${currencyFormat.format(_refundUnitPrice(item))} c/u · Vendido: ${_formatQuantity(item.qty)} · Disponible: ${_formatQuantity(remainingQty)}'
                                    : 'Este producto ya fue devuelto por completo',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasRemaining
                                      ? scheme.onSurfaceVariant
                                      : status.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : surfaceSoft,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFB8C8E8)
                                  : borderColor,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.remove,
                                  size: 18,
                                  color: returnQty > 0
                                      ? brandBlue
                                      : const Color(0xFF94A3B8),
                                ),
                                onPressed: returnQty > 0
                                    ? () => setState(() {
                                        _returnQuantities[index] =
                                            (returnQty - 1)
                                                .clamp(0, remainingQty)
                                                .toDouble();
                                        _refundAll = false;
                                      })
                                    : null,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                              SizedBox(
                                width: 42,
                                child: Text(
                                  _formatQuantity(returnQty),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? brandBlue
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: returnQty < item.qty
                                      ? brandBlue
                                      : const Color(0xFF94A3B8),
                                ),
                                onPressed: returnQty < remainingQty
                                    ? () => setState(
                                        () => _returnQuantities[index] =
                                            (returnQty + 1)
                                                .clamp(0, remainingQty)
                                                .toDouble(),
                                      )
                                    : null,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TextField(
                controller: _noteController,
                enabled: !_isProcessing,
                maxLines: 2,
                onChanged: (_) {
                  if (_noteError != null) setState(() => _noteError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Motivo obligatorio',
                  hintText: 'Ej.: producto defectuoso, cambio o error de venta',
                  errorText: _noteError,
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  filled: true,
                  fillColor: surfaceSoft,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: borderColor),
                  ),
                ),
              ),
            ),

            Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: surfaceSoft,
                borderRadius: BorderRadius.all(Radius.circular(8)),
                border: Border.fromBorderSide(BorderSide(color: borderColor)),
              ),
              child: Column(
                children: [
                  _refundSummaryRow(
                    'Subtotal seleccionado',
                    currencyFormat.format(_refundSubtotal),
                  ),
                  if (widget.sale.itbisEnabled == 1) ...[
                    const SizedBox(height: 7),
                    _refundSummaryRow(
                      'ITBIS (${(widget.sale.itbisRate * 100).toStringAsFixed(2)}%)',
                      currencyFormat.format(_refundTax),
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: borderColor),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total a reembolsar',
                          style: TextStyle(
                            color: brandNavy,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        currencyFormat.format(_totalReturn),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 21,
                          color: _hasSelectedItems
                              ? brandBlue
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing || _hasPreviousReturns
                              ? null
                              : _cancelFullSale,
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Anular factura'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: status.error,
                            side: BorderSide(color: status.error),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _hasSelectedItems && !_isProcessing
                              ? _processRefund
                              : null,
                          icon: _isProcessing
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.check_circle, size: 18),
                          label: Text(
                            _isProcessing
                                ? 'Procesando...'
                                : _refundActionLabel,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: scheme.surfaceVariant
                                .withOpacity(0.6),
                            minimumSize: const Size(0, 44),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refundSummaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
