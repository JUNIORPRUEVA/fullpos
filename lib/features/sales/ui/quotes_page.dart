import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../data/quote_model.dart';
import '../data/quote_to_ticket_converter.dart';
import '../data/quotes_repository.dart';
import '../data/settings_repository.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/printing/quote_printer.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/utils/currency_display.dart';
import '../../../theme/app_colors.dart' as ui_colors;
import 'widgets/compact_quote_row.dart';

enum _QuoteSort {
  newest,
  oldest,
  highest,
  lowest,
}

enum _QuoteDatePreset {
  all,
  today,
  last7Days,
  last30Days,
  thisMonth,
}

class QuotesPage extends StatefulWidget {
  const QuotesPage({super.key});

  @override
  State<QuotesPage> createState() => _QuotesPageState();
}

class _QuotesPageState extends State<QuotesPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _quoteItemsScrollController = ScrollController();

  List<QuoteDetailDto> _quotes = <QuoteDetailDto>[];
  List<QuoteDetailDto> _filteredQuotes = <QuoteDetailDto>[];

  QuoteDetailDto? _selectedQuote;
  int? _selectedQuoteId;

  bool _isLoading = false;
  bool _showFilterPanel = false;
  bool _showDetailsPanel = false;

  String _selectedStatus = 'ALL';
  _QuoteSort _sort = _QuoteSort.newest;
  _QuoteDatePreset _datePreset = _QuoteDatePreset.all;

  int _loadSequence = 0;

  static const double _pageMaxWidth = 1480;
  static const double _brandRadius = 10;

  ThemeData get _theme => Theme.of(context);
  ColorScheme get _scheme => _theme.colorScheme;

  AppStatusTheme get _status =>
      _theme.extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: _scheme.primary,
        warning: _scheme.tertiary,
        error: _scheme.error,
        info: _scheme.secondary,
      );

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    _loadQuotes();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applyFilters)
      ..dispose();
    _quoteItemsScrollController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

  Future<void> _loadQuotes() async {
    final int sequence = ++_loadSequence;
    _safeSetState(() => _isLoading = true);

    try {
      final quotes = await DbHardening.instance.runDbSafe<List<QuoteDetailDto>>(
        () => QuotesRepository().listQuotes(),
        stage: 'sales/quotes/load',
      );

      if (!mounted || sequence != _loadSequence) return;

      _safeSetState(() {
        _quotes = quotes;
        _isLoading = false;
      });

      _applyFilters();
    } catch (error, stackTrace) {
      if (!mounted || sequence != _loadSequence) return;

      _safeSetState(() => _isLoading = false);

      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        onRetry: _loadQuotes,
        module: 'sales/quotes/load',
      );
    }
  }

  void _applyFilters() {
    final String query = _searchController.text.trim().toLowerCase();
    final DateTime now = DateTime.now();

    DateTime? dateFrom;

    switch (_datePreset) {
      case _QuoteDatePreset.all:
        dateFrom = null;
        break;
      case _QuoteDatePreset.today:
        dateFrom = DateTime(now.year, now.month, now.day);
        break;
      case _QuoteDatePreset.last7Days:
        dateFrom = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        break;
      case _QuoteDatePreset.last30Days:
        dateFrom = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
        break;
      case _QuoteDatePreset.thisMonth:
        dateFrom = DateTime(now.year, now.month);
        break;
    }

    final List<QuoteDetailDto> result = _quotes.where((detail) {
      final quote = detail.quote;
      final createdAt =
          DateTime.fromMillisecondsSinceEpoch(quote.createdAtMs);

      final String code = quote.id == null
          ? ''
          : 'cot-${quote.id.toString().padLeft(5, '0')}';

      final bool matchesSearch = query.isEmpty ||
          detail.clientName.toLowerCase().contains(query) ||
          (detail.clientPhone ?? '').toLowerCase().contains(query) ||
          (detail.clientRnc ?? '').toLowerCase().contains(query) ||
          code.contains(query) ||
          quote.total.toStringAsFixed(2).contains(query);

      final bool matchesStatus =
          _selectedStatus == 'ALL' || quote.status == _selectedStatus;

      final bool matchesDate =
          dateFrom == null || !createdAt.isBefore(dateFrom);

      return matchesSearch && matchesStatus && matchesDate;
    }).toList();

    switch (_sort) {
      case _QuoteSort.newest:
        result.sort(
          (a, b) => b.quote.createdAtMs.compareTo(a.quote.createdAtMs),
        );
        break;
      case _QuoteSort.oldest:
        result.sort(
          (a, b) => a.quote.createdAtMs.compareTo(b.quote.createdAtMs),
        );
        break;
      case _QuoteSort.highest:
        result.sort((a, b) => b.quote.total.compareTo(a.quote.total));
        break;
      case _QuoteSort.lowest:
        result.sort((a, b) => a.quote.total.compareTo(b.quote.total));
        break;
    }

    _safeSetState(() {
      _filteredQuotes = result;

      if (_selectedQuoteId != null) {
        final int selectedIndex = result.indexWhere(
          (item) => item.quote.id == _selectedQuoteId,
        );

        if (selectedIndex >= 0) {
          _selectedQuote = result[selectedIndex];
        } else {
          _selectedQuote = null;
          _selectedQuoteId = null;
          _showDetailsPanel = false;
        }
      }
    });
  }

  void _resetFilters() {
    _searchController.clear();

    _safeSetState(() {
      _selectedStatus = 'ALL';
      _sort = _QuoteSort.newest;
      _datePreset = _QuoteDatePreset.all;
    });

    _applyFilters();
  }

  void _openFilterPanel() {
    _safeSetState(() {
      _showDetailsPanel = false;
      _showFilterPanel = true;
    });
  }

  void _openQuoteDetails(QuoteDetailDto quoteDetail) {
    _safeSetState(() {
      _selectedQuote = quoteDetail;
      _selectedQuoteId = quoteDetail.quote.id;
      _showFilterPanel = false;
      _showDetailsPanel = true;
    });
  }

  void _closeSidePanels() {
    _safeSetState(() {
      _showFilterPanel = false;
      _showDetailsPanel = false;
    });
  }

  double _sidePanelWidth(double screenWidth, {required bool details}) {
    if (screenWidth < 760) {
      return screenWidth;
    }

    if (details) {
      return (screenWidth * 0.40).clamp(520.0, 680.0);
    }

    return (screenWidth * 0.30).clamp(390.0, 480.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double availableWidth = constraints.maxWidth;
          final double detailWidth =
              _sidePanelWidth(availableWidth, details: true);
          final double filterWidth =
              _sidePanelWidth(availableWidth, details: false);

          return Column(
            children: [
              _buildCleanToolbar(),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildMainContent(),

                    if (_showFilterPanel || _showDetailsPanel)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeSidePanels,
                          child: Container(
                            color: Colors.black.withOpacity(0.055),
                          ),
                        ),
                      ),

                    if (_showFilterPanel)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: filterWidth,
                        child: _buildFilterPanel(),
                      ),

                    if (_showDetailsPanel)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: detailWidth,
                        child: _buildDetailsSideSheet(_selectedQuote),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCleanToolbar() {
    return Container(
      height: 66,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: ui_colors.AppColors.borderSoft),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Buscar por cliente, teléfono, RNC, código o total...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: ui_colors.AppColors.primaryBlue,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                              ),
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_brandRadius),
                        borderSide: const BorderSide(
                          color: ui_colors.AppColors.borderSoft,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_brandRadius),
                        borderSide: const BorderSide(
                          color: ui_colors.AppColors.primaryBlue,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _openFilterPanel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    backgroundColor:
                        _hasActiveAdvancedFilters
                            ? const Color(0xFFEAF2FF)
                            : Colors.white,
                    side: BorderSide(
                      color: _hasActiveAdvancedFilters
                          ? ui_colors.AppColors.primaryBlue
                          : ui_colors.AppColors.borderSoft,
                    ),
                    minimumSize: const Size(106, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_brandRadius),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text(
                    'Filtrar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildQuotesTotalsSummary(),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _isLoading ? null : _loadQuotes,
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    backgroundColor: const Color(0xFFF8FAFC),
                    side: const BorderSide(
                      color: ui_colors.AppColors.borderSoft,
                    ),
                    minimumSize: const Size(42, 42),
                    maximumSize: const Size(42, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_brandRadius),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => context.go('/sales'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ui_colors.AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(146, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_brandRadius),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text(
                    'Nueva cotización',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasActiveAdvancedFilters =>
      _selectedStatus != 'ALL' ||
      _sort != _QuoteSort.newest ||
      _datePreset != _QuoteDatePreset.all;

  Widget _buildQuotesTotalsSummary() {
    final int count = _filteredQuotes.length;
    final double total = _filteredQuotes.fold<double>(
      0,
      (sum, item) => sum + item.quote.total,
    );

    final money = CurrencyDisplay.currency();

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_brandRadius),
        border: Border.all(color: ui_colors.AppColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.request_quote_outlined,
            size: 17,
            color: ui_colors.AppColors.primaryBlue,
          ),
          const SizedBox(width: 8),
          Text(
            '$count cotizaciones',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 11),
            color: ui_colors.AppColors.borderSoft,
          ),
          Text(
            money.format(total),
            style: const TextStyle(
              color: ui_colors.AppColors.primaryBlue,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.92,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
            child: _buildQuotesList(),
          ),
        ),
      ),
    );
  }

  Widget _buildQuotesList() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    if (_filteredQuotes.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ui_colors.AppColors.borderSoft),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.request_quote_outlined,
                    size: 29,
                    color: ui_colors.AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _quotes.isEmpty
                      ? 'Aún no hay cotizaciones'
                      : 'No encontramos resultados',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _quotes.isEmpty
                      ? 'Crea una cotización desde Ventas y aparecerá aquí.'
                      : 'Ajusta la búsqueda o limpia los filtros.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ui_colors.AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 18),
                if (_quotes.isEmpty)
                  FilledButton.icon(
                    onPressed: () => context.go('/sales'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Crear cotización'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Limpiar filtros'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ui_colors.AppColors.borderSoft),
      ),
      child: Column(
        children: [
          _buildListHeader(),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _filteredQuotes.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 1,
                color: ui_colors.AppColors.borderSoft.withOpacity(0.72),
              ),
              itemBuilder: (context, index) {
                final detail = _filteredQuotes[index];
                final bool isSelected =
                    detail.quote.id == _selectedQuoteId &&
                    _showDetailsPanel;

                return CompactQuoteRow(
                  quoteDetail: detail,
                  isSelected: isSelected,
                  onTap: () => _openQuoteDetails(detail),
                  onWhatsApp: () => _shareWhatsApp(detail),
                  onPdf: () => _viewPDF(detail),
                  onDownload: () => _downloadPDF(detail),
                  onDuplicate: () => _duplicateQuote(detail),
                  onDelete: () => _deleteQuote(detail),
                  onConvertToTicket: () => _convertToTicket(detail),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    const style = TextStyle(
      color: Color(0xFF64748B),
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.35,
      fontFamily: 'Inter',
    );

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: ui_colors.AppColors.borderSoft),
        ),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('CÓDIGO', style: style)),
          SizedBox(width: 16),
          Expanded(flex: 5, child: Text('CLIENTE', style: style)),
          SizedBox(width: 16),
          Expanded(flex: 3, child: Text('FECHA', style: style)),
          SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              'TOTAL',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          SizedBox(width: 12),
          SizedBox(width: 82, child: Text('ESTADO', style: style)),
          SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Material(
      color: Colors.white,
      elevation: 18,
      shadowColor: Colors.black.withOpacity(0.15),
      child: Column(
        children: [
          _buildSidePanelHeader(
            icon: Icons.tune_rounded,
            title: 'Filtrar cotizaciones',
            subtitle: 'Organiza y encuentra resultados con precisión.',
            onClose: _closeSidePanels,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _filterLabel('Estado'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    isExpanded: true,
                    decoration: _filterInputDecoration(),
                    items: const [
                      DropdownMenuItem(
                        value: 'ALL',
                        child: Text('Todos los estados'),
                      ),
                      DropdownMenuItem(
                        value: 'OPEN',
                        child: Text('Abierta'),
                      ),
                      DropdownMenuItem(
                        value: 'PASSED_TO_TICKET',
                        child: Text('Pasada a ticket'),
                      ),
                      DropdownMenuItem(
                        value: 'TICKET',
                        child: Text('Ticket'),
                      ),
                      DropdownMenuItem(
                        value: 'CONVERTED',
                        child: Text('Convertida'),
                      ),
                      DropdownMenuItem(
                        value: 'CANCELLED',
                        child: Text('Cancelada'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _safeSetState(() => _selectedStatus = value);
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 20),
                  _filterLabel('Período'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_QuoteDatePreset>(
                    initialValue: _datePreset,
                    isExpanded: true,
                    decoration: _filterInputDecoration(),
                    items: const [
                      DropdownMenuItem(
                        value: _QuoteDatePreset.all,
                        child: Text('Todas las fechas'),
                      ),
                      DropdownMenuItem(
                        value: _QuoteDatePreset.today,
                        child: Text('Hoy'),
                      ),
                      DropdownMenuItem(
                        value: _QuoteDatePreset.last7Days,
                        child: Text('Últimos 7 días'),
                      ),
                      DropdownMenuItem(
                        value: _QuoteDatePreset.last30Days,
                        child: Text('Últimos 30 días'),
                      ),
                      DropdownMenuItem(
                        value: _QuoteDatePreset.thisMonth,
                        child: Text('Este mes'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _safeSetState(() => _datePreset = value);
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 20),
                  _filterLabel('Ordenar'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_QuoteSort>(
                    initialValue: _sort,
                    isExpanded: true,
                    decoration: _filterInputDecoration(),
                    items: const [
                      DropdownMenuItem(
                        value: _QuoteSort.newest,
                        child: Text('Más recientes'),
                      ),
                      DropdownMenuItem(
                        value: _QuoteSort.oldest,
                        child: Text('Más antiguas'),
                      ),
                      DropdownMenuItem(
                        value: _QuoteSort.highest,
                        child: Text('Mayor total'),
                      ),
                      DropdownMenuItem(
                        value: _QuoteSort.lowest,
                        child: Text('Menor total'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _safeSetState(() => _sort = value);
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: ui_colors.AppColors.borderSoft,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resultados actuales',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_filteredQuotes.length} cotizaciones',
                          style: const TextStyle(
                            color: Color(0xFF172033),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: ui_colors.AppColors.borderSoft),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetFilters,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_brandRadius),
                      ),
                    ),
                    child: const Text('Limpiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _closeSidePanels,
                    style: FilledButton.styleFrom(
                      backgroundColor: ui_colors.AppColors.primaryBlue,
                      minimumSize: const Size(0, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_brandRadius),
                      ),
                    ),
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _filterInputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_brandRadius),
        borderSide: const BorderSide(
          color: ui_colors.AppColors.borderSoft,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_brandRadius),
        borderSide: const BorderSide(
          color: ui_colors.AppColors.primaryBlue,
          width: 1.2,
        ),
      ),
    );
  }

  Widget _filterLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
    );
  }

  Widget _buildDetailsSideSheet(QuoteDetailDto? quoteDetail) {
    if (quoteDetail == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.white,
      elevation: 18,
      shadowColor: Colors.black.withOpacity(0.15),
      child: Column(
        children: [
          _buildSidePanelHeader(
            icon: Icons.request_quote_outlined,
            title: 'Detalle de cotización',
            subtitle: 'Información, productos, totales y acciones.',
            onClose: _closeSidePanels,
          ),
          Expanded(
            child: _buildQuoteDetailsPanel(quoteDetail),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanelHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onClose,
  }) {
    return Container(
      height: 76,
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: ui_colors.AppColors.borderSoft),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: ui_colors.AppColors.primaryBlue,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11.5,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              backgroundColor: const Color(0xFFF8FAFC),
              side: const BorderSide(
                color: ui_colors.AppColors.borderSoft,
              ),
            ),
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteDetailsPanel(QuoteDetailDto detail) {
    final quote = detail.quote;
    final DateTime createdAt =
        DateTime.fromMillisecondsSinceEpoch(quote.createdAtMs);
    final String createdLabel =
        DateFormat('dd/MM/yyyy · HH:mm').format(createdAt);
    final money = CurrencyDisplay.currency();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildQuoteCodeChip(quote.id),
                    const SizedBox(width: 8),
                    _buildStatusChip(quote.status),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  detail.clientName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  createdLabel,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    fontFamily: 'Inter',
                  ),
                ),
                if ((detail.clientPhone ?? '').trim().isNotEmpty ||
                    (detail.clientRnc ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if ((detail.clientPhone ?? '').trim().isNotEmpty)
                        _buildInfoPill(
                          Icons.phone_outlined,
                          detail.clientPhone!.trim(),
                        ),
                      if ((detail.clientRnc ?? '').trim().isNotEmpty)
                        _buildInfoPill(
                          Icons.badge_outlined,
                          detail.clientRnc!.trim(),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                _sectionTitle('Productos (${detail.items.length})'),
                const SizedBox(height: 10),
                _buildProductsTable(detail),
                if ((quote.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('Notas'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: ui_colors.AppColors.borderSoft,
                      ),
                    ),
                    child: Text(
                      quote.notes!.trim(),
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13,
                        height: 1.45,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _sectionTitle('Totales'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: ui_colors.AppColors.borderSoft,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildTotalsRow(
                        'Subtotal',
                        money.format(quote.subtotal),
                      ),
                      const SizedBox(height: 8),
                      _buildTotalsRow(
                        'Descuento',
                        quote.discountTotal > 0
                            ? '-${money.format(quote.discountTotal)}'
                            : money.format(0),
                      ),
                      const SizedBox(height: 8),
                      _buildTotalsRow(
                        quote.itbisEnabled ? 'ITBIS' : 'ITBIS (No aplica)',
                        quote.itbisEnabled
                            ? money.format(quote.itbisAmount)
                            : '—',
                        muted: !quote.itbisEnabled,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(
                          height: 1,
                          color: ui_colors.AppColors.borderSoft,
                        ),
                      ),
                      _buildTotalsRow(
                        'Total',
                        money.format(quote.total),
                        isTotal: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildDetailsActions(detail),
      ],
    );
  }

  Widget _buildQuoteCodeChip(int? quoteId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ui_colors.AppColors.borderSoft),
      ),
      child: Text(
        quoteId == null
            ? 'COT-—'
            : 'COT-${quoteId.toString().padLeft(5, '0')}',
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color background;
    Color foreground;

    switch (status) {
      case 'PASSED_TO_TICKET':
      case 'TICKET':
        background = const Color(0xFFFFF7E6);
        foreground = const Color(0xFF9A5A00);
        break;
      case 'CONVERTED':
        background = const Color(0xFFECFDF3);
        foreground = const Color(0xFF027A48);
        break;
      case 'CANCELLED':
        background = const Color(0xFFFEF3F2);
        foreground = const Color(0xFFB42318);
        break;
      default:
        background = const Color(0xFFF1F5F9);
        foreground = const Color(0xFF475569);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ui_colors.AppColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 13,
        fontWeight: FontWeight.w800,
        fontFamily: 'Inter',
      ),
    );
  }

  Widget _buildProductsTable(QuoteDetailDto detail) {
    if (detail.items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ui_colors.AppColors.borderSoft),
        ),
        child: const Text(
          'Esta cotización no tiene productos.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ui_colors.AppColors.borderSoft),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              border: Border(
                bottom: BorderSide(color: ui_colors.AppColors.borderSoft),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    'CANT.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'PRODUCTO',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                SizedBox(
                  width: 108,
                  child: Text(
                    'IMPORTE',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 310),
            child: Scrollbar(
              controller: _quoteItemsScrollController,
              thumbVisibility: detail.items.length > 5,
              child: ListView.separated(
                controller: _quoteItemsScrollController,
                shrinkWrap: true,
                primary: false,
                itemCount: detail.items.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  color: ui_colors.AppColors.borderSoft,
                ),
                itemBuilder: (context, index) {
                  final item = detail.items[index];
                  final String qty = item.qty.toStringAsFixed(
                    item.qty % 1 == 0 ? 0 : 2,
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 46,
                          child: Text(
                            qty,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF172033),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 108,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              CurrencyDisplay.format(item.totalLine),
                              maxLines: 1,
                              style: const TextStyle(
                                color: ui_colors.AppColors.primaryBlue,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsRow(
    String label,
    String value, {
    bool isTotal = false,
    bool muted = false,
  }) {
    final Color labelColor =
        muted ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: isTotal ? 14 : 12.5,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: isTotal
                    ? ui_colors.AppColors.primaryBlue
                    : labelColor,
                fontSize: isTotal ? 22 : 12.5,
                fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsActions(QuoteDetailDto detail) {
    final quote = detail.quote;
    final bool cannotConvert =
        quote.status == 'CONVERTED' || quote.status == 'CANCELLED';

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: ui_colors.AppColors.borderSoft),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  cannotConvert ? null : () => _convertToTicket(detail),
              style: FilledButton.styleFrom(
                backgroundColor: ui_colors.AppColors.primaryBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 43),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_brandRadius),
                ),
              ),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text(
                'Pasar a ticket',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _shareWhatsApp(detail),
              style: OutlinedButton.styleFrom(
                foregroundColor: ui_colors.AppColors.primaryBlue,
                minimumSize: const Size(0, 41),
                side: const BorderSide(
                  color: ui_colors.AppColors.borderSoft,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_brandRadius),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
              label: const Text(
                'Enviar por WhatsApp',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _smallActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Ver PDF',
                  onPressed: () => _viewPDF(detail),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _smallActionButton(
                  icon: Icons.download_rounded,
                  label: 'Descargar',
                  onPressed: () => _downloadPDF(detail),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _smallActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Duplicar',
                  onPressed: () => _duplicateQuote(detail),
                ),
              ),
              const SizedBox(width: 8),
              _smallActionButton(
                icon: Icons.delete_outline_rounded,
                label: '',
                danger: true,
                onPressed: () => _deleteQuote(detail),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor:
            danger ? const Color(0xFFB42318) : const Color(0xFF475569),
        backgroundColor:
            danger ? const Color(0xFFFEF3F2) : Colors.white,
        side: BorderSide(
          color: danger
              ? const Color(0xFFFECACA)
              : ui_colors.AppColors.borderSoft,
        ),
        minimumSize: Size(label.isEmpty ? 42 : 0, 39),
        padding: EdgeInsets.symmetric(
          horizontal: label.isEmpty ? 11 : 10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_brandRadius),
        ),
      ),
      icon: Icon(icon, size: 16),
      label: label.isEmpty
          ? const SizedBox.shrink()
          : Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
    );
  }

  Future<void> _shareWhatsApp(QuoteDetailDto detail) async {
    try {
      final business = await SettingsRepository.getBusinessInfo();

      final pdfData = await QuotePrinter.generatePdf(
        quote: detail.quote,
        items: detail.items,
        clientName: detail.clientName,
        clientPhone: detail.clientPhone,
        clientRnc: detail.clientRnc,
        business: business,
        validDays: 15,
      );

      await Printing.sharePdf(
        bytes: pdfData,
        filename: 'cotizacion_${detail.quote.id}.pdf',
      );
    } catch (error, stackTrace) {
      if (!mounted) return;

      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        onRetry: () => _shareWhatsApp(detail),
        module: 'sales/quotes/share',
      );
    }
  }

  Future<void> _viewPDF(QuoteDetailDto detail) async {
    try {
      final business = await SettingsRepository.getBusinessInfo();

      if (!mounted) return;

      await QuotePrinter.showPreview(
        context: context,
        quote: detail.quote,
        items: detail.items,
        clientName: detail.clientName,
        clientPhone: detail.clientPhone,
        clientRnc: detail.clientRnc,
        business: business,
        validDays: 15,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;

      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        onRetry: () => _viewPDF(detail),
        module: 'sales/quotes/pdf_preview',
      );
    }
  }

  Future<void> _downloadPDF(QuoteDetailDto detail) async {
    try {
      final business = await SettingsRepository.getBusinessInfo();

      final pdfData = await QuotePrinter.generatePdf(
        quote: detail.quote,
        items: detail.items,
        clientName: detail.clientName,
        clientPhone: detail.clientPhone,
        clientRnc: detail.clientRnc,
        business: business,
        validDays: 15,
      );

      Directory? downloadDirectory;

      if (Platform.isWindows) {
        final String? userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          downloadDirectory = Directory('$userProfile\\Downloads');
        }
      } else if (Platform.isAndroid) {
        downloadDirectory = Directory('/storage/emulated/0/Download');
      } else {
        downloadDirectory = await getDownloadsDirectory();
      }

      downloadDirectory ??= await getApplicationDocumentsDirectory();

      final String date =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String quoteCode =
          'COT-${detail.quote.id!.toString().padLeft(5, '0')}';
      final String filename = '${quoteCode}_$date.pdf';
      final String filePath =
          '${downloadDirectory.path}${Platform.pathSeparator}$filename';

      final file = File(filePath);
      await file.writeAsBytes(pdfData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF descargado: $filename'),
          backgroundColor: _status.success,
          duration: const Duration(seconds: 4),
          action: Platform.isWindows
              ? SnackBarAction(
                  label: 'ABRIR',
                  textColor:
                      ColorUtils.readableTextColor(_status.success),
                  onPressed: () async {
                    try {
                      await Process.run('explorer.exe', <String>[filePath]);
                    } catch (_) {}
                  },
                )
              : null,
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;

      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        onRetry: () => _downloadPDF(detail),
        module: 'sales/quotes/pdf_download',
      );
    }
  }

  Future<void> _duplicateQuote(QuoteDetailDto detail) async {
    if (detail.items.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se puede duplicar una cotización sin productos.',
          ),
          backgroundColor: _status.error,
        ),
      );
      return;
    }

    try {
      await DbHardening.instance.runDbSafe(
        () => QuotesRepository().duplicateQuote(detail.quote.id!),
        stage: 'sales/quotes/duplicate',
      );

      await _loadQuotes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cotización duplicada correctamente.'),
          backgroundColor: _status.success,
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;

      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        onRetry: () => _duplicateQuote(detail),
        module: 'sales/quotes/duplicate',
      );
    }
  }

  Future<void> _deleteQuote(QuoteDetailDto detail) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar cotización'),
          content: Text(
            '¿Deseas eliminar la cotización '
            '#${detail.quote.id}? Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: _status.error,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await DbHardening.instance.runDbSafe(
        () => QuotesRepository().deleteQuote(detail.quote.id!),
        stage: 'sales/quotes/delete',
      );

      _closeSidePanels();
      await _loadQuotes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cotización eliminada.'),
          backgroundColor: _status.error,
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;

      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        onRetry: () => _deleteQuote(detail),
        module: 'sales/quotes/delete',
      );
    }
  }

  Future<void> _convertToTicket(QuoteDetailDto detail) async {
    try {
      final quote = detail.quote;

      if (quote.status == 'PASSED_TO_TICKET') {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Esta cotización ya fue pasada a ticket pendiente.',
            ),
            backgroundColor: _status.warning,
          ),
        );
        return;
      }

      final int? currentUserId = await SessionManager.userId();

      final int ticketId =
          await QuoteToTicketConverter.convertQuoteToTicket(
        quoteId: quote.id!,
        userId: currentUserId ?? quote.userId,
      );

      await _loadQuotes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cotización convertida a ticket pendiente #$ticketId.',
          ),
          backgroundColor: _status.success,
          duration: const Duration(seconds: 3),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 700));

      if (!mounted) return;

      context.go('/sales?ticketId=$ticketId');
    } catch (error, stackTrace) {
      if (!mounted) return;

      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        onRetry: () => _convertToTicket(detail),
        module: 'sales/quotes/convert_ticket',
      );
    }
  }
}
