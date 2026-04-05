import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/errors/error_handler.dart';
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
import '../../reports/data/reports_repository.dart';
import '../data/sales_model.dart';
import '../data/sales_repository.dart';
import '../data/returns_repository.dart';
import 'dialogs/refund_reason_dialog.dart';

/// Filtros de fecha predefinidos
enum DateFilter { all, today, yesterday, thisWeek, thisMonth, custom }

enum _SalesRowAction { view, refund }

enum _InvoiceStatusFilter { all, active, withRefund, partialRefund, refunded }

/// Pantalla de facturas con devolucion integrada por factura.
class FacturaPage extends StatefulWidget {
  const FacturaPage({super.key});

  @override
  State<FacturaPage> createState() => _FacturaPageState();
}

class _FacturaPageState extends State<FacturaPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  SaleModel? _selectedSale;
  int? _selectedSaleId;

  List<SaleModel> _completedSales = [];
  List<Map<String, dynamic>> _returns = [];
  Map<int, String> _cashierNameBySessionId = <int, String>{};
  bool _isLoading = false;
  String _searchQuery = '';
  int _loadSeq = 0;

  // Filtros de fecha
  DateFilter _selectedFilter = DateFilter.thisMonth;
  DateTime? _customDateFrom;
  DateTime? _customDateTo;
  int? _selectedSessionId;
  _InvoiceStatusFilter _statusFilter = _InvoiceStatusFilter.all;

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

  @override
  void initState() {
    super.initState();
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
        final startOfMonth = DateTime(now.year, now.month, 1);
        return (startOfMonth, now);
      case DateFilter.custom:
        return (_customDateFrom, _customDateTo);
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
          .runDbSafe<
            (
              List<SaleModel>,
              List<Map<String, dynamic>>,
              List<CategoryPerformanceData>,
            )
          >(() async {
            final sales = await SalesRepository.listCompletedSales(
              dateFrom: dateFrom,
              dateTo: dateTo,
            );
            final returns = await ReturnsRepository.listReturns(
              dateFrom: dateFrom,
              dateTo: dateTo,
            );
            final now = DateTime.now();
            final startMs = dateFrom?.millisecondsSinceEpoch ?? 0;
            final endMs = (dateTo ?? now).millisecondsSinceEpoch;
            final categoryPerformance =
                await ReportsRepository.getCategoryPerformance(
                  startMs: startMs,
                  endMs: endMs,
                );
            return (sales, returns, categoryPerformance);
          }, stage: 'sales/returns_list/load');
      final (sales, returns, categoryPerformance) = result;
      final cashierNames = await _loadCashierNames([
        ...sales.map((sale) => sale.sessionId).whereType<int>(),
        ...returns.map((ret) => ret['session_id'] as int?).whereType<int>(),
      ]);

      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() {
        _completedSales = sales
            .where((s) => s.kind == 'invoice' && s.status != 'cancelled')
            .toList();
        _returns = returns;
        _cashierNameBySessionId = cashierNames;
        if (_selectedSessionId != null &&
            !_cashierNameBySessionId.containsKey(_selectedSessionId)) {
          _selectedSessionId = null;
        }

        _ensureSelection();
      });
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
    _safeSetState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _loadData();
    });
  }

  bool _matchesStatusFilter(SaleModel sale) {
    final statusValue = sale.status.toUpperCase();
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
        return 'Todas';
      case _InvoiceStatusFilter.active:
        return 'Sin devolucion';
      case _InvoiceStatusFilter.withRefund:
        return 'Con devolucion';
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
      _selectedSale = list.first;
      _selectedSaleId = _selectedSale?.id;
      return;
    }

    final match = list.firstWhere(
      (s) => s.id == currentId,
      orElse: () => list.first,
    );
    _selectedSale = match;
    _selectedSaleId = match.id;
  }

  void _selectSale(SaleModel sale, {required bool showDetails}) {
    _safeSetState(() {
      _selectedSale = sale;
      _selectedSaleId = sale.id;
    });
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
        return 'Este Mes';
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
      backgroundColor: scheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = (constraints.maxWidth * 0.018).clamp(
            12.0,
            28.0,
          );
          final verticalPadding = 10.0;
          final isWide = constraints.maxWidth >= 1200;
          final detailWidth = (constraints.maxWidth * 0.28).clamp(320.0, 460.0);

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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildSalesTab(
                              listPadding: listPadding,
                              isWide: true,
                            ),
                          ),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: detailWidth,
                            child: SizedBox.expand(child: _buildDetailsPanel()),
                          ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 980;
        final horizontalPadding = (constraints.maxWidth * 0.018).clamp(
          12.0,
          20.0,
        );
        final gap = 8.0;

        final baseFieldBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        );

        final searchField = TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Buscar por código, cliente o total...',
            filled: true,
            fillColor: scheme.surface,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.trim().isNotEmpty
                ? IconButton(
                    tooltip: 'Limpiar búsqueda',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            border: baseFieldBorder,
            enabledBorder: baseFieldBorder,
            focusedBorder: baseFieldBorder.copyWith(
              borderSide: BorderSide(color: scheme.primary),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        );

        final hasActiveFilters =
            _searchQuery.trim().isNotEmpty ||
            _selectedFilter != DateFilter.thisMonth ||
            _selectedSessionId != null ||
            _statusFilter != _InvoiceStatusFilter.all ||
            (_selectedFilter == DateFilter.custom &&
                (_customDateFrom != null || _customDateTo != null));

        final statusDropdown = Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
            color: scheme.surface,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButton<_InvoiceStatusFilter>(
            value: _statusFilter,
            underline: const SizedBox(),
            isDense: true,
            items: _InvoiceStatusFilter.values
                .map(
                  (filter) => DropdownMenuItem<_InvoiceStatusFilter>(
                    value: filter,
                    child: Text(_statusFilterLabel(filter)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              _safeSetState(() {
                _statusFilter = value;
                _ensureSelection();
              });
            },
          ),
        );

        final dateDropdown = Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
            color: scheme.surface,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButton<DateFilter>(
            value: _selectedFilter,
            underline: const SizedBox(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: DateFilter.today, child: Text('Hoy')),
              DropdownMenuItem(
                value: DateFilter.yesterday,
                child: Text('Ayer'),
              ),
              DropdownMenuItem(
                value: DateFilter.thisWeek,
                child: Text('Esta semana'),
              ),
              DropdownMenuItem(
                value: DateFilter.thisMonth,
                child: Text('Este mes'),
              ),
              DropdownMenuItem(value: DateFilter.all, child: Text('Todas')),
              DropdownMenuItem(
                value: DateFilter.custom,
                child: Text('Personalizado'),
              ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              if (value == DateFilter.custom) {
                await _selectCustomDateRange();
                return;
              }
              _safeSetState(() => _selectedFilter = value);
              _loadData();
            },
          ),
        );

        final rangeButton = OutlinedButton.icon(
          onPressed: _selectCustomDateRange,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(
            _selectedFilter == DateFilter.custom
                ? _getFilterLabel(DateFilter.custom)
                : 'Rango',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: scheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        );

        final cashierDropdown = Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
            color: scheme.surface,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButton<int?>(
            value: _selectedSessionId,
            underline: const SizedBox(),
            isDense: true,
            hint: const Text('Cajero'),
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
            onChanged: (value) {
              _safeSetState(() {
                _selectedSessionId = value;
                _ensureSelection();
              });
            },
          ),
        );

        final summary = _buildHeaderSummary();

        final actionsRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            statusDropdown,
            SizedBox(width: gap),
            dateDropdown,
            SizedBox(width: gap),
            rangeButton,
            SizedBox(width: gap),
            cashierDropdown,
            if (hasActiveFilters) ...[
              SizedBox(width: gap),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _safeSetState(() {
                    _searchQuery = '';
                    _selectedFilter = DateFilter.thisMonth;
                    _customDateFrom = null;
                    _customDateTo = null;
                    _selectedSessionId = null;
                    _statusFilter = _InvoiceStatusFilter.all;
                  });
                  _loadData();
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpiar'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ],
            SizedBox(width: gap),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
            ),
            SizedBox(width: gap),
            summary,
          ],
        );

        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withOpacity(0.35),
              ),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 10,
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: _handleBack,
                          tooltip: 'Volver',
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Facturas',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Consulta, imprime y procesa devoluciones desde una sola vista.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        summary,
                      ],
                    ),
                    const SizedBox(height: 8),
                    searchField,
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: actionsRow,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.borderSoft),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _handleBack,
                            tooltip: 'Volver',
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const SizedBox(width: 4),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Facturas',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Vista compacta con devolucion integrada',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          searchField,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: summary,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: actionsRow,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
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
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Selecciona una factura para ver el resumen completo a la derecha.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
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
                          : 'Filtro: ${_statusFilterLabel(_statusFilter)}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
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
                final statusStyle = _saleStatusStyle(sale);
                final canRefund = sale.status.toUpperCase() != 'REFUNDED';

                return Material(
                  color: isSelected
                      ? AppColors.lightBlueHover.withOpacity(0.30)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectSale(sale, showDetails: !isWide),
                    hoverColor: AppColors.lightBlueHover.withOpacity(0.22),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: LayoutBuilder(
                        builder: (context, rowConstraints) {
                          final compact = rowConstraints.maxWidth < 860;
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sale.localCode,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  fontFamily: 'Inter',
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            customer,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.onSurface,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'Inter',
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _buildStatusChip(statusStyle),
                                    PopupMenuButton<_SalesRowAction>(
                                      tooltip: 'Acciones',
                                      icon: Icon(
                                        Icons.more_horiz,
                                        size: 18,
                                        color: scheme.onSurface.withOpacity(
                                          0.7,
                                        ),
                                      ),
                                      onSelected: (action) {
                                        switch (action) {
                                          case _SalesRowAction.view:
                                            _showSaleDetails(sale);
                                            break;
                                          case _SalesRowAction.refund:
                                            _showRefundDialog(sale);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: _SalesRowAction.view,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.visibility_outlined,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Ver factura'),
                                            ],
                                          ),
                                        ),
                                        if (canRefund)
                                          const PopupMenuItem(
                                            value: _SalesRowAction.refund,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons
                                                      .assignment_return_outlined,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Devolver'),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      dateFormat.format(date),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Inter',
                                          ),
                                    ),
                                    Text(
                                      _cashierLabelForSessionId(sale.sessionId),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Inter',
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
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'Inter',
                                        ),
                                    smallStyle: theme.textTheme.bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Inter',
                                          color: AppColors.textSecondary,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sale.localCode,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'Inter',
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _cashierLabelForSessionId(sale.sessionId),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Inter',
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
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  dateFormat.format(date),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Inter',
                                  ),
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
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'Inter',
                                        ),
                                    smallStyle: theme.textTheme.bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Inter',
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<_SalesRowAction>(
                                tooltip: 'Acciones',
                                icon: Icon(
                                  Icons.more_horiz,
                                  size: 18,
                                  color: scheme.onSurface.withOpacity(0.7),
                                ),
                                onSelected: (action) {
                                  switch (action) {
                                    case _SalesRowAction.view:
                                      _showSaleDetails(sale);
                                      break;
                                    case _SalesRowAction.refund:
                                      _showRefundDialog(sale);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: _SalesRowAction.view,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Ver factura'),
                                      ],
                                    ),
                                  ),
                                  if (canRefund)
                                    const PopupMenuItem(
                                      value: _SalesRowAction.refund,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.assignment_return_outlined,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Devolver'),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
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

  Widget _buildHeaderSummary() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = CurrencyDisplay.currency();

    final count = _filteredSales.length;
    final total = _filteredSales.fold<double>(0, (sum, s) => sum + s.total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.summarize_outlined,
            size: 16,
            color: scheme.onSurface.withOpacity(0.75),
          ),
          const SizedBox(width: 8),
          Text(
            'Facturas: $count',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Total: ${money.format(total)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium ?? const TextStyle(),
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

  Widget _buildSaleDetailsPanel(SaleModel? sale) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    if (sale == null) {
      return Center(
        child: Text(
          'Seleccione una factura para ver detalles',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
    final customer = sale.customerNameSnapshot ?? 'Cliente General';
    final statusStyle = _saleStatusStyle(sale);
    final canRefund = sale.status.toUpperCase() != 'REFUNDED';
    final relatedReturns = _returnsForSale(sale);
    final refundedAmount = _refundedAmountForSale(sale);
    final netAmount = (sale.total - refundedAmount).clamp(0, sale.total);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sale.localCode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                          fontSize: 22,
                        ),
                      ),
                    ),
                    _buildStatusChip(statusStyle),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  customer,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoBadge(Icons.person_outline, customer),
              _buildInfoBadge(
                Icons.point_of_sale_outlined,
                _cashierLabelForSessionId(sale.sessionId),
              ),
              _buildInfoBadge(Icons.schedule_outlined, dateFormat.format(date)),
              if (relatedReturns.isNotEmpty)
                _buildInfoBadge(
                  Icons.assignment_return_outlined,
                  '${relatedReturns.length} devolucion${relatedReturns.length == 1 ? '' : 'es'}',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Total factura',
                  value: sale.total,
                  highlight: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Devuelto',
                  value: refundedAmount,
                  highlight: relatedReturns.isEmpty
                      ? scheme.outline
                      : status.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Neto vigente',
                  value: netAmount.toDouble(),
                  highlight: canRefund ? status.success : status.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: statusStyle.background.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              canRefund
                  ? sale.status.toUpperCase() == 'PARTIAL_REFUND'
                        ? 'Factura con devolucion parcial. Puede registrar otra devolucion si corresponde.'
                        : 'Factura activa lista para consulta, impresion o devolucion.'
                  : 'Factura totalmente devuelta. Se mantiene visible para consulta y filtros.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (relatedReturns.isNotEmpty) ...[
            Text(
              'Historial de devoluciones',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...relatedReturns.take(3).map(_buildRefundEntryCard),
            const SizedBox(height: 16),
          ],
          if (canRefund) ...[
            FilledButton.icon(
              onPressed: () => _showRefundDialog(sale),
              icon: const Icon(Icons.assignment_return_outlined, size: 18),
              label: const Text('Devolver'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                textStyle: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => _showSaleDetails(sale),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Ver ticket'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _loadData(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar lista'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required double value,
    required Color highlight,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: highlight.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildMoneyText(
            amount: value,
            bigStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
            smallStyle: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundEntryCard(Map<String, dynamic> ret) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');
    final code = (ret['local_code'] as String?) ?? 'DEV-${ret['id']}';
    final total = ((ret['total'] as num?)?.toDouble() ?? 0).abs();
    final createdMs = (ret['created_at_ms'] as int?) ?? 0;
    final note = (ret['note'] as String?)?.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildMoneyText(
                amount: total,
                bigStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                smallStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dateFormat.format(DateTime.fromMillisecondsSinceEpoch(createdMs)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
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
    final saleId = sale.id;
    if (saleId == null) {
      _showError('No se puede procesar: ticket inválido (sin ID).');
      return;
    }

    try {
      final items = await SalesRepository.getItemsBySaleId(saleId);
      if (!mounted) return;

      // Evita pantalla negra por force-unwraps si existieran items corruptos.
      if (items.any((i) => i.id == null)) {
        _showError('No se puede procesar: hay productos del ticket sin ID.');
        return;
      }

      final result = await showDialog<_RefundDialogResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _RefundDialog(sale: sale, items: items),
      );

      if (result == _RefundDialogResult.refunded) {
        _showSuccess('¡Devolución procesada!');
        _loadData();
      } else if (result == _RefundDialogResult.cancelled) {
        _showSuccess('✅ Ticket cancelado y stock restaurado');
        _loadData();
      }
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _showRefundDialog(sale),
        module: 'sales/returns_list/refund_dialog',
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
                      'ITBIS (18%)',
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
                      label: const Text('Devolver'),
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

  const _RefundDialog({required this.sale, required this.items});

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final List<double> _returnQuantities;
  final _noteController = TextEditingController();
  bool _isProcessing = false;
  bool _refundAll = false;

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
    double total = 0;
    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final qty = _returnQuantities[i];
      total += qty * item.unitPrice;
    }
    if (widget.sale.itbisEnabled == 1) {
      total += total * widget.sale.itbisRate;
    }
    return total;
  }

  bool get _hasSelectedItems => _returnQuantities.any((qty) => qty > 0);

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
        _returnQuantities[i] = _refundAll ? widget.items[i].qty : 0;
      }
    });
  }

  Future<void> _processRefund() async {
    if (!_hasSelectedItems) return;

    if (!await _ensureCashAvailableForRefund(_totalReturn)) {
      return;
    }

    // Motivo obligatorio (incluye confirmación previa)
    final reason = await showRefundReasonDialog(context);
    if (!mounted) return;
    if (!mounted) return;
    if (reason == null || reason.trim().isEmpty) return;
    _noteController.text = reason.trim();

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.processReturn,
      resourceType: 'sale',
      resourceId: widget.sale.id?.toString(),
      reason: 'Procesar devolucion',
    );
    if (!mounted) return;
    if (!authorized) return;

    if (!mounted) return;
    if (!mounted) return;
    setState(() => _isProcessing = true);

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
          returnItems.add({
            'sale_item_id': saleItemId,
            'product_id': item.productId,
            'description': item.productNameSnapshot,
            'qty': qty,
            'price': item.unitPrice,
          });
        }
      }

      await ReturnsRepository.createReturn(
        originalSaleId: widget.sale.id!,
        returnItems: returnItems,
        cashSessionId: await CashRepository.getCurrentSessionId(),
        note: _noteController.text.isEmpty ? null : _noteController.text,
      );

      if (mounted) Navigator.pop(context, _RefundDialogResult.refunded);
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _processRefund,
          module: 'sales/returns_list/refund',
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelFullSale() async {
    final reason = await showRefundReasonDialog(context);
    if (reason == null || reason.trim().isEmpty) return;
    _noteController.text = reason.trim();

    final proceed = await _warnIfDifferentSession();
    if (!mounted) return;
    if (!proceed) return;

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
        reason: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (!ok) {
        throw StateError('No se pudo anular (posiblemente ya estaba anulada)');
      }

      if (mounted) Navigator.pop(context, _RefundDialogResult.cancelled);
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _cancelFullSale,
          module: 'sales/returns_list/cancel',
        );
      }
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
          maxWidth: 500,
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
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard_return_rounded,
                    color: headerText,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Procesar Devolución',
                          style: TextStyle(
                            color: headerText,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.sale.localCode,
                          style: TextStyle(
                            color: headerText.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: headerText),
                  ),
                ],
              ),
            ),

            // Seleccionar todo
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Productos',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _toggleRefundAll,
                    icon: Icon(
                      _refundAll
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                    ),
                    label: Text(
                      _refundAll ? 'Deseleccionar' : 'Seleccionar todo',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Lista de productos
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final returnQty = _returnQuantities[index];
                  final isSelected = returnQty > 0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productNameSnapshot,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? scheme.primary
                                      : scheme.onSurface,
                                ),
                              ),
                              Text(
                                '${currencyFormat.format(item.unitPrice)} × ${item.qty.toInt()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? scheme.primary.withOpacity(0.12)
                                : scheme.surfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? scheme.primary.withOpacity(0.5)
                                  : scheme.outlineVariant,
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
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                onPressed: returnQty > 0
                                    ? () => setState(() {
                                        _returnQuantities[index] =
                                            returnQty - 1;
                                        _refundAll = false;
                                      })
                                    : null,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                child: Text(
                                  '${returnQty.toInt()}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: returnQty < item.qty
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                onPressed: returnQty < item.qty
                                    ? () => setState(
                                        () => _returnQuantities[index] =
                                            returnQty + 1,
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

            // Nota
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Motivo del reembolso o anulación',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: scheme.surfaceVariant.withOpacity(0.35),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _hasSelectedItems
                    ? scheme.primary.withOpacity(0.12)
                    : scheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasSelectedItems
                      ? scheme.primary.withOpacity(0.5)
                      : scheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total a reembolsar:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        currencyFormat.format(_totalReturn),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: _hasSelectedItems
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _cancelFullSale,
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Anular'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: status.error,
                            side: BorderSide(color: status.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                            _isProcessing ? 'Procesando...' : 'Procesar',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            disabledBackgroundColor: scheme.surfaceVariant
                                .withOpacity(0.6),
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
}
