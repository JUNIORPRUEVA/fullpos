import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_status_theme.dart';
import '../../../core/printing/models/ticket_layout_config.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/utils/currency_display.dart';
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
import '../data/session_close_ticket_composer.dart';

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

enum _CortesHeaderAction { pickRange, showSessions, showMovements }

class _CashHistoryPageState extends State<CashHistoryPage> {
  static const double _compactMaxContentWidth = 1080;
  static const double _wideMaxContentWidth = 1240;

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

  late final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy hh:mm a');
  late final DateFormat _timeOnlyFormat = DateFormat('hh:mm a');
  late final DateFormat _dateTimeShortFormat = DateFormat('dd/MM hh:mm a');

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

  String _paymentMethodShortLabel(SaleModel sale) {
    return sale.paymentMethodCompactLabel;
  }

  EdgeInsets _contentPadding(
    BoxConstraints constraints, {
    required bool isWide,
  }) {
    const minSide = 16.0;
    final maxContentWidth = isWide
        ? _wideMaxContentWidth
        : _compactMaxContentWidth;
    final side = math.max(
      minSide,
      (constraints.maxWidth - maxContentWidth) / 2,
    );
    return EdgeInsets.fromLTRB(side, 12, side, 16);
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

  Widget _buildTopHeaderLine(
    BuildContext headerContext, {
    required bool isNarrow,
    required EdgeInsets contentPadding,
  }) {
    final theme = Theme.of(headerContext);
    final scheme = theme.colorScheme;
    final tabController = DefaultTabController.of(headerContext);

    final controlRadius = BorderRadius.circular(12);

    final searchField = SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar (ID, cajero, motivo...)',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          filled: true,
          fillColor: scheme.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: controlRadius,
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: controlRadius,
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: controlRadius,
            borderSide: BorderSide(color: scheme.primary.withOpacity(0.7)),
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

    final filterButton = SizedBox(
      height: 48,
      child: PopupMenuButton<_CortesHeaderAction>(
        tooltip: 'Filtros',
        onSelected: (value) async {
          switch (value) {
            case _CortesHeaderAction.pickRange:
              await _pickRange();
              break;
            case _CortesHeaderAction.showSessions:
              tabController.animateTo(0);
              break;
            case _CortesHeaderAction.showMovements:
              tabController.animateTo(1);
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _CortesHeaderAction.pickRange,
            child: Text('Rango de fechas'),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: _CortesHeaderAction.showSessions,
            child: Text('Ver sesiones'),
          ),
          PopupMenuItem(
            value: _CortesHeaderAction.showMovements,
            child: Text('Ver movimientos'),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: controlRadius,
            border: Border.all(color: scheme.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.filter_list, size: 20, color: scheme.onSurface),
        ),
      ),
    );

    final refreshButton = SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: _load,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Icon(Icons.refresh, size: 20, color: scheme.onSurface),
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [filterButton, const SizedBox(width: 8), refreshButton],
    );

    final row = Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 12),
        actions,
      ],
    );

    if (!isNarrow) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          contentPadding.left,
          contentPadding.top,
          contentPadding.right,
          12,
        ),
        child: row,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        contentPadding.left,
        contentPadding.top,
        contentPadding.right,
        12,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: 520, child: row),
      ),
    );
  }

  Widget _buildPageHero(
    BuildContext context, {
    required EdgeInsets contentPadding,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        contentPadding.left,
        contentPadding.top,
        contentPadding.right,
        14,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CAJA',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Movimiento de efectivo',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Consulta sesiones, entradas y salidas en una vista más compacta, limpia y fácil de revisar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.66),
                  height: 1.35,
                ),
              ),
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
              final dateTime = _dateTimeFormat;
              final money = CurrencyDisplay.currency();

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
                            'Sesión #${session.id ?? '-'}',
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
                        'Ventas de la sesión',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildSalesListSection(
                        data: data,
                        theme: theme,
                        scheme: scheme,
                        timeFormat: _timeOnlyFormat,
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
    final methodLabel = _paymentMethodShortLabel(sale);
    final breakdown = sale.isMixedPayment ? sale.paymentBreakdownLabel : '';
    return SizedBox(
      height: breakdown.isEmpty ? 40 : 54,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (breakdown.isNotEmpty)
                  Text(
                    breakdown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: scheme.onSurface.withOpacity(0.72),
                    ),
                  ),
              ],
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
    final money = CurrencyDisplay.currency();
    final dateTime = _dateTimeFormat;
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
    final sessionId = data.session.id;
    final results = await Future.wait([
      PrinterSettingsRepository.getOrCreate(),
      CompanyInfoRepository.getCurrentCompanyInfo(),
      sessionId == null
          ? Future.value(const <CategoryCashSummary>[])
          : CashRepository.listCategorySummaryForSession(sessionId),
      sessionId == null
          ? Future.value(const <SoldProductCashSummary>[])
          : CashRepository.listSoldProductsForSession(sessionId),
      sessionId == null
          ? Future.value(const <RefundItemByCategory>[])
          : CashRepository.listRefundItemsByCategoryForSession(sessionId),
    ]);
    final settings = results[0] as dynamic;
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final company = results[1] as CompanyInfo;
    final categorySummary = results[2] as List<CategoryCashSummary>;
    final soldProducts = results[3] as List<SoldProductCashSummary>;
    final refundItems = results[4] as List<RefundItemByCategory>;

    final lines = _buildClosingTicketLinesForPrint(
      layout: layout,
      company: company,
      session: data.session,
      summary: data.summary,
      closingAmount: data.closingAmount,
      note: data.note,
      movements: data.movements,
      categorySummary: categorySummary,
      soldProducts: soldProducts,
      refundItems: refundItems,
    );

    await UnifiedTicketPrinter.printCustomLines(
      lines: lines,
      ticketNumber: 'CASH-${data.session.id ?? ''}',
      includeLogo: true,
      overrideCopies: 1,
      layoutOverride: layout,
    );
  }

  List<String> _buildClosingTicketLinesForPrint({
    required TicketLayoutConfig layout,
    required CompanyInfo company,
    required CashSessionModel session,
    required CashSummaryModel summary,
    required double closingAmount,
    required String note,
    required List<CashMovementModel> movements,
    List<CategoryCashSummary> categorySummary = const <CategoryCashSummary>[],
    List<SoldProductCashSummary> soldProducts =
        const <SoldProductCashSummary>[],
    List<RefundItemByCategory> refundItems = const <RefundItemByCategory>[],
  }) {
    return SessionCloseTicketComposer.buildLines(
      layout: layout,
      companyName: company.name,
      companyRnc: company.rnc,
      companyPhone: company.primaryPhone,
      session: session,
      summary: summary,
      closingAmount: closingAmount,
      note: note,
      movements: movements,
      categorySummary: categorySummary,
      soldProducts: soldProducts,
      refundItems: refundItems,
    );
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
            !_sessions.any((session) => session.id == _selectedSession!.id)) {
          _selectedSession = null;
        }
        if (_selectedMovement != null &&
            !_movements.any(
              (movement) => movement.id == _selectedMovement!.id,
            )) {
          _selectedMovement = null;
        }
        _loading = false;
      });
    } catch (_) {
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
    if (picked == null || !mounted) return;
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
      backgroundColor: scheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1200;
          final padding = _contentPadding(constraints, isWide: isWide);
          final isNarrow = constraints.maxWidth < 720;
          final contentWidth =
              constraints.maxWidth - padding.left - padding.right;
          final sideWidth = (contentWidth * 0.32).clamp(320.0, 420.0);

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                _buildPageHero(context, contentPadding: padding),
                Builder(
                  builder: (headerContext) => _buildTopHeaderLine(
                    headerContext,
                    isNarrow: isNarrow,
                    contentPadding: padding.copyWith(top: 0),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      0,
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
    final dateTime = _dateTimeShortFormat;
    final money = CurrencyDisplay.currency();
    final status = theme.extension<AppStatusTheme>();
    final sessions = _filteredSessions;

    Widget statusChip({required String text, required Color color}) {
      return Chip(
        label: Text(text),
        padding: EdgeInsets.zero,
        backgroundColor: color.withOpacity(0.12),
        side: BorderSide(color: color.withOpacity(0.35)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'Sin sesiones en el rango seleccionado.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final success = status?.success ?? scheme.tertiary;
    final warning = status?.warning ?? scheme.secondary;
    final danger = status?.error ?? scheme.error;

    final list = ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: sessions.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: scheme.outlineVariant.withOpacity(0.35),
      ),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final isSelected = _selectedSession?.id == session.id;
        final diff = session.difference ?? 0.0;
        final opened = dateTime.format(session.openedAt);
        final closed = session.closedAt != null
            ? dateTime.format(session.closedAt!)
            : null;
        final dateLabel = closed == null
            ? '$opened -> -'
            : '$opened -> $closed';
        final idLabel = session.id?.toString() ?? '-';
        final userName = session.userName.trim();
        final headline = userName.isEmpty
            ? 'Turno #$idLabel'
            : 'Turno #$idLabel · $userName';
        final totalLabel = money.format(session.closingAmount ?? 0);
        final bool isOpen = session.closedAt == null;
        final bool hasDiff = diff != 0;
        final (statusText, statusColor) = hasDiff
            ? ('Diferencia', danger)
            : (isOpen ? ('Abierto', warning) : ('Cerrado', success));

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: isSelected
                ? scheme.primary.withOpacity(0.06)
                : Colors.transparent,
            child: InkWell(
              onTap: () => _selectSession(session, showDetails: !isWide),
              hoverColor: scheme.surfaceVariant.withOpacity(0.35),
              child: SizedBox(
                height: 54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(Icons.lock_clock, size: 18, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 4,
                        child: Text(
                          headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 4,
                        child: Text(
                          dateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withOpacity(0.68),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      statusChip(text: statusText, color: statusColor),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 130,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            totalLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: IconButton(
                          tooltip: 'Detalle',
                          icon: const Icon(Icons.chevron_right, size: 20),
                          onPressed: () => _showSessionDetails(session),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
        const SizedBox(width: 12),
        Container(width: 1, color: scheme.outlineVariant.withOpacity(0.35)),
        const SizedBox(width: 12),
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
    final money = CurrencyDisplay.currency();
    final dateTime = _dateTimeFormat;
    final status = theme.extension<AppStatusTheme>();

    Widget kvRow({required String label, required String value}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Selecciona un turno para ver el detalle.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withOpacity(0.66),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return FutureBuilder<_SessionDetailData>(
      future: _loadSessionDetail(session),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No se pudieron cargar los detalles del turno.',
              style: theme.textTheme.bodyMedium,
            ),
          );
        }

        final data = snapshot.data!;
        final diff = data.closingAmount - data.summary.expectedCash;
        final bool isOpen = data.session.closedAt == null;
        final bool hasDiff = diff != 0;
        final success = status?.success ?? scheme.tertiary;
        final warning = status?.warning ?? scheme.secondary;
        final danger = status?.error ?? scheme.error;
        final (statusText, statusColor) = hasDiff
            ? ('Diferencia', danger)
            : (isOpen ? ('Abierto', warning) : ('Cerrado', success));

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Turno #${session.id ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _reprintSession(data),
                      icon: const Icon(Icons.print, size: 18),
                      tooltip: 'Reimprimir',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: () => _showSessionDetails(session),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'Abrir detalle',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(statusText),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    padding: EdgeInsets.zero,
                    backgroundColor: statusColor.withOpacity(0.12),
                    side: BorderSide(color: statusColor.withOpacity(0.35)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 24),
                kvRow(label: 'Cajero', value: session.userName),
                kvRow(
                  label: 'Apertura',
                  value: dateTime.format(session.openedAt),
                ),
                kvRow(
                  label: 'Cierre',
                  value: session.closedAt == null
                      ? '-'
                      : dateTime.format(session.closedAt!),
                ),
                kvRow(
                  label: 'Contado',
                  value: money.format(data.closingAmount),
                ),
                kvRow(
                  label: 'Esperado',
                  value: money.format(data.summary.expectedCash),
                ),
                kvRow(label: 'Diferencia', value: money.format(diff)),
                const SizedBox(height: 12),
                _detailGrid(theme, money, data),
                if (data.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  kvRow(label: 'Nota', value: data.note.trim()),
                ],
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
    final dateTime = _dateTimeShortFormat;
    final money = CurrencyDisplay.currency();

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
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: scheme.outlineVariant.withOpacity(0.35),
      ),
      itemBuilder: (context, index) {
        final movement = movements[index];
        final isSelected = _selectedMovement?.id == movement.id;
        final isIn = movement.isIn;
        final color = isIn ? scheme.primary : scheme.error;

        final title = movement.reason;
        final meta =
            '${dateTime.format(movement.createdAt)} · Sesión #${movement.sessionId}';
        final amountLabel =
            '${isIn ? '+' : '-'}${money.format(movement.amount)}';

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: isSelected
                ? scheme.primary.withOpacity(0.06)
                : Colors.transparent,
            child: InkWell(
              onTap: () => _selectMovement(movement, showDetails: !isWide),
              hoverColor: scheme.surfaceVariant.withOpacity(0.35),
              child: SizedBox(
                height: 54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        isIn
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                        color: color,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 4,
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withOpacity(0.68),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 130,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            amountLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: IconButton(
                          tooltip: 'Detalle',
                          icon: const Icon(Icons.chevron_right, size: 20),
                          onPressed: () => _showMovementDetails(movement),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
        const SizedBox(width: 12),
        Container(width: 1, color: scheme.outlineVariant.withOpacity(0.35)),
        const SizedBox(width: 12),
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
    final money = CurrencyDisplay.currency();
    final dateTime = _dateTimeFormat;

    Widget kvRow({required String label, required String value}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (movement == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Selecciona un movimiento para ver el detalle.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withOpacity(0.66),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final isIn = movement.isIn;
    final color = isIn ? scheme.primary : scheme.error;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Movimiento',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _showMovementDetails(movement),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  tooltip: 'Abrir detalle',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${isIn ? '+' : '-'}${money.format(movement.amount)}',
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 24),
            kvRow(label: 'Motivo', value: movement.reason),
            kvRow(label: 'Tipo', value: isIn ? 'Entrada' : 'Retiro'),
            kvRow(label: 'Sesión', value: '#${movement.sessionId}'),
            kvRow(label: 'Fecha', value: dateTime.format(movement.createdAt)),
          ],
        ),
      ),
    );
  }
}
