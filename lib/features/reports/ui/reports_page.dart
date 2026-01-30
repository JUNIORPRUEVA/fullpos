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
import '../data/reports_repository.dart';
import 'widgets/date_range_selector.dart';
import 'widgets/advanced_kpi_cards.dart';
import 'widgets/sales_bar_chart.dart';
import 'widgets/payment_method_pie_chart.dart';
import 'widgets/comparative_stats_card.dart';
import 'widgets/top_products_table.dart';
import 'widgets/top_clients_table.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  DateRangePeriod _selectedPeriod = DateRangePeriod.month;
  DateTime? _customStart;
  DateTime? _customEnd;

  late TabController _tabController;
  bool _isLoading = true;
  StreamSubscription<AppEvent>? _eventsSub;

  // Data
  KpisData? _kpis;
  List<SeriesDataPoint> _salesSeries = [];
  List<SeriesDataPoint> _profitSeries = [];
  List<PaymentMethodData> _paymentMethods = [];
  List<TopProduct> _topProducts = [];
  List<TopClient> _topClients = [];
  List<SaleRecord> _salesList = [];
  Map<String, dynamic> _comparativeStats = {};
  List<CategoryPerformanceData> _categoryPerformance = [];

  final Map<String, bool> _pdfSections = {
    'kpis': true,
    'salesSeries': true,
    'paymentMethods': true,
    'profitSeries': true,
    'comparativeStats': true,
    'topProducts': true,
    'topClients': true,
    'salesList': true,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _eventsSub = AppEventBus.stream.listen((event) {
      if (event is! SaleCompletedEvent) return;

      final range = DateRangeHelper.getRangeForPeriod(
        _selectedPeriod,
        customStart: _customStart,
        customEnd: _customEnd,
      );

      final startMs = range.start.millisecondsSinceEpoch;
      final endMs = range.end.millisecondsSinceEpoch;

      final createdAtMs = event.createdAtMs;
      final isInRange = createdAtMs >= startMs && createdAtMs <= endMs;

      if (!mounted) return;
      if (isInRange) {
        _loadData();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _tabController.dispose();
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

    final categoryPerformance = await safe(
      () => ReportsRepository.getCategoryPerformance(
        startMs: startMs,
        endMs: endMs,
      ),
      <CategoryPerformanceData>[],
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
      _categoryPerformance = categoryPerformance;
      _isLoading = false;
    });
  }

  void _onPeriodChanged(DateRangePeriod period) {
    setState(() => _selectedPeriod = period);
    _loadData();
  }

  void _onCustomRangeChanged(DateTime start, DateTime end) {
    setState(() {
      _customStart = start;
      _customEnd = end;
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

    final startMs = range.start.millisecondsSinceEpoch;
    final endMs = range.end.millisecondsSinceEpoch;

    try {
      final csv = await ReportsRepository.exportToCSV(
        startMs: startMs,
        endMs: endMs,
      );

      if (mounted) {
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_isLoading) return;
    final scheme = Theme.of(context).colorScheme;

    final selected = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) {
        final temp = Map<String, bool>.from(_pdfSections);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Widget item(String key, String label) {
              return CheckboxListTile(
                value: temp[key] ?? false,
                onChanged: (v) => setStateDialog(() => temp[key] = v ?? false),
                title: Text(label),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              );
            }

            return AlertDialog(
              title: const Text('Configurar PDF'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      item('kpis', 'KPIs'),
                      item('salesSeries', 'Ventas por Período'),
                      item('paymentMethods', 'Métodos de Pago'),
                      item('profitSeries', 'Ganancias por Período'),
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
                  icon: const Icon(Icons.picture_as_pdf),
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

      // Opción 2: abrir compartir del sistema (Drive aparece si está disponible)
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

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
    final side =
        ((constraints.maxWidth - contentWidth) / 2).clamp(12.0, 40.0);
    return EdgeInsets.fromLTRB(side, 16, side, 16);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final padding = _contentPadding(constraints);
                      final isNarrow = constraints.maxWidth < 1100;
                      return _buildContent(
                        padding: padding,
                        isNarrow: isNarrow,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.go('/'),
                  tooltip: 'Volver',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHighest,
                    foregroundColor: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.tertiary],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.analytics,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard de Reportes',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      'Estadísticas y métricas del negocio',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _buildActionButton(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  color: scheme.error,
                  onPressed: _exportPdf,
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.download,
                  label: 'Exportar CSV',
                  color: scheme.primary,
                  onPressed: _exportCSV,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadData,
                  tooltip: 'Recargar datos',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primary.withOpacity(0.12),
                    foregroundColor: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DateRangeSelector(
              selectedPeriod: _selectedPeriod,
              customStart: _customStart,
              customEnd: _customEnd,
              onPeriodChanged: _onPeriodChanged,
              onCustomRangeChanged: _onCustomRangeChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }

  Widget _buildLoadingState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(scheme.primary),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Cargando datos...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Procesando estadisticas',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent({required EdgeInsets padding, required bool isNarrow}) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_kpis != null) AdvancedKpiCards(kpis: _kpis!),
          const SizedBox(height: 24),
          if (isNarrow)
            Column(
              children: [
                _buildChartCard(
                  title: 'Ventas por Periodo',
                  icon: Icons.bar_chart,
                  child: SizedBox(
                    height: 280,
                    child: SalesBarChart(
                      data: _salesSeries,
                      barColor: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildChartCard(
                  title: 'Metodos de Pago',
                  icon: Icons.pie_chart,
                  child: SizedBox(
                    height: 280,
                    child: PaymentMethodPieChart(data: _paymentMethods),
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildChartCard(
                    title: 'Ventas por Periodo',
                    icon: Icons.bar_chart,
                    child: SizedBox(
                      height: 280,
                      child: SalesBarChart(
                        data: _salesSeries,
                        barColor: scheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: _buildChartCard(
                    title: 'Metodos de Pago',
                    icon: Icons.pie_chart,
                    child: SizedBox(
                      height: 280,
                      child: PaymentMethodPieChart(data: _paymentMethods),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          if (isNarrow)
            Column(
              children: [
                _buildChartCard(
                  title: 'Ganancias por Periodo',
                  icon: Icons.trending_up,
                  child: SizedBox(
                    height: 250,
                    child: SalesBarChart(
                      data: _profitSeries,
                      barColor: scheme.tertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildChartCard(
                  title: 'Comparativa de Ventas',
                  icon: Icons.compare_arrows,
                  child: SizedBox(
                    height: 250,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ComparativeStatsCard(stats: _comparativeStats),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildChartCard(
                    title: 'Ganancias por Periodo',
                    icon: Icons.trending_up,
                    child: SizedBox(
                      height: 250,
                      child: SalesBarChart(
                        data: _profitSeries,
                        barColor: scheme.tertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: _buildChartCard(
                    title: 'Comparativa de Ventas',
                    icon: Icons.compare_arrows,
                    child: SizedBox(
                      height: 250,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ComparativeStatsCard(stats: _comparativeStats),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          _buildCategoryPerformanceCard(),
          const SizedBox(height: 24),
          _buildTabbedSection(),
        ],
      ),
    );
  }

  Widget _buildCategoryPerformanceCard() {
    final scheme = Theme.of(context).colorScheme;
    final currencyFormat = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    );

    return _buildChartCard(
      title: 'Ventas y Ganancias por Categoria',
      icon: Icons.category,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _categoryPerformance.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No hay datos por categoria en este periodo.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              )
            : Column(
                children: [
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
                      Expanded(
                        child: Text(
                          'Ganancia',
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item.itemsSold.toInt()} vendidos · ${item.itemsRefunded.toInt()} devueltos',
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
                          Expanded(
                            child: Text(
                              currencyFormat.format(item.profit),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: item.profit >= 0
                                    ? scheme.tertiary
                                    : scheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
Widget _buildChartCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
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
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
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

  Widget _buildTabbedSection() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurface.withOpacity(0.7),
              indicatorColor: scheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              tabs: [
                _buildTab(Icons.inventory_2, 'Top Productos'),
                _buildTab(Icons.people, 'Top Clientes'),
                _buildTab(Icons.receipt_long, 'Ventas'),
              ],
            ),
          ),
          SizedBox(
            height: 450,
            child: TabBarView(
              controller: _tabController,
              children: [
                TopProductsTable(products: _topProducts),
                TopClientsTable(clients: _topClients),
                _buildSalesTable(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(IconData icon, String label) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      ),
    );
  }

  Widget _buildSalesTable() {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );

    if (_salesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long,
                size: 48,
                color: scheme.onSurface.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No hay ventas para mostrar',
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.7),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Las ventas del periodo apareceran aqui',
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.08),
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  'Codigo',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Fecha',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Cliente',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Metodo',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _salesList.length > 50 ? 50 : _salesList.length,
            itemBuilder: (context, index) {
              final sale = _salesList[index];
              final date = DateTime.fromMillisecondsSinceEpoch(
                sale.createdAtMs,
              );
              final dateStr =
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sale.localCode,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        sale.customerName ?? 'Cliente General',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        money.format(sale.total),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: _buildPaymentMethodBadge(sale.paymentMethod),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_salesList.length > 50)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: scheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Text(
                  'Mostrando 50 de ${_salesList.length} ventas',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentMethodBadge(String? method) {
    final scheme = Theme.of(context).colorScheme;
    String label;
    Color color;
    IconData icon;

    switch (method?.toLowerCase()) {
      case 'cash':
      case 'efectivo':
      case null:
        label = 'Efectivo';
        color = scheme.tertiary;
        icon = Icons.payments;
        break;
      case 'card':
      case 'tarjeta':
        label = 'Tarjeta';
        color = scheme.primary;
        icon = Icons.credit_card;
        break;
      case 'transfer':
      case 'transferencia':
        label = 'Transfer';
        color = scheme.secondary;
        icon = Icons.swap_horiz;
        break;
        case 'credit':
        case 'credito':
        case 'crédito':
          label = 'Credito';
          color = scheme.error;
          icon = Icons.schedule;
          break;
        case 'layaway':
        case 'apartado':
          label = 'Apartado';
          color = scheme.secondary;
          icon = Icons.bookmark;
          break;
      default:
        label = method ?? 'N/A';
        color = scheme.outline;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}







