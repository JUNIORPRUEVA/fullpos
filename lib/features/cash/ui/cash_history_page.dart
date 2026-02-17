import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/printing/models/receipt_text_utils.dart';
import '../../../core/printing/models/ticket_layout_config.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/printing/models/company_info.dart'
    show CompanyInfo, CompanyInfoRepository;
import '../../../core/db_hardening/db_hardening.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/data/sales_model.dart' show SaleModel, SaleItemModel;
import '../data/cash_movement_model.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/cash_summary_model.dart';

class CashHistoryPage extends StatefulWidget {
  const CashHistoryPage({super.key});

  @override
  State<CashHistoryPage> createState() => _CashHistoryPageState();
}

class _SessionDetailData {
  final CashSessionModel session;
  final CashSummaryModel summary;
  final double closingAmount;
  final String note;
  final List<SaleModel> sales;
  final Map<int, List<SaleItemModel>> saleItemsBySaleId;
  final List<CashMovementModel> movements;

  _SessionDetailData({
    required this.session,
    required this.summary,
    required this.closingAmount,
    required this.note,
    required this.sales,
    required this.saleItemsBySaleId,
    required this.movements,
  });
}

class _CashHistoryPageState extends State<CashHistoryPage> {
  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<CashSessionModel> _sessions = const [];
  List<CashMovementModel> _movements = const [];
  CashSessionModel? _selectedSession;
  CashMovementModel? _selectedMovement;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = now;
    _from = now.subtract(const Duration(days: 30));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Widget _pill(String text, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  String _paymentMethodShortLabel(String? method) {
    switch ((method ?? '').toLowerCase()) {
      case 'cash':
      case 'efectivo':
        return 'EFE';
      case 'card':
      case 'tarjeta':
        return 'TAR';
      case 'transfer':
      case 'transferencia':
        return 'TRF';
      case 'mixed':
      case 'mixto':
        return 'MIX';
      case 'credit':
      case 'credito':
        return 'CRE';
      case 'layaway':
      case 'apartado':
        return 'APA';
      default:
        return 'PAG';
    }
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2).clamp(12.0, 40.0);
    return EdgeInsets.fromLTRB(side, 12, side, 12);
  }

  String _normalizeSearch(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ü', 'u');
  }

  List<CashSessionModel> get _filteredSessions {
    final q = _normalizeSearch(_searchQuery);
    if (q.isEmpty) return _sessions;
    return _sessions
        .where((s) {
          final id = s.id?.toString() ?? '';
          final user = _normalizeSearch(s.userName);
          return id.contains(q) || user.contains(q);
        })
        .toList(growable: false);
  }

  List<CashMovementModel> get _filteredMovements {
    final q = _normalizeSearch(_searchQuery);
    if (q.isEmpty) return _movements;
    return _movements
        .where((m) {
          final reason = _normalizeSearch(m.reason);
          final sessionId = m.sessionId.toString();
          final amount = m.amount.toString();
          return reason.contains(q) ||
              sessionId.contains(q) ||
              amount.contains(q);
        })
        .toList(growable: false);
  }

  Widget _buildTopHeaderLine({required bool isNarrow}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yyyy');

    final controlRadius = BorderRadius.circular(12);
    final controlBorder = BorderSide(color: scheme.outlineVariant);

    ButtonStyle primaryControlStyle({EdgeInsetsGeometry? padding}) {
      return ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: controlRadius),
        elevation: 0,
        minimumSize: const Size(0, 42),
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      );
    }

    final rangeChip = Material(
      color: scheme.surface,
      borderRadius: controlRadius,
      child: InkWell(
        onTap: _pickRange,
        borderRadius: controlRadius,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: controlRadius,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.date_range, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '${dateFormat.format(_from)} - ${dateFormat.format(_to)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final refreshButton = ElevatedButton.icon(
      onPressed: _load,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Actualizar'),
      style: primaryControlStyle(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );

    final tabControl = SizedBox(
      height: kTextTabBarHeight,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: controlRadius,
          side: controlBorder,
        ),
        clipBehavior: Clip.antiAlias,
        child: TabBar(
          isScrollable: true,
          indicator: BoxDecoration(
            color: scheme.primary.withOpacity(0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.primary.withOpacity(0.35)),
          ),
          indicatorPadding: const EdgeInsets.all(4),
          dividerColor: Colors.transparent,
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurface.withOpacity(0.72),
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
          tabs: const [
            Tab(text: 'Turnos'),
            Tab(text: 'Movimientos'),
          ],
        ),
      ),
    );

    final searchField = SizedBox(
      width: isNarrow ? 260 : 320,
      height: 42,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar (ID, cajero, motivo...)',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(
            borderRadius: controlRadius,
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: controlRadius,
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          suffixIcon: _searchQuery.trim().isNotEmpty
              ? IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    _searchController.clear();
                    _safeSetState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear, size: 18),
                )
              : null,
        ),
        onChanged: (value) => _safeSetState(() => _searchQuery = value),
      ),
    );

    final summaryPill = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            'Turnos: ${_filteredSessions.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withOpacity(0.25)),
          ),
          child: Text(
            'Mov: ${_filteredMovements.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      color: scheme.surfaceVariant.withOpacity(0.22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.point_of_sale, color: scheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                'Cortes',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 12),
              searchField,
              const SizedBox(width: 12),
              rangeChip,
              const SizedBox(width: 10),
              summaryPill,
              const SizedBox(width: 10),
              refreshButton,
              const SizedBox(width: 10),
              tabControl,
            ],
          ),
        ),
      ),
    );
  }

  void _selectSession(CashSessionModel session, {required bool showDetails}) {
    _safeSetState(() {
      _selectedSession = session;
      _selectedMovement = null;
    });
    if (showDetails) {
      _showSessionDetails(session);
    }
  }

  void _selectMovement(
    CashMovementModel movement, {
    required bool showDetails,
  }) {
    _safeSetState(() {
      _selectedMovement = movement;
      _selectedSession = null;
    });
    if (showDetails) {
      _showMovementDetails(movement);
    }
  }

  Future<void> _showSessionDetails(CashSessionModel session) async {
    if (session.id == null) return;

    // Cargar datos completos antes de mostrar
    final detailFuture = _loadSessionDetail(session);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: FutureBuilder<_SessionDetailData>(
            future: detailFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 320,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError || snapshot.data == null) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No se pudieron cargar los detalles del corte.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }

              final data = snapshot.data!;
              final theme = Theme.of(context);
              final scheme = theme.colorScheme;
              final dateTime = DateFormat('dd/MM/yyyy HH:mm');
              final money = NumberFormat.currency(
                locale: 'es_DO',
                symbol: 'RD\$ ',
              );

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Turno #${session.id ?? '-'}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _reprintSession(data),
                            icon: const Icon(Icons.print),
                            label: const Text('Reimprimir'),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _pill('Cajero: ${session.userName}', scheme),
                          _pill(
                            'Apertura: ${dateTime.format(session.openedAt)}',
                            scheme,
                          ),
                          if (session.closedAt != null)
                            _pill(
                              'Cierre: ${dateTime.format(session.closedAt!)}',
                              scheme,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _detailGrid(theme, money, data),
                      const SizedBox(height: 16),
                      Text(
                        'Ventas del turno',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildSalesListSection(
                        data: data,
                        theme: theme,
                        scheme: scheme,
                        timeFormat: DateFormat('HH:mm'),
                        moneyFormat: money,
                      ),
                      const SizedBox(height: 12),
                      Text('Movimientos', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: data.movements.isEmpty
                            ? Center(
                                child: Text(
                                  'Sin movimientos',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              )
                            : ListView.builder(
                                itemCount: data.movements.length,
                                itemBuilder: (context, i) {
                                  final m = data.movements[i];
                                  final isIn = m.isIn;
                                  final color = isIn
                                      ? scheme.primary
                                      : scheme.error;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      isIn
                                          ? Icons.add_circle_outline
                                          : Icons.remove_circle_outline,
                                      color: color,
                                    ),
                                    title: Text(m.reason),
                                    subtitle: Text(
                                      DateFormat(
                                        'HH:mm dd/MM',
                                      ).format(m.createdAt),
                                    ),
                                    trailing: Text(
                                      '${isIn ? '+' : '-'}${money.format(m.amount)}',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: color,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSalesListSection({
    required _SessionDetailData data,
    required ThemeData theme,
    required ColorScheme scheme,
    required DateFormat timeFormat,
    required NumberFormat moneyFormat,
  }) {
    if (data.sales.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Sin ventas registradas',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final listHeight = math.min(320.0, data.sales.length * 44.0 + 12);
    return SizedBox(
      height: listHeight,
      child: ListView.separated(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: data.sales.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
        itemBuilder: (context, index) {
          final sale = data.sales[index];
          final items =
              data.saleItemsBySaleId[sale.id] ?? const <SaleItemModel>[];
          return _buildSalesItemRow(
            sale: sale,
            items: items,
            timeFormat: timeFormat,
            moneyFormat: moneyFormat,
            theme: theme,
            scheme: scheme,
          );
        },
      ),
    );
  }

  Widget _buildSalesItemRow({
    required SaleModel sale,
    required List<SaleItemModel> items,
    required DateFormat timeFormat,
    required NumberFormat moneyFormat,
    required ThemeData theme,
    required ColorScheme scheme,
  }) {
    final when = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
    final firstItemName = items.isNotEmpty
        ? items.first.productNameSnapshot
        : 'Venta';
    final displayName = firstItemName.isNotEmpty
        ? firstItemName
        : (sale.customerNameSnapshot?.trim() ?? 'Venta');
    final methodLabel = _paymentMethodShortLabel(sale.paymentMethod);
    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            timeFormat.format(when),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              methodLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            moneyFormat.format(sale.total),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMovementDetails(CashMovementModel movement) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final dateTime = DateFormat('dd/MM/yyyy HH:mm');
    final isIn = movement.isIn;
    final color = isIn ? scheme.primary : scheme.error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Movimiento',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isIn
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                        color: color,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          movement.reason,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${isIn ? '+' : '-'}${money.format(movement.amount)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _pill('Tipo: ${isIn ? 'Entrada' : 'Retiro'}', scheme),
                    _pill('Sesión: #${movement.sessionId}', scheme),
                    _pill(
                      'Fecha: ${dateTime.format(movement.createdAt)}',
                      scheme,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailGrid(
    ThemeData theme,
    NumberFormat money,
    _SessionDetailData data,
  ) {
    final items = <MapEntry<String, String>>[
      MapEntry('Apertura', money.format(data.summary.openingAmount)),
      MapEntry('Efectivo', money.format(data.summary.salesCashTotal)),
      MapEntry('Tarjeta', money.format(data.summary.salesCardTotal)),
      MapEntry('Transfer', money.format(data.summary.salesTransferTotal)),
      MapEntry('Crédito', money.format(data.summary.salesCreditTotal)),
      MapEntry('Entradas', money.format(data.summary.cashInManual)),
      MapEntry('Retiros', money.format(data.summary.cashOutManual)),
      MapEntry('Esperado', money.format(data.summary.expectedCash)),
      MapEntry('Contado', money.format(data.closingAmount)),
      MapEntry(
        'Diferencia',
        money.format(data.closingAmount - data.summary.expectedCash),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entry = items[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.key,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_SessionDetailData> _loadSessionDetail(
    CashSessionModel session,
  ) async {
    final sessionId = session.id!;
    return DbHardening.instance.runDbSafe<_SessionDetailData>(() async {
      final summary = await CashRepository.buildSummary(sessionId: sessionId);
      final movements = await CashRepository.listMovements(
        sessionId: sessionId,
      );
      final sales = await SalesRepository.listSalesBySession(sessionId);

      final saleItemsBySaleId = <int, List<SaleItemModel>>{};
      for (final sale in sales) {
        final saleId = sale.id;
        if (saleId == null) continue;
        saleItemsBySaleId[saleId] = await SalesRepository.getItemsBySaleId(
          saleId,
        );
      }

      final closingAmount = session.closingAmount ?? summary.expectedCash;
      final note = session.note ?? '';

      return _SessionDetailData(
        session: session,
        summary: summary,
        closingAmount: closingAmount,
        note: note,
        sales: sales,
        saleItemsBySaleId: saleItemsBySaleId,
        movements: movements,
      );
    }, stage: 'cash_history/session_detail');
  }

  Future<void> _reprintSession(_SessionDetailData data) async {
    final settings = await PrinterSettingsRepository.getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final company = await CompanyInfoRepository.getCurrentCompanyInfo();

    final lines = _buildClosingTicketLinesForPrint(
      layout: layout,
      company: company,
      session: data.session,
      summary: data.summary,
      closingAmount: data.closingAmount,
      note: data.note,
      sales: data.sales,
      saleItemsBySaleId: data.saleItemsBySaleId,
      movements: data.movements,
    );

    await UnifiedTicketPrinter.printCustomLines(
      lines: lines,
      ticketNumber: 'CASH-${data.session.id ?? ''}',
      includeLogo: true,
      overrideCopies: settings.copies,
    );
  }

  List<String> _buildClosingTicketLinesForPrint({
    required TicketLayoutConfig layout,
    required CompanyInfo company,
    required CashSessionModel session,
    required CashSummaryModel summary,
    required double closingAmount,
    required String note,
    required List<SaleModel> sales,
    required Map<int, List<SaleItemModel>> saleItemsBySaleId,
    required List<CashMovementModel> movements,
  }) {
    final w = layout.maxCharsPerLine;
    final lines = <String>[];
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    String sanitize(String text) => _sanitizeTicketText(text);
    String fit(String text) => ReceiptText.fitText(sanitize(text), w);
    String line() => ReceiptText.line(width: w);

    String center(String text) {
      final cleaned = sanitize(text);
      if (cleaned.length >= w) return cleaned.substring(0, w);
      final left = ((w - cleaned.length) / 2).floor();
      final right = w - cleaned.length - left;
      return ' ' * left + cleaned + ' ' * right;
    }

    String twoCols(String left, String right) {
      final rightWidth = 14.clamp(6, w - 2);
      final leftWidth = (w - rightWidth - 1).clamp(0, w);
      final leftText = ReceiptText.padRight(sanitize(left), leftWidth);
      final rightText = ReceiptText.padLeft(sanitize(right), rightWidth);
      return ReceiptText.fitText('$leftText $rightText', w);
    }

    String money(double value) => 'RD\$ ${ReceiptText.money(value)}';

    String fmtDuration(Duration d) {
      final totalMinutes = d.inMinutes;
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours <= 0) return '${minutes}m';
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }

    if (company.name.trim().isNotEmpty) {
      lines.add('<H2C>${sanitize(company.name.toUpperCase())}');
    }
    final headerParts = <String>[];
    if ((company.rnc ?? '').trim().isNotEmpty) {
      headerParts.add('RNC: ${company.rnc!.trim()}');
    }
    if ((company.primaryPhone ?? '').trim().isNotEmpty) {
      headerParts.add('TEL: ${company.primaryPhone!.trim()}');
    }
    if (headerParts.isNotEmpty) {
      lines.add(center(headerParts.join('  ')));
    }

    lines.add(line());
    lines.add('<H2C>CORTE DE CAJA');
    lines.add(line());
    lines.add('<BL>${twoCols('Sesion', '#${session.id ?? ''}')}');
    lines.add('<BL>${twoCols('Cajero', session.userName)}');
    lines.add('<BL>${twoCols('Apertura', fmt.format(session.openedAt))}');
    if (session.closedAt != null) {
      lines.add('<BL>${twoCols('Cierre', fmt.format(session.closedAt!))}');
    }
    final end = session.closedAt ?? DateTime.now();
    final duration = end.difference(session.openedAt);
    if (duration.inMinutes >= 1) {
      lines.add('<BL>${twoCols('Duracion', fmtDuration(duration))}');
    }
    lines.add(line());

    lines.add('<BL>${twoCols('Saldo inicial', money(summary.openingAmount))}');
    lines.add(
      '<BL>${twoCols('Ventas efectivo', money(summary.salesCashTotal))}',
    );
    lines.add(
      '<BL>${twoCols('Ventas tarjeta', money(summary.salesCardTotal))}',
    );
    lines.add(
      '<BL>${twoCols('Ventas transferencia', money(summary.salesTransferTotal))}',
    );
    lines.add(
      '<BL>${twoCols('Ventas credito', money(summary.salesCreditTotal))}',
    );
    if (summary.refundsCash > 0) {
      lines.add('<BL>${twoCols('Devoluciones', money(summary.refundsCash))}');
    }
    if (summary.creditAbonos > 0) {
      lines.add(
        '<BL>${twoCols('Abonos crédito', money(summary.creditAbonos))}',
      );
    }
    if (summary.layawayAbonos > 0) {
      lines.add(
        '<BL>${twoCols('Abonos apartado', money(summary.layawayAbonos))}',
      );
    }
    final manualNoAbonos =
        (summary.cashInManual - summary.creditAbonos - summary.layawayAbonos)
            .clamp(0.0, double.infinity);
    lines.add('<BL>${twoCols('Entradas manuales', money(manualNoAbonos))}');
    lines.add(
      '<BL>${twoCols('Retiros manuales', money(summary.cashOutManual))}',
    );
    lines.add(line());
    lines.add(
      '<BL>${twoCols('Efectivo esperado', money(summary.expectedCash))}',
    );
    lines.add('<BL>${twoCols('Efectivo contado', money(closingAmount))}');
    lines.add(
      '<BL>${twoCols('Diferencia', money(closingAmount - summary.expectedCash))}',
    );
    lines.add(line());

    if (note.trim().isNotEmpty) {
      lines.add(fit('Nota:'));
      final wrapped = ReceiptText.wrapText(
        sanitize(note.trim()),
        (w - 2).clamp(1, w),
      );
      for (final lineText in wrapped) {
        lines.add(fit('  $lineText'));
      }
      lines.add(line());
    }

    lines.add('<H2C>MOVIMIENTOS DEL TURNO');
    lines.add(line());
    if (movements.isEmpty) {
      lines.add(center('Sin movimientos'));
    } else {
      final timeFmt = DateFormat('HH:mm');
      for (final m in movements) {
        final sign = m.isIn ? '+' : '-';
        final right = '$sign${money(m.amount)}';
        final left = '${timeFmt.format(m.createdAt)} ${m.reason}';
        lines.add(twoCols(left, right));
      }
      lines.add(line());
      lines.add(
        '<BL>${twoCols('Total entradas', money(summary.cashInManual))}',
      );
      lines.add(
        '<BL>${twoCols('Total retiros', money(summary.cashOutManual))}',
      );
    }

    String methodAbbr(String? method) {
      final m = (method ?? '').trim().toLowerCase();
      switch (m) {
        case 'cash':
        case 'efectivo':
          return 'EFE';
        case 'card':
        case 'tarjeta':
          return 'TAR';
        case 'transfer':
        case 'transferencia':
          return 'TRF';
        case 'credit':
        case 'credito':
          return 'CRE';
        case 'mixed':
        case 'mixto':
          return 'MIX';
        default:
          if (m.isEmpty) return '---';
          final up = sanitize(m.toUpperCase());
          return up.substring(0, math.min(3, up.length));
      }
    }

    String saleRow({
      required String time,
      required String name,
      required String method,
      required String total,
    }) {
      final timeWidth = 5;
      final methodWidth = 3;
      final int totalWidth = (14).clamp(10, w - 10).toInt();
      final int nameWidth = (w - timeWidth - methodWidth - totalWidth - 3)
          .clamp(8, w)
          .toInt();

      final t = ReceiptText.padRight(sanitize(time), timeWidth);
      final c = ReceiptText.padRight(sanitize(name), nameWidth);
      final m = ReceiptText.padRight(sanitize(method), methodWidth);
      final a = ReceiptText.padLeft(sanitize(total), totalWidth);
      return ReceiptText.fitText('$t $c $m $a', w);
    }

    lines.add('<H2C>VENTAS DEL TURNO');
    lines.add(line());
    if (sales.isEmpty) {
      lines.add(center('Sin ventas registradas'));
    } else {
      final sorted = [...sales]
        ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));

      lines.add(
        '<BL>${saleRow(time: 'HORA', name: 'PRODUCTO', method: 'MET', total: 'TOTAL')}',
      );
      lines.add(ReceiptText.line(char: '=', width: w));

      final timeFmt = DateFormat('HH:mm');
      for (final sale in sorted) {
        final when = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
        final items = saleItemsBySaleId[sale.id ?? -1];
        final firstItemName = (items != null && items.isNotEmpty)
            ? items.first.productNameSnapshot.trim()
            : '';
        final customerName = (sale.customerNameSnapshot ?? '').trim();
        final displayName = firstItemName.isNotEmpty
            ? firstItemName
            : customerName;
        lines.add(
          saleRow(
            time: timeFmt.format(when),
            name: displayName.isNotEmpty ? displayName : 'Venta',
            method: methodAbbr(sale.paymentMethod),
            total: money(sale.total),
          ),
        );
      }
    }
    lines.add(line());

    lines.add('<H2C>TOTALES');
    lines.add(line());
    lines.add('<BL>${twoCols('Tickets', summary.totalTickets.toString())}');
    lines.add('<BL>${twoCols('Total ventas', money(summary.totalSales))}');
    lines.add('');
    lines.add('<H2C>TOTAL VENTAS');
    lines.add('<H1C>${money(summary.totalSales)}');
    lines.add('');
    lines.add('<H2C>EFECTIVO ESPERADO');
    lines.add('<H1C>${money(summary.expectedCash)}');
    lines.add('');
    lines.add('<H2C>EFECTIVO CONTADO');
    lines.add('<H1C>${money(closingAmount)}');
    lines.add('');
    lines.add('<H2C>DIFERENCIA');
    lines.add('<H1C>${money(closingAmount - summary.expectedCash)}');

    lines.add(line());
    lines.add(fit('Firma cajero: _______________________'));

    if (layout.autoCut) {
      lines.add('');
      lines.add('');
      lines.add('');
    }

    return lines;
  }

  String _sanitizeTicketText(String input) {
    final s = input
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C');

    final filtered = s.replaceAll(
      RegExp(r'''[^A-Za-z0-9\s\-_/.:,()#%+*&@'"'>$<]+'''),
      '',
    );
    return filtered.trim();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await DbHardening.instance.runDbSafe<List<Object>>(
        () async {
          final data = await Future.wait([
            CashRepository.listClosedSessions(from: _from, to: _to, limit: 200),
            CashRepository.listMovementsRange(from: _from, to: _to, limit: 400),
          ]);
          return data;
        },
        stage: 'cash_history/load',
      );

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _sessions = results[0] as List<CashSessionModel>;
        _movements = results[1] as List<CashMovementModel>;
        if (_selectedSession != null &&
            !_sessions.any((s) => s.id == _selectedSession!.id)) {
          _selectedSession = null;
        }
        if (_selectedMovement != null &&
            !_movements.any((m) => m.id == _selectedMovement!.id)) {
          _selectedMovement = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _error = 'No se pudieron cargar los cortes y movimientos.';
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        toolbarHeight: 8,
        elevation: 0,
        surfaceTintColor: scheme.surface,
      ),
      backgroundColor: scheme.surface.withOpacity(0.98),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = _contentPadding(constraints);
          final isWide = constraints.maxWidth >= 1200;
          final isNarrow = constraints.maxWidth < 720;
          final sideWidth = (constraints.maxWidth * 0.25).clamp(320.0, 460.0);

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                _buildTopHeaderLine(isNarrow: isNarrow),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      12,
                      padding.right,
                      padding.bottom,
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          )
                        : TabBarView(
                            children: [
                              _buildSessionsList(context, isWide, sideWidth),
                              _buildMovementsList(context, isWide, sideWidth),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionsList(
    BuildContext context,
    bool isWide,
    double sideWidth,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateTime = DateFormat('dd/MM HH:mm');
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');

    final sessions = _filteredSessions;
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'Sin cortes en el rango seleccionado.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final list = ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: sessions.length,
      separatorBuilder: (_, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final isSelected = _selectedSession?.id == session.id;
        final diff = session.difference ?? 0.0;
        final diffColor = diff == 0
            ? scheme.onSurface.withOpacity(0.58)
            : (diff > 0 ? scheme.tertiary : scheme.error);
        final diffBg = diff == 0
            ? scheme.surfaceVariant.withOpacity(0.45)
            : (diff > 0
                  ? scheme.tertiary.withOpacity(0.14)
                  : scheme.error.withOpacity(0.14));
        final rowBorderColor = scheme.outlineVariant.withOpacity(0.55);

        final opened = dateTime.format(session.openedAt);
        final closed = session.closedAt != null
            ? dateTime.format(session.closedAt!)
            : null;
        final headline = StringBuffer()..write('Turno #${session.id ?? '-'}');
        final userName = session.userName.trim();
        if (userName.isNotEmpty) {
          headline.write('  ·  $userName');
        }
        headline.write('  ·  $opened');
        if (closed != null) {
          headline.write(' → $closed');
        }
        final totalLabel = money.format(session.closingAmount ?? 0);

        return InkWell(
          onTap: () => _selectSession(session, showDetails: !isWide),
          borderRadius: BorderRadius.circular(16),
          hoverColor: scheme.primary.withOpacity(0.08),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? scheme.primary : rowBorderColor,
                width: isSelected ? 1.3 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(isSelected ? 0.12 : 0.07),
                  blurRadius: isSelected ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_clock,
                    color: scheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    headline.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isWide ? 260 : 220),
                      child: LayoutBuilder(
                        builder: (context, trailingConstraints) {
                          final compact = trailingConstraints.maxWidth < 180;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 8 : 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: diffBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: diffColor.withOpacity(0.25),
                                    ),
                                  ),
                                  child: Text(
                                    'Dif ${money.format(diff)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: diffColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: compact ? 8 : 12),
                              Flexible(
                                child: Text(
                                  totalLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: compact ? 15 : 17,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                              if (!compact) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.chevron_right, color: scheme.outline),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!isWide) return list;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        const SizedBox(width: 16),
        SizedBox(
          width: sideWidth,
          child: _buildSessionDetailsPanel(_selectedSession),
        ),
      ],
    );
  }

  Widget _buildSessionDetailsPanel(CashSessionModel? session) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final dateTime = DateFormat('dd/MM/yyyy HH:mm');

    if (session == null || session.id == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.analytics_outlined,
                color: scheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Detalle del turno',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Selecciona un turno para ver la información.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.66),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<_SessionDetailData>(
      future: _loadSessionDetail(session),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              'No se pudieron cargar los detalles del turno.',
              style: theme.textTheme.bodyMedium,
            ),
          );
        }

        final data = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Turno #${session.id ?? '-'}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _reprintSession(data),
                      icon: const Icon(Icons.print, size: 18),
                      tooltip: 'Reimprimir',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _pill('Cajero: ${session.userName}', scheme),
                    _pill(
                      'Apertura: ${dateTime.format(session.openedAt)}',
                      scheme,
                    ),
                    if (session.closedAt != null)
                      _pill(
                        'Cierre: ${dateTime.format(session.closedAt!)}',
                        scheme,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _detailGrid(theme, money, data),
                const SizedBox(height: 14),
                Text(
                  'Ventas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _buildSalesListSection(
                  data: data,
                  theme: theme,
                  scheme: scheme,
                  timeFormat: DateFormat('HH:mm'),
                  moneyFormat: money,
                ),
                const SizedBox(height: 14),
                Text(
                  'Movimientos',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: data.movements.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 22,
                                color: scheme.onSurface.withOpacity(0.45),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Sin movimientos registrados',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface.withOpacity(0.58),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: data.movements.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: scheme.outlineVariant.withOpacity(0.35),
                          ),
                          itemBuilder: (context, i) {
                            final movement = data.movements[i];
                            final isIn = movement.isIn;
                            final color = isIn ? scheme.primary : scheme.error;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Icon(
                                    isIn
                                        ? Icons.add_circle_outline
                                        : Icons.remove_circle_outline,
                                    size: 16,
                                    color: color,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      movement.reason,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${isIn ? '+' : '-'}${money.format(movement.amount)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMovementsList(
    BuildContext context,
    bool isWide,
    double sideWidth,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateTime = DateFormat('dd/MM HH:mm');
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');

    final movements = _filteredMovements;
    if (movements.isEmpty) {
      return Center(
        child: Text(
          'Sin movimientos en el rango seleccionado.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final list = ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: movements.length,
      separatorBuilder: (_, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final movement = movements[index];
        final isIn = movement.isIn;
        final color = isIn ? scheme.primary : scheme.error;
        final isSelected = _selectedMovement?.id == movement.id;
        final rowBorderColor = scheme.outlineVariant.withOpacity(0.65);

        final title =
            '${movement.reason}  ·  ${dateTime.format(movement.createdAt)}';
        return InkWell(
          onTap: () => _selectMovement(movement, showDetails: !isWide),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? scheme.primary : rowBorderColor,
                width: isSelected ? 1.2 : 0.9,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isIn ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${isIn ? '+' : '-'}${money.format(movement.amount)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!isWide) return list;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        const SizedBox(width: 16),
        SizedBox(
          width: sideWidth,
          child: _buildMovementDetailsPanel(_selectedMovement),
        ),
      ],
    );
  }

  Widget _buildMovementDetailsPanel(CashMovementModel? movement) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final dateTime = DateFormat('dd/MM/yyyy HH:mm');

    if (movement == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle del movimiento',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Selecciona un movimiento para ver la información.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.66),
              ),
            ),
          ],
        ),
      );
    }

    final isIn = movement.isIn;
    final color = isIn ? scheme.primary : scheme.error;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Movimiento',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  isIn ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    movement.reason,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${isIn ? '+' : '-'}${money.format(movement.amount)}',
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _pill('Tipo: ${isIn ? 'Entrada' : 'Retiro'}', scheme),
              _pill('Sesión: #${movement.sessionId}', scheme),
              _pill('Fecha: ${dateTime.format(movement.createdAt)}', scheme),
            ],
          ),
        ],
      ),
    );
  }
}
