import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../data/quotes_repository.dart';
import '../data/quote_model.dart';
import '../data/quote_to_ticket_converter.dart';
import '../data/sales_repository.dart';
import '../data/settings_repository.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/printing/quote_printer.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/ui/ui_scale.dart';
import '../../settings/data/printer_settings_repository.dart';
import 'widgets/compact_quote_row.dart';
import 'widgets/quotes_filter_bar.dart';
import 'utils/quotes_filter_util.dart';

class QuotesPage extends StatefulWidget {
  const QuotesPage({super.key});

  @override
  State<QuotesPage> createState() => _QuotesPageState();
}

class _QuotesPageState extends State<QuotesPage> {
  List<QuoteDetailDto> _quotes = [];
  List<QuoteDetailDto> _filteredQuotes = [];
  bool _isLoading = false;
  int _loadSeq = 0;
  late QuotesFilterConfig _filterConfig;
  late SearchDebouncer _searchDebouncer;

  QuoteDetailDto? _selectedQuote;
  int? _selectedQuoteId;

  static const _brandDark = Colors.black;
  static const _brandLight = Colors.white;
  static const _brandRadius = 10.0;

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
    _filterConfig = const QuotesFilterConfig();
    _searchDebouncer = SearchDebouncer(
      duration: const Duration(milliseconds: 300),
      onDebounce: (_) {
        if (!mounted) return;
        _applyFilters();
      },
    );
    _loadQuotes();
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadQuotes() async {
    final seq = ++_loadSeq;
    _safeSetState(() => _isLoading = true);
    try {
      final quotes = await DbHardening.instance.runDbSafe<List<QuoteDetailDto>>(
        () => QuotesRepository().listQuotes(),
        stage: 'sales/quotes/load',
      );
      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() {
        _quotes = quotes;
        _isLoading = false;
        _applyFilters();
      });
    } catch (e, st) {
      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() => _isLoading = false);
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadQuotes,
        module: 'sales/quotes/load',
      );
    }
  }

  void _applyFilters() {
    _safeSetState(() {
      _filteredQuotes = QuotesFilterUtil.applyFilters(_quotes, _filterConfig);

      if (_filteredQuotes.isEmpty) {
        _selectedQuote = null;
        _selectedQuoteId = null;
        return;
      }

      final currentId = _selectedQuoteId;
      if (currentId == null) {
        _selectedQuote = _filteredQuotes.first;
        _selectedQuoteId = _selectedQuote!.quote.id;
        return;
      }

      final match = _filteredQuotes.firstWhere(
        (q) => q.quote.id == currentId,
        orElse: () => _filteredQuotes.first,
      );
      _selectedQuote = match;
      _selectedQuoteId = match.quote.id;
    });
  }

  void _selectQuote(QuoteDetailDto quoteDetail, {required bool showDetails}) {
    _safeSetState(() {
      _selectedQuote = quoteDetail;
      _selectedQuoteId = quoteDetail.quote.id;
    });
    if (showDetails) {
      _showQuoteDetails(quoteDetail);
    }
  }

  void _onFilterChanged(QuotesFilterConfig newConfig) {
    _safeSetState(() {
      _filterConfig = newConfig;
    });
    _searchDebouncer(_filterConfig.searchText);
  }

  @override
  Widget build(BuildContext context) {
    final totalsWidget = _buildQuotesTotalsSummary();

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scale = uiScale(context);
          final horizontalPadding =
              (constraints.maxWidth * 0.018).clamp(12.0, 28.0) * scale;
          final verticalPadding = 10.0 * scale;
          final itemSpacing = 8.0 * scale;
          final isWide = constraints.maxWidth >= 1200;
          final detailWidth =
              (constraints.maxWidth * 0.25).clamp(320.0, 460.0) * scale;
          final listPadding = EdgeInsets.fromLTRB(
            horizontalPadding,
            verticalPadding,
            horizontalPadding,
            22.0 * scale,
          );

          return Column(
            children: [
              QuotesFilterBar(
                initialConfig: _filterConfig,
                onFilterChanged: _onFilterChanged,
                summary: totalsWidget,
              ),
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildQuotesList(
                              listPadding: listPadding,
                              itemSpacing: itemSpacing,
                              isWide: true,
                            ),
                          ),
                          SizedBox(width: 12 * scale),
                          SizedBox(
                            width: detailWidth,
                            child: SizedBox.expand(
                              child: _buildQuoteDetailsPanel(_selectedQuote),
                            ),
                          ),
                        ],
                      )
                    : _buildQuotesList(
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

  Widget _buildQuotesTotalsSummary() {
    final theme = _theme;
    final scheme = _scheme;
    final count = _filteredQuotes.length;
    final totalAmount = _filteredQuotes.fold<double>(
      0,
      (sum, q) => sum + q.quote.total,
    );
    final money = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
      decimalDigits: 2,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _brandDark,
        borderRadius: BorderRadius.circular(_brandRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.summarize_outlined,
            size: 16,
            color: Colors.white.withOpacity(0.85),
          ),
          const SizedBox(width: 8),
          Text(
            'Cotizaciones: $count',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Total: ${money.format(totalAmount)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _brandButtonStyle({Color? borderColor}) {
    return ElevatedButton.styleFrom(
      backgroundColor: _brandDark,
      foregroundColor: _brandLight,
      side: BorderSide(color: borderColor ?? _scheme.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_brandRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    );
  }

  Widget _buildQuotesList({
    required EdgeInsets listPadding,
    required double itemSpacing,
    required bool isWide,
  }) {
    final scheme = _scheme;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredQuotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 80,
              color: scheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _quotes.isEmpty ? 'No hay cotizaciones' : 'No hay resultados',
              style: TextStyle(
                fontSize: 18,
                color: scheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _quotes.isEmpty
                  ? 'Crea una cotización desde la página de ventas'
                  : 'Ajusta los filtros e intenta de nuevo',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: listPadding,
      itemCount: _filteredQuotes.length,
      itemBuilder: (context, index) {
        final quoteDetail = _filteredQuotes[index];
        final isSelected = quoteDetail.quote.id == _selectedQuoteId;
        return Padding(
          padding: EdgeInsets.only(bottom: itemSpacing),
          child: CompactQuoteRow(
            quoteDetail: quoteDetail,
            isSelected: isSelected,
            onTap: () => _selectQuote(quoteDetail, showDetails: !isWide),
            onSell: () => _convertToSale(quoteDetail),
            onWhatsApp: () => _shareWhatsApp(quoteDetail),
            onPdf: () => _viewPDF(quoteDetail),
            onDownload: () => _downloadPDF(quoteDetail),
            onDuplicate: () => _duplicateQuote(quoteDetail),
            onDelete: () => _deleteQuote(quoteDetail),
            onConvertToTicket: () => _convertToTicket(quoteDetail),
          ),
        );
      },
    );
  }

  Widget _buildQuoteDetailsPanel(QuoteDetailDto? quoteDetail) {
    final theme = _theme;
    final scheme = _scheme;
    final status = _status;

    if (quoteDetail == null) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle de cotización',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selecciona una cotización para ver sus detalles.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    final quote = quoteDetail.quote;
    final quoteId = quote.id;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(quote.createdAtMs);
    final createdLabel = DateFormat('dd/MM/yy HH:mm').format(createdAt);

    Color statusColor(String value) {
      switch (value) {
        case 'CONVERTED':
          return status.success;
        case 'CANCELLED':
          return status.error;
        case 'TICKET':
        case 'PASSED_TO_TICKET':
          return status.warning;
        default:
          return scheme.primary;
      }
    }

    final chipColor = statusColor(quote.status);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
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
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    quoteId == null
                        ? 'COT-—'
                        : 'COT-${quoteId.toString().padLeft(5, '0')}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: chipColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    quote.status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Abrir detalle',
                  onPressed: () => _showQuoteDetails(quoteDetail),
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              quoteDetail.clientName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              createdLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 14),
            _buildDetailMetric(
              label: 'Total',
              value: NumberFormat.currency(
                locale: 'es_DO',
                symbol: 'RD\$',
                decimalDigits: 2,
              ).format(quote.total),
              color: scheme.primary,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildDetailMetric(
                    label: 'Subtotal',
                    value: NumberFormat.currency(
                      locale: 'es_DO',
                      symbol: 'RD\$',
                      decimalDigits: 2,
                    ).format(quote.subtotal),
                    color: scheme.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDetailMetric(
                    label: 'Descuento',
                    value: NumberFormat.currency(
                      locale: 'es_DO',
                      symbol: 'RD\$',
                      decimalDigits: 2,
                    ).format(quote.discountTotal),
                    color: scheme.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildDetailMetric(
              label: 'ITBIS',
              value: quote.itbisEnabled
                  ? NumberFormat.currency(
                      locale: 'es_DO',
                      symbol: 'RD\$',
                      decimalDigits: 2,
                    ).format(quote.itbisAmount)
                  : 'No',
              color: quote.itbisEnabled ? scheme.outline : scheme.outline,
            ),

            const SizedBox(height: 14),
            Text(
              'Productos (${quoteDetail.items.length})',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (quoteDetail.items.isEmpty)
              Text(
                'Sin productos.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.7),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: quoteDetail.items.map((item) {
                    final qtyLabel = item.qty.toStringAsFixed(
                      item.qty % 1 == 0 ? 0 : 2,
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              qtyLabel,
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 86,
                            child: Text(
                              NumberFormat.currency(
                                locale: 'es_DO',
                                symbol: 'RD\$',
                                decimalDigits: 2,
                              ).format(item.totalLine),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            if ((quote.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Notas',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                quote.notes!.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.75),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (quote.status == 'CONVERTED' || quote.status == 'CANCELLED')
                    ? null
                    : () => _convertToSale(quoteDetail),
                icon: const Icon(Icons.point_of_sale, size: 18),
                label: const Text('Convertir a venta'),
                style: _brandButtonStyle(borderColor: scheme.primary),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (quote.status == 'CONVERTED' || quote.status == 'CANCELLED')
                    ? null
                    : () => _convertToTicket(quoteDetail),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Pasar a ticket'),
                style: _brandButtonStyle(borderColor: scheme.tertiary),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _shareWhatsApp(quoteDetail),
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('Enviar por WhatsApp'),
                style: _brandButtonStyle(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _viewPDF(quoteDetail),
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('PDF'),
                    style: _brandButtonStyle(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _downloadPDF(quoteDetail),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Descargar'),
                    style: _brandButtonStyle(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _duplicateQuote(quoteDetail),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Duplicar'),
                style: _brandButtonStyle(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _deleteQuote(quoteDetail),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Eliminar'),
                style: _brandButtonStyle(borderColor: status.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = _theme;
    final scheme = _scheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _showQuoteDetails(QuoteDetailDto quoteDetail) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _QuoteDetailsDialog(quoteDetail: quoteDetail),
    );

    // Si algo cambió en el diálogo, recargar la lista
    if (changed == true && mounted) {
      await _loadQuotes();
    }
  }

  Future<void> _convertToSale(QuoteDetailDto quoteDetail) async {
    // Validación: Verificar si la cotización ya fue convertida
    if (quoteDetail.quote.status == 'CONVERTED') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Esta cotización ya fue convertida a venta'),
            backgroundColor: _status.warning,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Validación: Verificar que hay items en la cotización
    if (quoteDetail.items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ No se puede convertir una cotización sin productos',
            ),
            backgroundColor: _status.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.point_of_sale, color: _status.success, size: 48),
        title: const Text('CONVERTIR A VENTA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '¿Convertir la cotización COT-${quoteDetail.quote.id!.toString().padLeft(5, '0')} en venta?',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _status.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _status.warning),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: _status.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esto descontará el stock de los productos automáticamente',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('CONVERTIR A VENTA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _status.success,
              foregroundColor: ColorUtils.readableTextColor(_status.success),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final quote = quoteDetail.quote;

        // Generar código de venta
        final localCode = await SalesRepository.generateNextLocalCode('sale');

        // Convertir items de cotización a mapas para createSale
        final saleItems = quoteDetail.items
            .map(
              (item) => <String, dynamic>{
                'product_id': item.productId,
                'code': item.productCode ?? 'N/A',
                'description': item.description,
                'qty': item.qty,
                'price': item.price,
                'cost': item.cost,
                'discount': item.discountLine,
              },
            )
            .toList();

        // Crear la venta (atómica). Si el stock quedaría en negativo, pedir confirmación.
        int saleId;
        try {
          saleId = await SalesRepository.createSale(
            localCode: localCode,
            kind: 'sale',
            items: saleItems,
            itbisEnabled: quote.itbisEnabled,
            itbisRate: quote.itbisRate,
            discountTotal: quote.discountTotal,
            paymentMethod: 'cash', // Por defecto efectivo
            customerId: quote.clientId,
            customerName: quoteDetail.clientName,
            customerPhone: quoteDetail.clientPhone,
            customerRnc: quoteDetail.clientRnc,
            paidAmount: quote.total,
            changeAmount: 0,
          );
        } on AppException catch (e, st) {
          if (e.code != 'stock_negative') {
            await ErrorHandler.instance.handle(
              e,
              stackTrace: st,
              context: context,
              module: 'quotes',
            );
            return;
          }

          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Stock insuficiente'),
              content: Text(e.messageUser),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('CONTINUAR'),
                ),
              ],
            ),
          );
          if (proceed != true) return;

          final retry = await ErrorHandler.instance.runSafe<int>(
            () => SalesRepository.createSale(
              localCode: localCode,
              kind: 'sale',
              items: saleItems,
              allowNegativeStock: true,
              itbisEnabled: quote.itbisEnabled,
              itbisRate: quote.itbisRate,
              discountTotal: quote.discountTotal,
              paymentMethod: 'cash',
              customerId: quote.clientId,
              customerName: quoteDetail.clientName,
              customerPhone: quoteDetail.clientPhone,
              customerRnc: quoteDetail.clientRnc,
              paidAmount: quote.total,
              changeAmount: 0,
            ),
            context: context,
            module: 'quotes',
          );
          if (retry == null) return;
          saleId = retry;
        }

        // Actualizar estado de la cotización
        await DbHardening.instance.runDbSafe(
          () => QuotesRepository().updateQuoteStatus(quote.id!, 'CONVERTED'),
          stage: 'sales/quotes/update_status',
        );

        await _loadQuotes();

        if (mounted) {
          // Preguntar si desea imprimir
          final printTicket = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              icon: Icon(Icons.check_circle, color: _status.success, size: 48),
              title: const Text('¡VENTA CREADA!'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Código: $localCode'),
                  Text('Total: \$${quote.total.toStringAsFixed(2)}'),
                  const SizedBox(height: 16),
                  const Text('¿Desea imprimir el ticket?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('NO'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.print),
                  label: const Text('IMPRIMIR'),
                ),
              ],
            ),
          );

          if (printTicket == true) {
            final sale = await SalesRepository.getSaleById(saleId);
            final items = await SalesRepository.getItemsBySaleId(saleId);
            if (sale != null) {
              // Obtener nombre del cajero desde la sesión
              final cashierName =
                  await SessionManager.displayName() ?? 'Cajero';
              await UnifiedTicketPrinter.reprintSale(
                sale: sale,
                items: items,
                cashierName: cashierName,
              );
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Venta creada: $localCode'),
              backgroundColor: _status.success,
            ),
          );
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _convertToSale(quoteDetail),
            module: 'sales/quotes/convert',
          );
        }
      }
    }
  }

  Future<void> _shareWhatsApp(QuoteDetailDto quoteDetail) async {
    try {
      final business = await SettingsRepository.getBusinessInfo();

      // Generar PDF
      final pdfData = await QuotePrinter.generatePdf(
        quote: quoteDetail.quote,
        items: quoteDetail.items,
        clientName: quoteDetail.clientName,
        clientPhone: quoteDetail.clientPhone,
        clientRnc: quoteDetail.clientRnc,
        business: business,
        validDays: 15,
      );

      // Compartir
      await Printing.sharePdf(
        bytes: pdfData,
        filename: 'cotizacion_${quoteDetail.quote.id}.pdf',
      );
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _shareWhatsApp(quoteDetail),
          module: 'sales/quotes/share',
        );
      }
    }
  }

  Future<void> _viewPDF(QuoteDetailDto quoteDetail) async {
    try {
      final business = await SettingsRepository.getBusinessInfo();

      if (mounted) {
        await QuotePrinter.showPreview(
          context: context,
          quote: quoteDetail.quote,
          items: quoteDetail.items,
          clientName: quoteDetail.clientName,
          clientPhone: quoteDetail.clientPhone,
          clientRnc: quoteDetail.clientRnc,
          business: business,
          validDays: 15,
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _viewPDF(quoteDetail),
          module: 'sales/quotes/pdf_preview',
        );
      }
    }
  }

  /// Descargar cotización como PDF a la carpeta de Descargas
  Future<void> _downloadPDF(QuoteDetailDto quoteDetail) async {
    try {
      // Mostrar indicador de carga
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ColorUtils.readableTextColor(_status.info),
                  ),
                ),
                SizedBox(width: 12),
                Text('Generando PDF...'),
              ],
            ),
            duration: Duration(seconds: 1),
            backgroundColor: _status.info,
          ),
        );
      }

      final business = await SettingsRepository.getBusinessInfo();

      // Generar PDF
      final pdfData = await QuotePrinter.generatePdf(
        quote: quoteDetail.quote,
        items: quoteDetail.items,
        clientName: quoteDetail.clientName,
        clientPhone: quoteDetail.clientPhone,
        clientRnc: quoteDetail.clientRnc,
        business: business,
        validDays: 15,
      );

      // Obtener carpeta de descargas
      Directory? downloadDir;
      if (Platform.isWindows) {
        // En Windows, usar la carpeta de Descargas del usuario
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          downloadDir = Directory('$userProfile\\Downloads');
        }
      } else if (Platform.isAndroid) {
        downloadDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadDir = await getDownloadsDirectory();
      }

      // Fallback a documentos si no existe Descargas
      downloadDir ??= await getApplicationDocumentsDirectory();

      // Crear nombre de archivo único con fecha
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      final quoteCode =
          'COT-${quoteDetail.quote.id!.toString().padLeft(5, '0')}';
      final fileName = '${quoteCode}_$dateStr.pdf';
      final filePath = '${downloadDir.path}${Platform.pathSeparator}$fileName';

      // Guardar archivo
      final file = File(filePath);
      await file.writeAsBytes(pdfData);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: ColorUtils.readableTextColor(_status.success),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✅ PDF descargado correctamente',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(fileName, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: _status.success,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'ABRIR',
              textColor: ColorUtils.readableTextColor(_status.success),
              onPressed: () async {
                // Intentar abrir el archivo
                try {
                  if (Platform.isWindows) {
                    await Process.run('explorer.exe', [filePath]);
                  }
                } catch (_) {}
              },
            ),
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _downloadPDF(quoteDetail),
          module: 'sales/quotes/pdf_download',
        );
      }
    }
  }

  /// Duplicar una cotización
  Future<void> _duplicateQuote(QuoteDetailDto quoteDetail) async {
    // Validación: Verificar que hay items en la cotización
    if (quoteDetail.items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ No se puede duplicar una cotización sin productos',
            ),
            backgroundColor: _status.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Validación: Verificar que todos los items tengan precio válido
    final hasInvalidPrices = quoteDetail.items.any((item) => item.price <= 0);
    if (hasInvalidPrices) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(Icons.warning, color: _status.warning, size: 48),
            title: const Text('ADVERTENCIA'),
            content: const Text(
              'Algunos productos en esta cotización tienen precio cero o inválido. Se duplicarán pero verifique los precios.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }

    try {
      debugPrint('📋 Duplicando cotización ID: ${quoteDetail.quote.id}...');
      await DbHardening.instance.runDbSafe(
        () => QuotesRepository().duplicateQuote(quoteDetail.quote.id!),
        stage: 'sales/quotes/duplicate',
      );
      if (!mounted) return;

      debugPrint('✅ Cotización duplicada. Recargando lista...');
      // ✅ IMPORTANTE: Recargar la lista ANTES de cerrar
      await _loadQuotes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Cotización duplicada exitosamente'),
          backgroundColor: _status.success,
        ),
      );
    } catch (e, stack) {
      debugPrint('❌ Error al duplicar cotización: $e');
      debugPrint('Stack trace: $stack');
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: stack,
        context: context,
        onRetry: () => _duplicateQuote(quoteDetail),
        module: 'sales/quotes/duplicate',
      );
    }
  }

  /// Eliminar una cotización con confirmación
  Future<void> _deleteQuote(QuoteDetailDto quoteDetail) async {
    // Advertencia especial si la cotización fue convertida
    final isConverted = quoteDetail.quote.status == 'CONVERTED';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Cotización'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '¿Está seguro que desea eliminar la cotización #${quoteDetail.quote.id}?\n'
              'Esta acción no se puede deshacer.',
            ),
            if (isConverted) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _status.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _status.error),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: _status.error),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Esta cotización ya fue convertida a venta. Solo se eliminará el registro.',
                        style: TextStyle(fontSize: 12, color: _status.error),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: TextStyle(color: _status.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      debugPrint('🗑️  Eliminando cotización ID: ${quoteDetail.quote.id}...');
      await DbHardening.instance.runDbSafe(
        () => QuotesRepository().deleteQuote(quoteDetail.quote.id!),
        stage: 'sales/quotes/delete',
      );
      if (!mounted) return;

      debugPrint('✅ Cotización eliminada. Recargando lista...');
      // ✅ IMPORTANTE: Recargar la lista ANTES de cualquier navegación
      await _loadQuotes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Cotización eliminada'),
          backgroundColor: _status.error,
        ),
      );
    } catch (e, stack) {
      debugPrint('❌ Error al eliminar cotización: $e');
      debugPrint('Stack trace: $stack');
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: stack,
        context: context,
        onRetry: () => _deleteQuote(quoteDetail),
        module: 'sales/quotes/delete',
      );
    }
  }

  /// Pasar cotización a ticket pendiente (caja)
  Future<void> _convertToTicket(QuoteDetailDto quoteDetail) async {
    try {
      final quote = quoteDetail.quote;

      debugPrint(
        '🎫 [UI] Iniciando conversión de cotización #${quote.id} a ticket pendiente',
      );

      if (quote.status == 'PASSED_TO_TICKET') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ Esta cotización ya fue convertida a ticket pendiente',
            ),
            backgroundColor: _status.warning,
          ),
        );
        return;
      }

      // Usar el nuevo conversor transaccional
      final ticketId = await QuoteToTicketConverter.convertQuoteToTicket(
        quoteId: quote.id!,
        userId: quote.userId,
      );

      if (!mounted) return;

      debugPrint(
        '🎉 [UI] Cotización convertida exitosamente a ticket #$ticketId',
      );

      // ✅ IMPORTANTE: Recargar la lista ANTES de mostrar mensajes
      await _loadQuotes();

      if (!mounted) return;

      // Mostrar mensaje de éxito
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Cotización convertida a ticket pendiente #$ticketId',
          ),
          backgroundColor: _status.success,
          duration: const Duration(seconds: 3),
        ),
      );

      // Navegar a Ventas después de 1 segundo para que vea el mensaje
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      context.go('/sales');
    } catch (e, stack) {
      debugPrint('❌ [UI] Error al convertir a ticket: $e');
      debugPrint('Stack: $stack');

      if (!mounted) return;

      await ErrorHandler.instance.handle(
        e,
        stackTrace: stack,
        context: context,
        onRetry: () => _convertToTicket(quoteDetail),
        module: 'sales/quotes/convert_ticket',
      );
    }
  }
}

// Dialog para mostrar detalles de cotización
class _QuoteDetailsDialog extends StatefulWidget {
  final QuoteDetailDto quoteDetail;

  const _QuoteDetailsDialog({required this.quoteDetail});

  @override
  State<_QuoteDetailsDialog> createState() => _QuoteDetailsDialogState();
}

class _QuoteDetailsDialogState extends State<_QuoteDetailsDialog> {
  bool _isLoading = false;

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

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  /// Cierra el diálogo con un resultado (true = algo cambió)
  void _closeDialog([bool changed = false]) {
    Navigator.pop(context, changed);
  }

  Future<void> _viewPDF() async {
    _safeSetState(() => _isLoading = true);
    try {
      final business = await SettingsRepository.getBusinessInfo();

      if (mounted) {
        await QuotePrinter.showPreview(
          context: context,
          quote: widget.quoteDetail.quote,
          items: widget.quoteDetail.items,
          clientName: widget.quoteDetail.clientName,
          clientPhone: widget.quoteDetail.clientPhone,
          clientRnc: widget.quoteDetail.clientRnc,
          business: business,
          validDays: 15,
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _viewPDF,
          module: 'sales/quotes/dialog_pdf_preview',
        );
      }
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  Future<void> _printQuote() async {
    _safeSetState(() => _isLoading = true);
    try {
      final business = await SettingsRepository.getBusinessInfo();
      final settings = await PrinterSettingsRepository.getOrCreate();

      final success = await QuotePrinter.printQuote(
        quote: widget.quoteDetail.quote,
        items: widget.quoteDetail.items,
        clientName: widget.quoteDetail.clientName,
        clientPhone: widget.quoteDetail.clientPhone,
        clientRnc: widget.quoteDetail.clientRnc,
        business: business,
        settings: settings,
        validDays: 15,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? '✅ Cotización impresa' : '❌ Error al imprimir',
            ),
            backgroundColor: success ? _status.success : _status.error,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _printQuote,
          module: 'sales/quotes/dialog_print',
        );
      }
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  /// Duplicar cotización desde el diálogo
  Future<void> _duplicateQuoteFromDialog() async {
    _safeSetState(() => _isLoading = true);
    try {
      // Validación: Verificar que hay items en la cotización
      if (widget.quoteDetail.items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ No se puede duplicar una cotización sin productos',
              ),
              backgroundColor: _status.error,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Validación: Verificar que todos los items tengan precio válido
      final hasInvalidPrices = widget.quoteDetail.items.any(
        (item) => item.price <= 0,
      );
      if (hasInvalidPrices) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              icon: Icon(Icons.warning, color: _status.warning, size: 48),
              title: const Text('ADVERTENCIA'),
              content: const Text(
                'Algunos productos en esta cotización tienen precio cero o inválido. Se duplicarán pero verifique los precios.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }

      // Duplicar la cotización
      await DbHardening.instance.runDbSafe(
        () => QuotesRepository().duplicateQuote(widget.quoteDetail.quote.id!),
        stage: 'sales/quotes/duplicate_dialog',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Cotización duplicada exitosamente'),
          backgroundColor: _status.success,
        ),
      );

      // Cerrar el diálogo indicando que hubo un cambio
      _closeDialog(true);
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _duplicateQuoteFromDialog,
        module: 'sales/quotes/dialog_duplicate',
      );
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  /// Eliminar cotización desde el diálogo
  Future<void> _deleteQuoteFromDialog() async {
    // Advertencia especial si la cotización fue convertida
    final isConverted = widget.quoteDetail.quote.status == 'CONVERTED';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Cotización'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '¿Está seguro que desea eliminar la cotización #${widget.quoteDetail.quote.id}?\n'
              'Esta acción no se puede deshacer.',
            ),
            if (isConverted) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _status.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _status.error),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: _status.error),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Esta cotización ya fue convertida a venta. Solo se eliminará el registro.',
                        style: TextStyle(fontSize: 12, color: _status.error),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: TextStyle(color: _status.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      _safeSetState(() => _isLoading = true);
      debugPrint(
        '🗑️  Eliminando cotización ID: ${widget.quoteDetail.quote.id}...',
      );
      await DbHardening.instance.runDbSafe(
        () => QuotesRepository().deleteQuote(widget.quoteDetail.quote.id!),
        stage: 'sales/quotes/delete_dialog',
      );

      if (!mounted) return;

      debugPrint('✅ Cotización eliminada');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Cotización eliminada'),
          backgroundColor: _status.error,
        ),
      );

      // Cerrar el diálogo indicando que hubo un cambio
      _closeDialog(true);
    } catch (e, stack) {
      debugPrint('❌ Error al eliminar cotización: $e');
      debugPrint('Stack trace: $stack');
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: stack,
        context: context,
        onRetry: _deleteQuoteFromDialog,
        module: 'sales/quotes/dialog_delete',
      );
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = _scheme;
    final status = _status;
    final headerForeground = ColorUtils.readableTextColor(scheme.primary);
    final scale = uiScale(context);
    final mq = MediaQuery.of(context);
    final maxWidth = (mq.size.width * 0.92).clamp(320.0, 720.0);
    final maxHeight = (mq.size.height * 0.9).clamp(420.0, 860.0);
    final footerBackground = scheme.surfaceContainerHighest;
    final pdfColor = ColorUtils.ensureReadableColor(
      scheme.secondary,
      footerBackground,
    );
    final printColor = ColorUtils.ensureReadableColor(
      scheme.primary,
      footerBackground,
    );
    final duplicateColor = ColorUtils.ensureReadableColor(
      scheme.tertiary,
      footerBackground,
    );
    final deleteColor = ColorUtils.ensureReadableColor(
      status.error,
      footerBackground,
    );
    final quote = widget.quoteDetail.quote;
    final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(18 * scale),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.description, color: headerForeground, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COT-${quote.id!.toString().padLeft(5, '0')}',
                          style: TextStyle(
                            color: headerForeground,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          dateFormatter.format(
                            DateTime.fromMillisecondsSinceEpoch(
                              quote.createdAtMs,
                            ),
                          ),
                          style: TextStyle(
                            color: headerForeground.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: headerForeground),
                    onPressed: () => _closeDialog(false),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(18 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cliente
                    _buildInfoSection('Cliente', [
                      _buildInfoRow('Nombre', widget.quoteDetail.clientName),
                      if ((widget.quoteDetail.clientPhone ?? '')
                          .trim()
                          .isNotEmpty)
                        _buildInfoRow(
                          'Teléfono',
                          widget.quoteDetail.clientPhone!,
                        ),
                      if (widget.quoteDetail.clientRnc != null)
                        _buildInfoRow('RNC', widget.quoteDetail.clientRnc!),
                    ]),
                    SizedBox(height: 16 * scale),
                    // Items
                    _buildInfoSection(
                      'Productos (${widget.quoteDetail.items.length})',
                      widget.quoteDetail.items
                          .map((item) => _buildItemRow(item))
                          .toList(),
                    ),
                    SizedBox(height: 16 * scale),
                    // Totales
                    _buildTotalsSection(quote),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: EdgeInsets.all(14 * scale),
              decoration: BoxDecoration(
                color: footerBackground,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Botón Ver PDF
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _viewPDF,
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('VER PDF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pdfColor,
                        side: BorderSide(color: pdfColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón Imprimir
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _printQuote,
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('IMPRIMIR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: printColor,
                        side: BorderSide(color: printColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón Duplicar
                    OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _duplicateQuoteFromDialog(),
                      icon: const Icon(Icons.content_copy, size: 18),
                      label: const Text('DUPLICAR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: duplicateColor,
                        side: BorderSide(color: duplicateColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón Eliminar
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _deleteQuoteFromDialog,
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('ELIMINAR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: deleteColor,
                        side: BorderSide(color: deleteColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _closeDialog(false),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    final scheme = _scheme;
    final sectionBackground = scheme.surfaceContainerHighest;
    final sectionForeground = ColorUtils.ensureReadableColor(
      scheme.onSurface,
      sectionBackground,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sectionBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .map(
                  (child) => DefaultTextStyle.merge(
                    style: TextStyle(color: sectionForeground),
                    child: child,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final scheme = _scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withOpacity(0.6),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(QuoteItemModel item) {
    final scheme = _scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(item.description, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Text(
            '${item.qty.toStringAsFixed(0)} x \$${item.price.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '\$${item.totalLine.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection(QuoteModel quote) {
    final scheme = _scheme;
    final background = scheme.primaryContainer;
    final foreground = ColorUtils.readableTextColor(background);
    final muted = foreground.withOpacity(0.85);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Column(
        children: [
          _buildTotalRow('Subtotal', quote.subtotal, textColor: muted),
          if (quote.discountTotal > 0)
            _buildTotalRow('Descuento', -quote.discountTotal, textColor: muted),
          if (quote.itbisEnabled)
            _buildTotalRow(
              'ITBIS (${(quote.itbisRate * 100).toStringAsFixed(0)}%)',
              quote.itbisAmount,
              textColor: muted,
            ),
          Divider(height: 20, color: foreground.withOpacity(0.35)),
          _buildTotalRow(
            'TOTAL',
            quote.total,
            bold: true,
            large: true,
            textColor: foreground,
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    double amount, {
    bool bold = false,
    bool large = false,
    Color? textColor,
  }) {
    final scheme = _scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: large ? 18 : 15,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: textColor,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: large ? 20 : 15,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: large ? textColor : textColor ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
