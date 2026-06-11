import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/printing/reports_printer.dart';
import '../../../core/utils/app_event_bus.dart';
import '../../../core/utils/currency_display.dart';
import '../../../theme/app_colors.dart' as ui_colors;
import '../data/reports_repository.dart';
import 'client_sales_report_page.dart';
import 'widgets/date_range_selector.dart';
import 'widgets/payment_method_pie_chart.dart';
import 'widgets/sales_bar_chart.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  DateRangePeriod _selectedPeriod = DateRangePeriod.today;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _isLoading = true;
  KpisData? _kpis;
  List<SeriesDataPoint> _salesSeries = [];
  List<SeriesDataPoint> _profitSeries = [];
  List<TopProduct> _topProducts = [];
  List<TopClient> _topClients = [];
  List<SaleRecord> _salesList = [];
  List<PaymentMethodData> _paymentMethods = [];
  Map<String, dynamic> _comparativeStats = <String, dynamic>{};
  final Map<String, bool> _pdfSections = <String, bool>{
    'kpis': true,
    'salesSeries': true,
    'paymentMethods': true,
    'profitSeries': true,
    'comparativeStats': true,
    'topProducts': true,
    'topClients': true,
    'salesList': true,
  };
  StreamSubscription<dynamic>? _eventsSubscription;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _eventsSubscription = AppEventBus.stream.listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 250), _loadData);
    });
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _eventsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    final range = DateRangeHelper.getRangeForPeriod(
      _selectedPeriod,
      customStart: _customStart,
      customEnd: _customEnd,
    );
    final startMs = range.start.millisecondsSinceEpoch;
    final endMs = range.end.millisecondsSinceEpoch;

    Future<T> safe<T>(Future<T> Function() run, T fallback) async {
      try {
        return await run();
      } catch (e) {
        debugPrint('Reporte: error obteniendo dato: $e');
        return fallback;
      }
    }

    final kpis = await safe(
      () => ReportsRepository.getKpis(startMs: startMs, endMs: endMs),
      KpisData(
        totalSales: 0,
        totalProfit: 0,
        salesCount: 0,
        quotesCount: 0,
        quotesConverted: 0,
        avgTicket: 0,
      ),
    );
    final salesSeries = await safe(
      () => ReportsRepository.getSalesSeries(startMs: startMs, endMs: endMs),
      <SeriesDataPoint>[],
    );
    final profitSeries = await safe(
      () => ReportsRepository.getProfitSeries(startMs: startMs, endMs: endMs),
      <SeriesDataPoint>[],
    );
    final topProducts = await safe(
      () => ReportsRepository.getTopProducts(
        startMs: startMs,
        endMs: endMs,
        limit: 10,
      ),
      <TopProduct>[],
    );
    final topClients = await safe(
      () => ReportsRepository.getTopClients(
        startMs: startMs,
        endMs: endMs,
        limit: 10,
      ),
      <TopClient>[],
    );
    final salesList = await safe(
      () => ReportsRepository.getSalesList(startMs: startMs, endMs: endMs),
      <SaleRecord>[],
    );
    final paymentMethods = await safe(
      () => ReportsRepository.getPaymentMethodDistribution(
        startMs: startMs,
        endMs: endMs,
      ),
      <PaymentMethodData>[],
    );
    final comparativeStats = await safe(
      () => ReportsRepository.getComparativeStats(),
      <String, dynamic>{},
    );

    if (!mounted) return;

    setState(() {
      _kpis = kpis;
      _salesSeries = salesSeries;
      _profitSeries = profitSeries;
      _topProducts = topProducts;
      _topClients = topClients;
      _salesList = salesList;
      _paymentMethods = paymentMethods;
      _comparativeStats = comparativeStats;
      _isLoading = false;
    });
  }

  void _onPeriodChanged(DateRangePeriod period) {
    setState(() => _selectedPeriod = period);
    _loadData();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customStart != null && _customEnd != null
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: now,
            ),
    );

    if (range == null) return;
    setState(() {
      _customStart = range.start;
      _customEnd = range.end;
      _selectedPeriod = DateRangePeriod.custom;
    });
    _loadData();
  }

  Future<void> _exportCSV() async {
    final scheme = Theme.of(context).colorScheme;
    final range = DateRangeHelper.getRangeForPeriod(
      _selectedPeriod,
      customStart: _customStart,
      customEnd: _customEnd,
    );

    try {
      final csv = await ReportsRepository.exportToCSV(
        startMs: range.start.millisecondsSinceEpoch,
        endMs: range.end.millisecondsSinceEpoch,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV generado: ${csv.split('\n').length - 1} ventas'),
          backgroundColor: scheme.tertiary,
          action: SnackBarAction(
            label: 'Ver',
            textColor: scheme.onTertiary,
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('CSV Generado'),
                  content: SingleChildScrollView(child: SelectableText(csv)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
    }
  }

  Future<void> _exportPdf() async {
    if (_isLoading) return;
    final scheme = Theme.of(context).colorScheme;

    final selected = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) {
        final dialogTheme = Theme.of(context);
        final dialogScheme = dialogTheme.colorScheme;
        final temp = Map<String, bool>.from(_pdfSections);

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Widget item(String key, String label) {
              final enabled = temp[key] ?? false;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setStateDialog(() => temp[key] = !enabled),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: enabled
                        ? dialogScheme.primary.withOpacity(0.08)
                        : dialogScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: enabled
                          ? dialogScheme.primary.withOpacity(0.22)
                          : dialogScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: enabled,
                        onChanged: (v) =>
                            setStateDialog(() => temp[key] = v ?? false),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: dialogTheme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: dialogScheme.error.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.picture_as_pdf_outlined,
                          color: dialogScheme.error,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Configurar PDF',
                          style: dialogTheme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Selecciona las secciones que quieres incluir en el reporte exportado.',
                    style: dialogTheme.textTheme.bodySmall?.copyWith(
                      color: dialogScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      item('kpis', 'KPIs'),
                      item('salesSeries', 'Ventas por Período'),
                      item('paymentMethods', 'Métodos de Pago'),
                      item('profitSeries', 'Utilidad por Período'),
                      item('comparativeStats', 'Comparativa de Ventas'),
                      const Divider(),
                      item('topProducts', 'Top Productos'),
                      item('topClients', 'Top Clientes'),
                      item('salesList', 'Ventas (Listado)'),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, temp),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generar PDF'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null) return;
    _pdfSections
      ..clear()
      ..addAll(selected);

    final range = DateRangeHelper.getRangeForPeriod(
      _selectedPeriod,
      customStart: _customStart,
      customEnd: _customEnd,
    );

    try {
      final pdfBytes = await ReportsPrinter.generatePdf(
        rangeStart: range.start,
        rangeEnd: range.end,
        sections: _pdfSections,
        kpis: _kpis,
        salesSeries: _salesSeries,
        profitSeries: _profitSeries,
        paymentMethods: _paymentMethods,
        topProducts: _topProducts,
        topClients: _topClients,
        salesList: _salesList,
        comparativeStats: _comparativeStats,
      );

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw StateError('No se pudo acceder al directorio de descargas');
      }

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${downloadsDir.path}/Reporte_$ts.pdf');
      await file.writeAsBytes(pdfBytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Reporte de Estadísticas');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF generado: ${file.path}'),
          backgroundColor: scheme.tertiary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al generar PDF: $e'),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  String _periodLabel() {
    switch (_selectedPeriod) {
      case DateRangePeriod.today:
        return 'Hoy';
      case DateRangePeriod.week:
        return 'Semana';
      case DateRangePeriod.biweekly:
        return '15 dias';
      case DateRangePeriod.month:
        return 'Mes';
      case DateRangePeriod.year:
        return 'Ano';
      case DateRangePeriod.custom:
        return 'Personalizado';
    }
  }

  String _formatNumber(num value) {
    final normalized = value.toDouble();
    if (normalized.isNaN || normalized.isInfinite) {
      return '0';
    }

    final sign = normalized < 0 ? '-' : '';
    final formatter = NumberFormat('#,##0', 'en_US');
    return '$sign${formatter.format(normalized.abs().round())}';
  }

  String _formatCurrency(num value) {
    final normalized = value.toDouble();
    if (normalized.isNaN || normalized.isInfinite) {
      return 'RD\$ 0.00';
    }
    return CurrencyDisplay.format(normalized, symbol: 'RD\$', decimalDigits: 2);
  }

  @override
  Widget build(BuildContext context) {
    const pageBackground = Color(0xFFF2F6F9);
    return Scaffold(
      backgroundColor: pageBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final fraction = constraints.maxWidth >= 1400
              ? 0.88
              : (constraints.maxWidth >= 1000 ? 0.92 : 0.96);
          final contentWidth = math.min(
            constraints.maxWidth * fraction,
            1500.0,
          );
          final horizontal = math.max(
            12.0,
            (constraints.maxWidth - contentWidth) / 2,
          );
          final isNarrow = contentWidth < 900;
          return _isLoading
              ? _buildLoadingState()
              : _buildContent(
                  padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 22),
                  isNarrow: isNarrow,
                );
        },
      ),
    );
  }

  Widget _buildPageHeader(bool isNarrow) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ANALÍTICA',
          style: theme.textTheme.labelSmall?.copyWith(
            color: const Color(0xFF1A56DB),
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Rendimiento comercial',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ventas, rentabilidad y comportamiento del período seleccionado.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/sales');
            }
          },
          tooltip: 'Volver',
        ),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          tooltip: 'Acciones del reporte',
          color: Colors.white,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          onSelected: (value) {
            switch (value) {
              case 'clients':
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ClientSalesReportPage(),
                  ),
                );
              case 'pdf':
                _exportPdf();
              case 'csv':
                _exportCSV();
              case 'refresh':
                _loadData();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'clients',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.people_alt_outlined),
                title: Text('Ver clientes'),
              ),
            ),
            PopupMenuItem(
              value: 'pdf',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('Exportar PDF'),
              ),
            ),
            PopupMenuItem(
              value: 'csv',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.download_outlined),
                title: Text('Exportar CSV'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.refresh_rounded),
                title: Text('Actualizar'),
              ),
            ),
          ],
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.more_horiz_rounded),
            label: const Text('Acciones'),
            style: FilledButton.styleFrom(
              disabledBackgroundColor: scheme.primary,
              disabledForegroundColor: scheme.onPrimary,
            ),
          ),
        ),
      ],
    );
    return isNarrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 14), controls],
          )
        : Row(
            children: [
              Expanded(child: title),
              controls,
            ],
          );
  }

  Widget _buildFilterBar(bool isNarrow) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filters = [
      ('Hoy', DateRangePeriod.today),
      ('Semana', DateRangePeriod.week),
      ('15 dias', DateRangePeriod.biweekly),
      ('Mes', DateRangePeriod.month),
      ('Personalizado', DateRangePeriod.custom),
    ];

    Widget segment(String label, DateRangePeriod period) {
      final isSelected = _selectedPeriod == period;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (period == DateRangePeriod.custom) {
            await _pickCustomRange();
            return;
          }
          _onPeriodChanged(period);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isSelected ? scheme.onPrimary : scheme.onSurface,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return isNarrow
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final item in filters) segment(item.$1, item.$2)],
          )
        : Row(
            children: [
              for (final item in filters) ...[
                segment(item.$1, item.$2),
                if (item != filters.last) const SizedBox(width: 8),
              ],
            ],
          );
  }

  Widget _buildLoadingState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(scheme.primary),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Cargando reportes',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Procesando ventas y métricas del rango seleccionado.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.58),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({required EdgeInsets padding, required bool isNarrow}) {
    final scheme = Theme.of(context).colorScheme;
    final kpis = _kpis;
    final topClient = _topClients.isNotEmpty ? _topClients.first : null;
    final topPayment = _paymentMethods.isNotEmpty
        ? (_paymentMethods.toList()
                ..sort((a, b) => b.amount.compareTo(a.amount)))
              .first
        : null;

    return SingleChildScrollView(
      padding: padding,
      child: Container(
        padding: EdgeInsets.all(isNarrow ? 16 : 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F172A),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageHeader(isNarrow),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _buildFilterBar(isNarrow),
            const SizedBox(height: 20),
            if (kpis != null) ...[
              _buildReferenceHeroPanel(
                isNarrow: isNarrow,
                kpis: kpis,
                topClient: topClient,
                topPayment: topPayment,
              ),
              const SizedBox(height: 18),
              isNarrow
                  ? Column(
                      children: [
                        _buildExecutiveMetricCard(
                          label: 'Total vendido',
                          value: kpis.totalSales,
                          tone: scheme.primary,
                          icon: Icons.point_of_sale_outlined,
                          footnote:
                              '${_formatNumber(kpis.salesCount)} ordenes procesadas',
                        ),
                        const SizedBox(height: 12),
                        _buildExecutiveMetricCard(
                          label: 'Utilidad',
                          value: kpis.netProfit,
                          tone: scheme.tertiary,
                          icon: Icons.trending_up_outlined,
                          footnote: 'Utilidad despues de costos.',
                        ),
                        const SizedBox(height: 12),
                        _buildExecutiveMetricCard(
                          label: 'Costo vendido',
                          value: kpis.totalCost,
                          tone: scheme.secondary,
                          icon: Icons.inventory_2_outlined,
                          footnote: 'Costo de los productos vendidos.',
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _buildExecutiveMetricCard(
                            label: 'Total vendido',
                            value: kpis.totalSales,
                            tone: scheme.primary,
                            icon: Icons.point_of_sale_outlined,
                            footnote:
                                '${_formatNumber(kpis.salesCount)} ordenes procesadas',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildExecutiveMetricCard(
                            label: 'Utilidad',
                            value: kpis.netProfit,
                            tone: scheme.tertiary,
                            icon: Icons.trending_up_outlined,
                            footnote: 'Utilidad despues de costos.',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildExecutiveMetricCard(
                            label: 'Costo vendido',
                            value: kpis.totalCost,
                            tone: scheme.secondary,
                            icon: Icons.inventory_2_outlined,
                            footnote: 'Costo de los productos vendidos.',
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 18),
            ],
            const SizedBox(height: 18),
            if (isNarrow)
              Column(
                children: [
                  _buildTopProductsExecutiveCard(),
                  const SizedBox(height: 14),
                  _buildSecondaryStatCard(
                    title: 'Total de ordenes',
                    value: _formatNumber(kpis?.salesCount ?? 0),
                    icon: Icons.receipt_long_outlined,
                    tone: scheme.primary,
                    caption: 'Ordenes generadas durante el periodo.',
                  ),
                  const SizedBox(height: 12),
                  _buildSecondaryStatCard(
                    title: 'Ticket promedio',
                    value: _formatCurrency(kpis?.avgTicket ?? 0),
                    icon: Icons.local_atm_outlined,
                    tone: scheme.secondary,
                    caption: 'Valor promedio por venta.',
                  ),
                  const SizedBox(height: 12),
                  _buildSecondaryStatCard(
                    title: 'Cliente principal',
                    value: topClient?.clientName ?? 'Sin datos',
                    icon: Icons.person_outline,
                    tone: scheme.tertiary,
                    caption: topClient == null
                        ? 'Sin cliente destacado en el rango.'
                        : _formatCurrency(topClient.totalSpent),
                  ),
                  const SizedBox(height: 12),
                  _buildSecondaryStatCard(
                    title: 'Metodo de pago lider',
                    value: topPayment?.method ?? 'Sin datos',
                    icon: Icons.account_balance_wallet_outlined,
                    tone: scheme.primary,
                    caption: topPayment == null
                        ? 'Sin pagos registrados.'
                        : _formatCurrency(topPayment.amount),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildTopProductsExecutiveCard()),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _buildSecondaryStatCard(
                          title: 'Total de ordenes',
                          value: _formatNumber(kpis?.salesCount ?? 0),
                          icon: Icons.receipt_long_outlined,
                          tone: scheme.primary,
                          caption: 'Ordenes generadas durante el periodo.',
                        ),
                        const SizedBox(height: 12),
                        _buildSecondaryStatCard(
                          title: 'Ticket promedio',
                          value: _formatCurrency(kpis?.avgTicket ?? 0),
                          icon: Icons.local_atm_outlined,
                          tone: scheme.secondary,
                          caption: 'Valor promedio por venta.',
                        ),
                        const SizedBox(height: 12),
                        _buildSecondaryStatCard(
                          title: 'Cliente principal',
                          value: topClient?.clientName ?? 'Sin datos',
                          icon: Icons.person_outline,
                          tone: scheme.tertiary,
                          caption: topClient == null
                              ? 'Sin cliente destacado en el rango.'
                              : _formatCurrency(topClient.totalSpent),
                        ),
                        const SizedBox(height: 12),
                        _buildSecondaryStatCard(
                          title: 'Metodo de pago lider',
                          value: topPayment?.method ?? 'Sin datos',
                          icon: Icons.account_balance_wallet_outlined,
                          tone: scheme.primary,
                          caption: topPayment == null
                              ? 'Sin pagos registrados.'
                              : _formatCurrency(topPayment.amount),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceHeroPanel({
    required bool isNarrow,
    required KpisData kpis,
    required TopClient? topClient,
    required PaymentMethodData? topPayment,
  }) {
    final brandScheme =
        ColorScheme.fromSeed(
          seedColor: ui_colors.AppColors.primaryBlue,
          brightness: Brightness.light,
        ).copyWith(
          primary: ui_colors.AppColors.primaryBlue,
          secondary: const Color(0xFF22C55E),
          tertiary: const Color(0xFF0EA5E9),
          surface: Colors.white,
          surfaceContainerHighest: const Color(0xFFEAF2FF),
          onSurface: ui_colors.AppColors.textPrimary,
          onSurfaceVariant: ui_colors.AppColors.textSecondary,
          outlineVariant: ui_colors.AppColors.borderSoft,
          error: ui_colors.AppColors.error,
        );

    final brandTheme = Theme.of(context).copyWith(
      colorScheme: brandScheme,
      scaffoldBackgroundColor: brandScheme.surface,
      cardColor: Colors.white,
      dividerColor: brandScheme.outlineVariant,
      textTheme: Theme.of(context).textTheme.apply(
        bodyColor: brandScheme.onSurface,
        displayColor: brandScheme.onSurface,
      ),
    );

    Widget summaryTile({
      required String label,
      required String value,
      required Color accent,
    }) {
      return Container(
        constraints: BoxConstraints(minWidth: isNarrow ? 120 : 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: brandScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    Widget periodBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: brandScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: brandScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              _periodLabel(),
              style: TextStyle(
                color: brandScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: brandScheme.onSurfaceVariant,
            ),
          ],
        ),
      );
    }

    final salesCount = _formatNumber(kpis.salesCount);
    final margin = kpis.totalSales > 0
        ? ((kpis.netProfit / kpis.totalSales) * 100).clamp(-999, 999)
        : 0.0;

    return Theme(
      data: brandTheme,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFFF8FBFF), Color(0xFFEDF4FF), Color(0xFFF6FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: ui_colors.AppColors.borderSoft),
          boxShadow: [
            BoxShadow(
              color: brandScheme.shadow.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ventas del periodo',
                    style: TextStyle(
                      color: brandScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatCurrency(kpis.totalSales),
                    style: TextStyle(
                      color: brandScheme.onSurface,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  periodBadge(),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 240,
                    child: SalesBarChart(
                      data: _salesSeries,
                      barColor: brandScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      summaryTile(
                        label: 'Margen',
                        value: '${margin.toStringAsFixed(1)}%',
                        accent: brandScheme.tertiary,
                      ),
                      summaryTile(
                        label: 'Ordenes',
                        value: salesCount,
                        accent: brandScheme.primary,
                      ),
                      summaryTile(
                        label: 'Utilidad',
                        value: _formatCurrency(kpis.netProfit),
                        accent: brandScheme.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 280,
                    child: PaymentMethodPieChart(data: _paymentMethods),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ventas del periodo',
                          style: TextStyle(
                            color: brandScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatCurrency(kpis.totalSales),
                          style: TextStyle(
                            color: brandScheme.onSurface,
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(children: [periodBadge()]),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 290,
                          child: SalesBarChart(
                            data: _salesSeries,
                            barColor: brandScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 26),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            summaryTile(
                              label: 'Margen',
                              value: '${margin.toStringAsFixed(1)}%',
                              accent: brandScheme.tertiary,
                            ),
                            summaryTile(
                              label: 'Ordenes',
                              value: salesCount,
                              accent: brandScheme.primary,
                            ),
                            summaryTile(
                              label: 'Utilidad',
                              value: _formatCurrency(kpis.netProfit),
                              accent: brandScheme.secondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 250,
                          child: PaymentMethodPieChart(data: _paymentMethods),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildHeroMiniInfo(
                              label: 'Ticket promedio',
                              value: _formatCurrency(kpis.avgTicket),
                              scheme: brandScheme,
                            ),
                            _buildHeroMiniInfo(
                              label: 'Cliente principal',
                              value: topClient?.clientName ?? 'Sin datos',
                              scheme: brandScheme,
                            ),
                            _buildHeroMiniInfo(
                              label: 'Metodo lider',
                              value: topPayment?.method ?? 'Sin datos',
                              scheme: brandScheme,
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

  Widget _buildHeroMiniInfo({
    required String label,
    required String value,
    required ColorScheme scheme,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveMetricCard({
    required String label,
    required double value,
    required Color tone,
    required IconData icon,
    String? footnote,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tone.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tone, size: 20),
              ),
              const Spacer(),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatCurrency(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
              fontFamily: 'Inter',
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 8),
            Text(
              footnote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecondaryStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color tone,
    String? caption,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tone.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsExecutiveCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _buildChartCard(
      title: 'Productos mas vendidos',
      subtitle: 'Productos con mayor impacto comercial en el periodo.',
      icon: Icons.workspace_premium_outlined,
      child: _topProducts.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'No hay productos destacados en este rango.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : Column(
              children: _topProducts.take(5).toList().asMap().entries.map((
                entry,
              ) {
                final index = entry.key;
                final product = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: index == 4
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color: scheme.outlineVariant.withOpacity(0.35),
                            ),
                          ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${product.totalQty.toStringAsFixed(0)} uds',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatCurrency(product.totalSales),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: scheme.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withOpacity(0.62),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}
