import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/reports_repository.dart';
import 'widgets/date_range_selector.dart';

class ClientSalesReportPage extends StatefulWidget {
  const ClientSalesReportPage({super.key});

  @override
  State<ClientSalesReportPage> createState() => _ClientSalesReportPageState();
}

class _ClientSalesReportPageState extends State<ClientSalesReportPage> {
  DateRangePeriod _selectedPeriod = DateRangePeriod.month;
  DateTime? _customStart;
  DateTime? _customEnd;

  bool _isLoading = true;
  List<ClientSalesSummary> _clientSummaries = [];
  List<TopProduct> _topProducts = [];
  TopClient? _topClient;
  List<SaleRecord> _selectedClientSales = [];
  ClientSalesSummary? _selectedClient;

  @override
  void initState() {
    super.initState();
    _loadData();
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

    try {
      final results = await Future.wait([
        ReportsRepository.getClientSalesSummaries(
          startMs: startMs,
          endMs: endMs,
        ),
        ReportsRepository.getTopProducts(
          startMs: startMs,
          endMs: endMs,
          limit: 10,
        ),
        ReportsRepository.getTopClients(
          startMs: startMs,
          endMs: endMs,
          limit: 1,
        ),
      ]);

      final clientSummaries = results[0] as List<ClientSalesSummary>;
      final topProducts = results[1] as List<TopProduct>;
      final topClients = results[2] as List<TopClient>;

      ClientSalesSummary? selected = _selectedClient;
      if (clientSummaries.isEmpty) {
        selected = null;
      } else if (selected == null) {
        selected = clientSummaries.first;
      } else {
        try {
          selected = clientSummaries.firstWhere(
            (c) => c.clientId == selected!.clientId,
          );
        } catch (_) {
          selected = clientSummaries.first;
        }
      }
      selected ??= clientSummaries.isNotEmpty ? clientSummaries.first : null;

      List<SaleRecord> selectedSales = [];
      if (selected != null) {
        selectedSales = await ReportsRepository.getSalesListByClient(
          clientId: selected.clientId,
          startMs: startMs,
          endMs: endMs,
          limit: 40,
        );
      }

      if (!mounted) return;
      setState(() {
        _clientSummaries = clientSummaries;
        _topProducts = topProducts;
        _topClient = topClients.isNotEmpty ? topClients.first : null;
        _selectedClient = selected;
        _selectedClientSales = selectedSales;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectClient(ClientSalesSummary summary) async {
    final range = DateRangeHelper.getRangeForPeriod(
      _selectedPeriod,
      customStart: _customStart,
      customEnd: _customEnd,
    );

    final sales = await ReportsRepository.getSalesListByClient(
      clientId: summary.clientId,
      startMs: range.start.millisecondsSinceEpoch,
      endMs: range.end.millisecondsSinceEpoch,
      limit: 40,
    );

    if (!mounted) return;
    setState(() {
      _selectedClient = summary;
      _selectedClientSales = sales;
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
        final date = DateFormat('dd/MM/yyyy');
        if (_customStart != null && _customEnd != null) {
          return '${date.format(_customStart!)} - ${date.format(_customEnd!)}';
        }
        return 'Personalizado';
    }
  }

  Widget _headerBadge(
    BuildContext context,
    String text,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 1120;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 980;
                  final titleRow = Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        tooltip: 'Volver',
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.surfaceContainerHighest,
                          minimumSize: const Size(36, 36),
                          padding: const EdgeInsets.all(8),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: scheme.tertiary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.tertiary.withOpacity(0.18),
                          ),
                        ),
                        child: Icon(
                          Icons.people_alt_outlined,
                          color: scheme.tertiary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ventas por cliente',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  );

                  final reloadButton = OutlinedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Recargar'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );

                  final statusBadges = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _headerBadge(
                        context,
                        _periodLabel(),
                        Icons.calendar_today_outlined,
                        scheme.primary,
                      ),
                      _headerBadge(
                        context,
                        '${_clientSummaries.length} clientes',
                        Icons.people_outline,
                        scheme.tertiary,
                      ),
                      _headerBadge(
                        context,
                        '${_selectedClientSales.length} movimientos',
                        Icons.receipt_long_outlined,
                        scheme.secondary,
                      ),
                    ],
                  );

                  final selectorRow = stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DateRangeSelector(
                              selectedPeriod: _selectedPeriod,
                              customStart: _customStart,
                              customEnd: _customEnd,
                              onPeriodChanged: _onPeriodChanged,
                              onCustomRangeChanged: _onCustomRangeChanged,
                            ),
                            const SizedBox(height: 8),
                            statusBadges,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DateRangeSelector(
                                selectedPeriod: _selectedPeriod,
                                customStart: _customStart,
                                customEnd: _customEnd,
                                onPeriodChanged: _onPeriodChanged,
                                onCustomRangeChanged: _onCustomRangeChanged,
                              ),
                            ),
                            const SizedBox(width: 10),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: statusBadges,
                              ),
                            ),
                          ],
                        );

                  return Column(
                    children: [
                      if (stacked) ...[
                        titleRow,
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: reloadButton,
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(child: titleRow),
                            reloadButton,
                          ],
                        ),
                      const SizedBox(height: 10),
                      selectorRow,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: isWide
                    ? Row(
                        children: [
                          Expanded(flex: 2, child: _buildGeneralPanel(context)),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: _buildClientDetailPanel(context),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _buildGeneralPanel(context)),
                          const SizedBox(height: 12),
                          Expanded(child: _buildClientDetailPanel(context)),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralPanel(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );

    final totalSales = _clientSummaries.fold<double>(
      0,
      (sum, item) => sum + item.totalSales,
    );
    final totalCredits = _clientSummaries.fold<double>(
      0,
      (sum, item) => sum + item.totalCredit,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = constraints.maxWidth >= 420
              ? (constraints.maxWidth - 8) / 2
              : constraints.maxWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resumen general',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _statTile(
                      context,
                      'Ventas totales',
                      money.format(totalSales),
                      Icons.payments,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _statTile(
                      context,
                      'Créditos totales',
                      money.format(totalCredits),
                      Icons.credit_card,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _statTile(
                      context,
                      'Clientes con compras',
                      _clientSummaries.length.toString(),
                      Icons.people,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _statTile(
                      context,
                      'Cliente top',
                      _topClient == null
                          ? '-'
                          : '${_topClient!.clientName} · ${money.format(_topClient!.totalSpent)}',
                      Icons.workspace_premium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Productos más vendidos',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _topProducts.isEmpty
                    ? Center(
                        child: Text(
                          'Sin datos en el rango seleccionado.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _topProducts.length,
                        separatorBuilder: (_, _) => Divider(
                          color: scheme.outlineVariant.withOpacity(0.6),
                          height: 10,
                        ),
                        itemBuilder: (context, index) {
                          final item = _topProducts[index];
                          return Row(
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '${index + 1}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.totalQty.toStringAsFixed(0)} u',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClientDetailPanel(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );
    final date = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;

          Widget clientList() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clientes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _clientSummaries.isEmpty
                      ? Center(
                          child: Text(
                            'No hay ventas por cliente en este rango.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _clientSummaries.length,
                          itemBuilder: (context, index) {
                            final item = _clientSummaries[index];
                            final selected =
                                item.clientId == _selectedClient?.clientId;
                            return InkWell(
                              onTap: () => _selectClient(item),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? scheme.primary.withOpacity(0.10)
                                      : scheme.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? scheme.primary.withOpacity(0.60)
                                        : scheme.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.clientName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${money.format(item.totalSales)} · ${item.salesCount} ventas',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          }

          Widget detailList() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedClient?.clientName ?? 'Detalle del cliente',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (_selectedClient != null) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pill(context, 'Ventas: ${_selectedClient!.salesCount}'),
                      _pill(
                        context,
                        'Total: ${money.format(_selectedClient!.totalSales)}',
                      ),
                      _pill(
                        context,
                        'Crédito: ${money.format(_selectedClient!.totalCredit)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Expanded(
                  child: _selectedClientSales.isEmpty
                      ? Center(
                          child: Text(
                            'Sin facturas para el cliente en este rango.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _selectedClientSales.length,
                          separatorBuilder: (_, _) => Divider(
                            color: scheme.outlineVariant.withOpacity(0.6),
                            height: 10,
                          ),
                          itemBuilder: (context, index) {
                            final sale = _selectedClientSales[index];
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sale.localCode,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${sale.kind == 'return' ? 'Devolución' : 'Factura'} • ${date.format(DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs))}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  money.format(sale.total),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            );
          }

          if (stacked) {
            return Column(
              children: [
                Expanded(child: clientList()),
                const SizedBox(height: 12),
                Expanded(child: detailList()),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 2, child: clientList()),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: detailList()),
            ],
          );
        },
      ),
    );
  }

  Widget _statTile(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: scheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
