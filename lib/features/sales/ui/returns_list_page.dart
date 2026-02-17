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

/// Página profesional de devoluciones y reembolsos
class ReturnsListPage extends StatefulWidget {
  const ReturnsListPage({super.key});

  @override
  State<ReturnsListPage> createState() => _ReturnsListPageState();
}

class _ReturnsListPageState extends State<ReturnsListPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _activeTab = 0; // 0: Ventas | 1: Historial

  SaleModel? _selectedSale;
  int? _selectedSaleId;

  Map<String, dynamic>? _selectedReturn;
  int? _selectedReturnId;

  List<SaleModel> _completedSales = [];
  List<Map<String, dynamic>> _returns = [];
  bool _isLoading = false;
  String _searchQuery = '';
  int _loadSeq = 0;

  // Filtros de fecha
  DateFilter _selectedFilter = DateFilter.thisMonth;
  DateTime? _customDateFrom;
  DateTime? _customDateTo;

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
              query: _searchQuery.isNotEmpty ? _searchQuery : null,
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

      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() {
        _completedSales = sales
            .where(
              (s) =>
                  s.kind == 'invoice' &&
                  s.status != 'cancelled' &&
                  s.status != 'REFUNDED',
            )
            .toList();
        _returns = returns;

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
    if (_searchQuery.isEmpty) return _completedSales;
    final query = _searchQuery.toLowerCase();
    return _completedSales.where((sale) {
      return sale.localCode.toLowerCase().contains(query) ||
          (sale.customerNameSnapshot?.toLowerCase().contains(query) ?? false) ||
          sale.total.toString().contains(query);
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

  void _setActiveTab(int index) {
    if (index == _activeTab) return;
    _safeSetState(() {
      _activeTab = index;
      _ensureSelection();
    });
  }

  void _ensureSelection() {
    if (_activeTab == 0) {
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
      return;
    }

    if (_returns.isEmpty) {
      _selectedReturn = null;
      _selectedReturnId = null;
      return;
    }

    final currentId = _selectedReturnId;
    if (currentId == null) {
      _selectedReturn = _returns.first;
      _selectedReturnId = (_selectedReturn?['id'] as int?);
      return;
    }

    final match = _returns.firstWhere(
      (r) => (r['id'] as int?) == currentId,
      orElse: () => _returns.first,
    );
    _selectedReturn = match;
    _selectedReturnId = (match['id'] as int?);
  }

  void _selectSale(SaleModel sale, {required bool showDetails}) {
    _safeSetState(() {
      _activeTab = 0;
      _selectedSale = sale;
      _selectedSaleId = sale.id;
    });
    if (showDetails) {
      _showSaleDetails(sale);
    }
  }

  void _selectReturn(Map<String, dynamic> ret, {required bool showDetails}) {
    _safeSetState(() {
      _activeTab = 1;
      _selectedReturn = ret;
      _selectedReturnId = (ret['id'] as int?);
    });
    if (showDetails) {
      _showReturnDetails(ret);
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

    // Esta pantalla suele abrirse con context.go('/returns-list'),
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
          final itemSpacing = 8.0;
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
                            child: _activeTab == 0
                                ? _buildSalesTab(
                                    listPadding: listPadding,
                                    itemSpacing: itemSpacing,
                                    isWide: true,
                                  )
                                : _buildHistoryTab(
                                    listPadding: listPadding,
                                    itemSpacing: itemSpacing,
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
                    : _activeTab == 0
                    ? _buildSalesTab(
                        listPadding: listPadding,
                        itemSpacing: itemSpacing,
                        isWide: false,
                      )
                    : _buildHistoryTab(
                        listPadding: listPadding,
                        itemSpacing: itemSpacing,
                        isWide: false,
                      ),
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
          (_selectedFilter == DateFilter.custom &&
            (_customDateFrom != null || _customDateTo != null));

        final tabToggle = ToggleButtons(
          isSelected: [_activeTab == 0, _activeTab == 1],
          onPressed: (i) => _setActiveTab(i),
          borderRadius: BorderRadius.circular(10),
          constraints: const BoxConstraints(minHeight: 40),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Ventas'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Historial'),
            ),
          ],
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

        final summary = _buildHeaderSummary();

        final actionsRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tabToggle,
            SizedBox(width: gap),
            dateDropdown,
            SizedBox(width: gap),
            rangeButton,
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
          color: scheme.surfaceContainerHighest,
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
                          child: Text(
                            'Devoluciones',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
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
                  children: [
                    IconButton(
                      onPressed: _handleBack,
                      tooltip: 'Volver',
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Devoluciones',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(flex: 3, child: searchField),
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
    required double itemSpacing,
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    final sales = _filteredSales;
    if (sales.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.trim().isEmpty
              ? 'No hay ventas en este periodo'
              : 'No se encontraron resultados',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: listPadding,
      itemCount: sales.length,
      separatorBuilder: (context, index) => SizedBox(height: itemSpacing),
      itemBuilder: (context, index) {
        final sale = sales[index];
        final isSelected = sale.id != null && sale.id == _selectedSaleId;
        final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
        final customer = sale.customerNameSnapshot ?? 'Cliente General';
        final isPartial = sale.status == 'PARTIAL_REFUND';
        final statusLabel = isPartial ? 'PARCIAL' : 'OK';
        const statusBg = Color(0xFFDCFCE7);
        const statusFg = Color(0xFF166534);

        return Material(
          color: isSelected
              ? AppColors.lightBlueHover.withOpacity(0.55)
              : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _selectSale(sale, showDetails: !isWide),
            borderRadius: BorderRadius.circular(12),
            hoverColor: AppColors.lightBlueHover.withOpacity(0.65),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      sale.localCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: Text(
                      customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Inter',
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Text(
                      dateFormat.format(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Inter',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildMoneyText(
                        amount: sale.total,
                        bigStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                        smallStyle: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusFg,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<_SalesRowAction>(
                    tooltip: 'Acciones',
                    icon: Icon(
                      Icons.more_vert,
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
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _SalesRowAction.view,
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Ver ticket'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: _SalesRowAction.refund,
                        child: Row(
                          children: [
                            Icon(Icons.assignment_return_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Devolver'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab({
    required EdgeInsets listPadding,
    required double itemSpacing,
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    if (_returns.isEmpty) {
      return Center(
        child: Text(
          'No hay devoluciones en este periodo',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: listPadding,
      itemCount: _returns.length,
      separatorBuilder: (context, index) => SizedBox(height: itemSpacing),
      itemBuilder: (context, index) {
        final ret = _returns[index];
        final isSelected =
            (ret['id'] as int?) != null &&
            (ret['id'] as int?) == _selectedReturnId;
        final code = (ret['local_code'] as String?) ?? 'DEV-${ret['id']}';
        final customer =
            (ret['customer_name_snapshot'] as String?) ?? 'Cliente General';
        final createdMs = (ret['created_at_ms'] as int?) ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(createdMs);
        final total = (ret['total'] as num?)?.toDouble().abs() ?? 0.0;
        final hasNote = (ret['note'] as String?)?.trim().isNotEmpty ?? false;

        return Material(
          color: isSelected
              ? AppColors.lightBlueHover.withOpacity(0.55)
              : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _selectReturn(ret, showDetails: !isWide),
            borderRadius: BorderRadius.circular(12),
            hoverColor: AppColors.lightBlueHover.withOpacity(0.65),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: Text(
                      customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Inter',
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Text(
                      dateFormat.format(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Inter',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildMoneyText(
                        amount: total,
                        bigStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                        smallStyle: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (hasNote)
                    Icon(
                      Icons.comment_outlined,
                      size: 18,
                      color: scheme.onSurface.withOpacity(0.65),
                    )
                  else
                    const SizedBox(width: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderSummary() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
      decimalDigits: 2,
    );

    final count = _activeTab == 0 ? _filteredSales.length : _returns.length;
    final total = _activeTab == 0
        ? _filteredSales.fold<double>(0, (sum, s) => sum + s.total)
        : _returns.fold<double>(
            0,
            (sum, r) => sum + ((r['total'] as num?)?.toDouble().abs() ?? 0.0),
          );

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
            _activeTab == 0 ? 'Ventas: $count' : 'Devoluciones: $count',
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

    final child = _activeTab == 0
        ? _buildSaleDetailsPanel(_selectedSale)
        : _buildReturnDetailsPanel(_selectedReturn);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: scheme.shadow.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderSoft),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium ?? const TextStyle(),
          child: child,
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
          'Seleccione una venta para ver detalles',
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
    final isPartial = sale.status == 'PARTIAL_REFUND';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sale.localCode,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            customer,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              fontFamily: 'Inter',
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: scheme.onSurface.withOpacity(0.65),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dateFormat.format(date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Inter',
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.borderSoft, height: 16),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Row(
              children: [
                Text(
                  'Total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    fontFamily: 'Inter',
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                _buildMoneyText(
                  amount: sale.total,
                  bigStyle: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 23,
                    fontFamily: 'Inter',
                  ),
                  smallStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (isPartial ? status.warning : status.success).withOpacity(
                0.10,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (isPartial ? status.warning : status.success)
                    .withOpacity(0.35),
              ),
            ),
            child: Text(
              isPartial ? 'Devolución parcial detectada' : 'Venta completada',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          OutlinedButton.icon(
            onPressed: () => _showSaleDetails(sale),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Ver ticket'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
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

  Widget _buildReturnDetailsPanel(Map<String, dynamic>? ret) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    if (ret == null) {
      return Center(
        child: Text(
          'Seleccione una devolución para ver detalles',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final code = (ret['local_code'] as String?) ?? 'DEV-${ret['id']}';
    final customer =
        (ret['customer_name_snapshot'] as String?) ?? 'Cliente General';
    final createdMs = (ret['created_at_ms'] as int?) ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(createdMs);
    final total = (ret['total'] as num?)?.toDouble().abs() ?? 0.0;
    final note = (ret['note'] as String?)?.trim();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            customer,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              fontFamily: 'Inter',
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: scheme.onSurface.withOpacity(0.65),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dateFormat.format(date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Inter',
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.borderSoft, height: 16),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Row(
              children: [
                Text(
                  'Total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    fontFamily: 'Inter',
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                _buildMoneyText(
                  amount: total,
                  bigStyle: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 23,
                    fontFamily: 'Inter',
                  ),
                  smallStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Nota',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(note),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _showReturnDetails(ret),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Ver detalles'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoneyText({
    required double amount,
    required TextStyle? bigStyle,
    required TextStyle? smallStyle,
  }) {
    final whole = amount.truncate();
    final decimal = ((amount - whole) * 100).round().abs().toString().padLeft(2, '0');
    final formatter = NumberFormat.decimalPattern('es_DO');

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: 'RD\$ ', style: smallStyle),
          TextSpan(text: formatter.format(whole), style: bigStyle),
          TextSpan(text: '.$decimal', style: smallStyle),
        ],
      ),
    );
  }

  Future<void> _showReturnDetails(Map<String, dynamic> ret) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
      decimalDigits: 2,
    );
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    final code = (ret['local_code'] as String?) ?? 'DEV-${ret['id']}';
    final customer =
        (ret['customer_name_snapshot'] as String?) ?? 'Cliente General';
    final createdMs = (ret['created_at_ms'] as int?) ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(createdMs);
    final total = (ret['total'] as num?)?.toDouble().abs() ?? 0.0;
    final note = (ret['note'] as String?)?.trim();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(code),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  dateFormat.format(date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Total: ${money.format(total)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Nota:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(note),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
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
    final currencyFormat = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    );
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
          'Disponible en caja: RD\$ ${available.toStringAsFixed(2)}\n'
          'Reembolso requerido: RD\$ ${amount.toStringAsFixed(2)}\n\n'
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
              'Sigue faltando efectivo. Disponible: RD\$ ${refreshed.expectedCash.toStringAsFixed(2)}',
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
        title: const Text('Ticket de otro turno'),
        content: Text(
          'Este ticket se creó en el turno #$originalId ($originalUser).\n'
          'Tu turno actual es #${currentSession.id} (${currentSession.userName}).\n\n'
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
    final currencyFormat = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    );
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
