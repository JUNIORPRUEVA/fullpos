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

/// Página profesional de devoluciones y reembolsos
class ReturnsListPage extends StatefulWidget {
  const ReturnsListPage({super.key});

  @override
  State<ReturnsListPage> createState() => _ReturnsListPageState();
}

class _ReturnsListPageState extends State<ReturnsListPage>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late TabController _tabController;

  List<SaleModel> _completedSales = [];
  List<Map<String, dynamic>> _returns = [];
  List<CategoryPerformanceData> _categoryPerformance = [];
  bool _isLoading = false;
  String _searchQuery = '';
  int _loadSeq = 0;

  // Filtros de fecha
  DateFilter _selectedFilter = DateFilter.today;
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
    _tabController = TabController(length: 2, vsync: this);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
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
        _categoryPerformance = categoryPerformance;
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
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [_buildSalesTab(), _buildHistoryTab()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final gradientTheme = theme.extension<AppGradientTheme>();
    final backgroundGradient =
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
    final width = MediaQuery.sizeOf(context).width;
    final padH = (width * 0.012).clamp(10.0, 18.0);
    final padV = (width * 0.008).clamp(8.0, 14.0);
    final chipHeight = (width * 0.03).clamp(38.0, 46.0);

    return Container(
      decoration: BoxDecoration(
        gradient: backgroundGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Título y botones
            Padding(
              padding: EdgeInsets.fromLTRB(padH * 0.6, padV, padH, padV * 0.7),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _handleBack,
                    icon: Icon(Icons.arrow_back, color: headerText),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Devoluciones',
                          style: TextStyle(
                            color: headerText,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_filteredSales.length} ventas encontradas',
                          style: TextStyle(
                            color: headerText.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loadData,
                    icon: Icon(Icons.refresh, color: headerText),
                    tooltip: 'Actualizar',
                  ),
                ],
              ),
            ),

            // Filtros de fecha
            Container(
              height: chipHeight,
              margin: EdgeInsets.symmetric(horizontal: padH),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(DateFilter.today),
                  _buildFilterChip(DateFilter.yesterday),
                  _buildFilterChip(DateFilter.thisWeek),
                  _buildFilterChip(DateFilter.thisMonth),
                  _buildFilterChip(DateFilter.all),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(
                      Icons.date_range,
                      size: 18,
                      color: _selectedFilter == DateFilter.custom
                          ? headerText
                          : scheme.primary,
                    ),
                    label: Text(
                      _selectedFilter == DateFilter.custom
                          ? _getFilterLabel(DateFilter.custom)
                          : 'Rango',
                      style: TextStyle(
                        color: _selectedFilter == DateFilter.custom
                            ? headerText
                            : scheme.primary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    backgroundColor: _selectedFilter == DateFilter.custom
                        ? scheme.primary
                        : scheme.surface,
                    onPressed: _selectCustomDateRange,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Búsqueda
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padH),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: headerText.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                  style: TextStyle(color: headerText, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por código o cliente...',
                    hintStyle: TextStyle(color: headerText.withOpacity(0.6)),
                    prefixIcon: Icon(
                      Icons.search,
                      color: headerText.withOpacity(0.7),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: headerText.withOpacity(0.7),
                              size: 18,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Tabs
            Container(
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.25),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: headerText,
                indicatorWeight: 3,
                labelColor: headerText,
                unselectedLabelColor: headerText.withOpacity(0.6),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.receipt_long, size: 18),
                    text: 'Ventas',
                    height: 50,
                  ),
                  Tab(
                    icon: Icon(Icons.history, size: 18),
                    text: 'Historial',
                    height: 50,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(DateFilter filter) {
    final isSelected = _selectedFilter == filter;
    final selectedColor = scheme.primary;
    final selectedText = ColorUtils.ensureReadableColor(
      scheme.onPrimary,
      selectedColor,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          _getFilterLabel(filter),
          style: TextStyle(
            color: isSelected ? selectedText : scheme.primary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        selected: isSelected,
        selectedColor: selectedColor,
        backgroundColor: scheme.surface,
        onSelected: (selected) {
          if (selected) {
            setState(() => _selectedFilter = filter);
            _loadData();
          }
        },
      ),
    );
  }

  Widget _buildSalesTab() {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    );
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final width = MediaQuery.sizeOf(context).width;
    final padH = (width * 0.012).clamp(10.0, 18.0);
    final padV = (width * 0.01).clamp(8.0, 16.0);

    if (_filteredSales.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
        children: [
          _buildCategorySummaryCard(
            title: 'Ventas y devoluciones por categoria',
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 80,
                  color: scheme.onSurfaceVariant.withOpacity(0.35),
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty
                      ? 'No hay ventas en este periodo'
                      : 'No se encontraron resultados',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Prueba cambiando el filtro de fecha',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
      itemCount: _filteredSales.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: EdgeInsets.only(bottom: padV),
            child: _buildCategorySummaryCard(
              title: 'Ventas y devoluciones por categoria',
            ),
          );
        }

        final sale = _filteredSales[index - 1];
        final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
        final hasPartialRefund = sale.status == 'PARTIAL_REFUND';
        final accent = hasPartialRefund ? status.warning : status.success;
        final badgeBg = accent.withOpacity(0.16);
        final badgeBorder = accent.withOpacity(0.45);
        final badgeText = ColorUtils.ensureReadableColor(accent, badgeBg);
        return Card(
          margin: EdgeInsets.only(bottom: padV * 0.6),
          elevation: 1.5,
          shadowColor: Theme.of(context).shadowColor.withOpacity(0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
          ),
          child: InkWell(
            onTap: () => _showSaleDetails(sale),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Icono
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: badgeBorder),
                    ),
                    child: Icon(
                      hasPartialRefund ? Icons.replay : Icons.receipt_outlined,
                      color: accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              sale.localCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (hasPartialRefund) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Parcial',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: badgeText,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                sale.customerNameSnapshot ?? 'Cliente General',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: scheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dateFormat.format(date),
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Total y acciones
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currencyFormat.format(sale.total),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Ver ticket
                          InkWell(
                            onTap: () => _showSaleDetails(sale),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.visibility,
                                size: 18,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Devolver
                          InkWell(
                            onTap: () => _showRefundDialog(sale),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: scheme.primary.withOpacity(0.6),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.keyboard_return,
                                    size: 14,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Devolver',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildHistoryTab() {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    );
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final width = MediaQuery.sizeOf(context).width;
    final padH = (width * 0.012).clamp(10.0, 18.0);
    final padV = (width * 0.01).clamp(8.0, 16.0);

    if (_returns.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
        children: [
          _buildCategorySummaryCard(title: 'Historial por categoria'),
          const SizedBox(height: 24),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 80,
                  color: scheme.onSurfaceVariant.withOpacity(0.35),
                ),
                const SizedBox(height: 16),
                Text(
                  'No hay devoluciones en este per?odo',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
      itemCount: _returns.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: EdgeInsets.only(bottom: padV),
            child: _buildCategorySummaryCard(title: 'Historial por categoria'),
          );
        }

        final ret = _returns[index - 1];
        final date = DateTime.fromMillisecondsSinceEpoch(
          ret['created_at_ms'] as int,
        );
        final total = (ret['total'] as num?)?.toDouble().abs() ?? 0.0;
        final accent = status.warning;
        final badgeBg = accent.withOpacity(0.16);
        final badgeBorder = accent.withOpacity(0.45);

        return Card(
          margin: EdgeInsets.only(bottom: padV * 0.6),
          elevation: 1.5,
          shadowColor: Theme.of(context).shadowColor.withOpacity(0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Icon(
                    Icons.keyboard_return_rounded,
                    color: accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ret['local_code'] ?? 'DEV-${ret['id']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ret['customer_name_snapshot'] ??
                                  'Cliente General',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFormat.format(date),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                      if ((ret['note'] as String?)?.trim().isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.comment_outlined,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  (ret['note'] as String).trim(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    currencyFormat.format(total),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildCategorySummaryCard({required String title}) {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.category, color: scheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_categoryPerformance.isEmpty)
            Text(
              'No hay movimientos por categoria en este periodo.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Categoria',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Ventas',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Devol.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Neto',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _categoryPerformance.length,
              separatorBuilder: (_, _) => Divider(
                height: 16,
                color: scheme.outlineVariant.withOpacity(0.6),
              ),
              itemBuilder: (context, index) {
                final item = _categoryPerformance[index];
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.category,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.itemsSold.toInt()} vendidos ? ${item.itemsRefunded.toInt()} devueltos',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        currencyFormat.format(item.sales),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        currencyFormat.format(item.refunds),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        currencyFormat.format(item.netSales),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
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
