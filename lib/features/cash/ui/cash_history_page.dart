import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/printing/models/company_info.dart'
    show CompanyInfo, CompanyInfoRepository;
import '../../../core/printing/models/ticket_layout_config.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/utils/currency_display.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/data/sales_model.dart' show SaleModel, SaleItemModel;
import '../data/cash_movement_model.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/cash_summary_model.dart';
import '../data/session_close_ticket_composer.dart';

enum CashHistoryInitialView { sessions, movements }

class CashHistoryPage extends StatefulWidget {
  final CashHistoryInitialView initialView;

  const CashHistoryPage({
    super.key,
    this.initialView = CashHistoryInitialView.sessions,
  });

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

  EdgeInsets _contentPadding(
    BoxConstraints constraints, {
    required bool isWide,
  }) {
    const maxContentWidth = 1440.0;
    final contentWidth = math.min(constraints.maxWidth * 0.92, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(24.0, 160.0)
        .toDouble();

    return EdgeInsets.fromLTRB(side, 22, side, 24);
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
    final money = CurrencyDisplay.currency();

    double totalIn = 0;
    double totalOut = 0;
    for (final movement in _filteredMovements) {
      if (movement.isIn) {
        totalIn += movement.amount;
      } else {
        totalOut += movement.amount;
      }
    }
    final netBalance = totalIn - totalOut;

    Widget summaryBadge({
      required String label,
      required String value,
      required Color borderColor,
      Color? backgroundColor,
      Color? textColor,
    }) {
      return Expanded(
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: textColor ?? scheme.onSurface.withOpacity(0.72),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: textColor ?? scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final searchField = SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar cajero, motivo, monto, sesión...',
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: scheme.onSurface.withOpacity(0.48),
          ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1A56DB), width: 1.6),
          ),
          suffixIcon: _searchQuery.trim().isNotEmpty
              ? IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    _searchController.clear();
                    _safeSetState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              : null,
        ),
        onChanged: (value) => _safeSetState(() => _searchQuery = value),
      ),
    );

    final viewButton = SizedBox(
      height: 48,
      child: PopupMenuButton<_CortesHeaderAction>(
        tooltip: 'Vista',
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
            child: ListTile(
              dense: true,
              leading: Icon(Icons.date_range_rounded),
              title: Text('Rango de fechas'),
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: _CortesHeaderAction.showSessions,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.lock_clock_rounded),
              title: Text('Ver sesiones'),
            ),
          ),
          PopupMenuItem(
            value: _CortesHeaderAction.showMovements,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.payments_outlined),
              title: Text('Ver movimientos'),
            ),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.view_sidebar_rounded,
                size: 18,
                color: scheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Vista',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final actionsButton = SizedBox(
      height: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (value) async {
          switch (value) {
            case 'refresh':
              await _load();
              break;
            case 'range':
              await _pickRange();
              break;
            case 'sessions':
              tabController.animateTo(0);
              break;
            case 'movements':
              tabController.animateTo(1);
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'refresh',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.refresh_rounded),
              title: Text('Actualizar'),
            ),
          ),
          PopupMenuItem(
            value: 'range',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.date_range_rounded),
              title: Text('Cambiar rango'),
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: 'sessions',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.lock_clock_rounded),
              title: Text('Ver sesiones'),
            ),
          ),
          PopupMenuItem(
            value: 'movements',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.payments_outlined),
              title: Text('Ver movimientos'),
            ),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A56DB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1A56DB)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Acciones',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );

    final searchRow = Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 10),
        viewButton,
        const SizedBox(width: 8),
        actionsButton,
      ],
    );

    final summaryRow = Row(
      children: [
        summaryBadge(
          label: 'Movimientos',
          value: '${_filteredMovements.length}',
          borderColor: scheme.outlineVariant,
        ),
        const SizedBox(width: 8),
        summaryBadge(
          label: 'Entradas',
          value: money.format(totalIn),
          borderColor: scheme.primary.withOpacity(0.26),
          backgroundColor: scheme.primary.withOpacity(0.10),
          textColor: scheme.primary,
        ),
        const SizedBox(width: 8),
        summaryBadge(
          label: 'Salidas',
          value: money.format(totalOut),
          borderColor: scheme.error.withOpacity(0.22),
          backgroundColor: scheme.error.withOpacity(0.08),
          textColor: scheme.error,
        ),
        const SizedBox(width: 8),
        summaryBadge(
          label: 'Balance',
          value: money.format(netBalance),
          borderColor: scheme.outlineVariant,
        ),
      ],
    );

    return Padding(
      padding: contentPadding.copyWith(bottom: 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: LayoutBuilder(
          builder: (context, headerConstraints) {
            final stacked = headerConstraints.maxWidth < 760;

            if (stacked) {
              return Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 620, child: searchRow),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 680, child: summaryRow),
                  ),
                ],
              );
            }

            return Column(
              children: [searchRow, const SizedBox(height: 10), summaryRow],
            );
          },
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

    _safeSetState(() {
      _selectedSession = session;
      _selectedMovement = null;
    });

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar detalle del turno',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        final availableWidth = MediaQuery.of(context).size.width;
        final panelWidth = math.min(392.0, availableWidth);

        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: panelWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
              child: _buildSessionDetailsPanel(
                session,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _showMovementDetails(CashMovementModel movement) async {
    if (!mounted) return;

    _safeSetState(() {
      _selectedMovement = movement;
      _selectedSession = null;
    });

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar detalle del movimiento',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        final availableWidth = MediaQuery.of(context).size.width;
        final panelWidth = math.min(392.0, availableWidth);

        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: panelWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
              child: _buildMovementDetailsDrawer(
                movement,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1200;
        final padding = _contentPadding(constraints, isWide: isWide);
        final isNarrow = constraints.maxWidth < 720;

        return DefaultTabController(
          length: 2,
          initialIndex: widget.initialView == CashHistoryInitialView.sessions
              ? 0
              : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (headerContext) => _buildTopHeaderLine(
                  headerContext,
                  isNarrow: isNarrow,
                  contentPadding: padding,
                ),
              ),
              const SizedBox(height: 20),
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
                            _buildSessionsList(context, isWide),
                            _buildMovementsList(context, isWide),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SESIONES
  // ─────────────────────────────────────────────────────────────

  Widget _buildSessionsList(BuildContext context, bool isWide) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateTime = _dateTimeShortFormat;
    final money = CurrencyDisplay.currency();
    final status = theme.extension<AppStatusTheme>();
    final sessions = _filteredSessions;
    final mutedText = scheme.onSurface.withOpacity(0.6);

    Widget listHeader() {
      final muted = scheme.onSurface.withOpacity(0.70);

      Text label(String text, {TextAlign? align}) {
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 34,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            SizedBox(width: 32, child: label('')),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: label('Turno')),
            const SizedBox(width: 12),
            Expanded(flex: 1, child: label('Cajero')),
            const SizedBox(width: 8),
            Expanded(flex: 1, child: label('Estado')),
            const SizedBox(width: 8),
            Expanded(flex: 1, child: label('Fecha')),
            const SizedBox(width: 8),
            SizedBox(width: 128, child: label('Monto', align: TextAlign.right)),
            const SizedBox(width: 8),
            SizedBox(width: 28, child: label('', align: TextAlign.center)),
          ],
        ),
      );
    }

    Widget emptyState() {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_clock_outlined, size: 64, color: mutedText),
            const SizedBox(height: 14),
            Text(
              'Sin turnos',
              style: theme.textTheme.titleMedium?.copyWith(color: mutedText),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.trim().isNotEmpty
                  ? 'Intenta cambiar la búsqueda o el rango de fechas.'
                  : 'No hay turnos cerrados en el rango seleccionado.',
              style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final success = status?.success ?? scheme.tertiary;
    final warning = status?.warning ?? scheme.secondary;
    final danger = status?.error ?? scheme.error;

    Widget sessionRow(CashSessionModel session) {
      final isSelected = _selectedSession?.id == session.id;
      final diff = session.difference ?? 0.0;
      final opened = dateTime.format(session.openedAt);
      final closed = session.closedAt != null
          ? dateTime.format(session.closedAt!)
          : null;
      final dateLabel = closed == null ? '$opened -> -' : '$opened -> $closed';
      final idLabel = session.id?.toString() ?? '-';
      final userName = session.userName.trim();
      final cashierLabel = userName.isEmpty ? 'Usuario sin nombre' : userName;
      final totalLabel = money.format(session.closingAmount ?? 0);
      final bool isOpen = session.closedAt == null;
      final bool hasDiff = diff != 0;
      final (statusText, statusColor) = hasDiff
          ? ('Diferencia', danger)
          : (isOpen ? ('Abierto', warning) : ('Cerrado', success));

      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _selectSession(session, showDetails: true),
          borderRadius: BorderRadius.circular(12),
          hoverColor: scheme.primary.withOpacity(0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEAF2FF).withOpacity(0.82)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF8FB3FF)
                    : Colors.transparent,
                width: isSelected ? 1 : 0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1A56DB)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: statusText,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: statusColor.withOpacity(0.18)),
                    ),
                    child: Icon(
                      Icons.lock_clock_rounded,
                      color: statusColor,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Turno #$idLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: Text(
                    cashierLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Text(
                    dateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 128,
                  child: Text(
                    totalLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: scheme.onSurface.withOpacity(0.58),
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'details') {
                        _showSessionDetails(session);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'details',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.visibility_outlined, size: 18),
                          title: Text('Ver detalle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            if (sessions.isNotEmpty) ...[
              listHeader(),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: sessions.isEmpty
                  ? emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: sessions.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: scheme.outlineVariant),
                      itemBuilder: (context, index) {
                        return sessionRow(sessions[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionDetailsPanel(
    CashSessionModel? session, {
    VoidCallback? onClose,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = CurrencyDisplay.currency();
    final dateTime = _dateTimeFormat;
    final status = theme.extension<AppStatusTheme>();
    final muted = scheme.onSurface.withOpacity(0.62);
    final border = scheme.outlineVariant.withOpacity(0.85);

    Widget kvRow({required String label, required String value}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Color(0xFF1A56DB),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (session == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: border, width: 1)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Selecciona un turno para ver el detalle.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: border, width: 1)),
      ),
      child: FutureBuilder<_SessionDetailData>(
        future: _loadSessionDetail(session),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Padding(
              padding: const EdgeInsets.all(18),
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

          return Column(
            children: [
              Container(
                height: 64,
                padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Detalle del turno',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.15,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Imprimir ticket de cierre',
                      onPressed: () => _reprintSession(data),
                      icon: const Icon(Icons.print_rounded, size: 19),
                    ),
                    IconButton(
                      tooltip: 'Cerrar detalle',
                      onPressed:
                          onClose ??
                          () => _safeSetState(() => _selectedSession = null),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
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
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          padding: EdgeInsets.zero,
                          backgroundColor: statusColor.withOpacity(0.12),
                          side: BorderSide(
                            color: statusColor.withOpacity(0.35),
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 24, color: border),
                      kvRow(label: 'Cajero', value: session.userName),
                      Divider(height: 1, color: border),
                      kvRow(
                        label: 'Apertura',
                        value: dateTime.format(session.openedAt),
                      ),
                      Divider(height: 1, color: border),
                      kvRow(
                        label: 'Cierre',
                        value: session.closedAt == null
                            ? '-'
                            : dateTime.format(session.closedAt!),
                      ),
                      Divider(height: 1, color: border),
                      kvRow(
                        label: 'Contado',
                        value: money.format(data.closingAmount),
                      ),
                      Divider(height: 1, color: border),
                      kvRow(
                        label: 'Esperado',
                        value: money.format(data.summary.expectedCash),
                      ),
                      Divider(height: 1, color: border),
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
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reprintSession(_SessionDetailData data) async {
    final sessionId = data.session.id;
    if (sessionId == null) return;

    try {
      final results = await Future.wait([
        CashRepository.listCategorySummaryForSession(sessionId),
        CashRepository.listSoldProductsForSession(sessionId),
        CashRepository.listRefundItemsByCategoryForSession(sessionId),
        PrinterSettingsRepository.getOrCreate(),
        CompanyInfoRepository.getCurrentCompanyInfo(),
      ]);
      final categorySummary = results[0] as List<CategoryCashSummary>;
      final soldProducts = results[1] as List<SoldProductCashSummary>;
      final refundItems = results[2] as List<RefundItemByCategory>;
      final settings = results[3] as dynamic;
      final layout = TicketLayoutConfig.fromPrinterSettings(settings);
      final company = results[4] as CompanyInfo;

      final lines = SessionCloseTicketComposer.buildLines(
        layout: layout,
        companyName: company.name,
        companyRnc: company.rnc,
        companyPhone: company.primaryPhone,
        session: data.session,
        summary: data.summary,
        closingAmount: data.closingAmount,
        note: data.note,
        movements: data.movements,
        categorySummary: categorySummary,
        soldProducts: soldProducts,
        refundItems: refundItems,
      );

      final result = await UnifiedTicketPrinter.printCustomLines(
        lines: lines,
        ticketNumber: 'CASH-$sessionId',
        includeLogo: true,
        overrideCopies: 1,
        layoutOverride: layout,
      );

      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Ticket de cierre enviado a imprimir.'
                : result.message,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('No se pudo imprimir el ticket: $e')),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MOVIMIENTOS
  // ─────────────────────────────────────────────────────────────

  Widget _buildMovementsList(BuildContext context, bool isWide) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateTime = _dateTimeShortFormat;
    final money = CurrencyDisplay.currency();

    final movements = _filteredMovements;
    final mutedText = scheme.onSurface.withOpacity(0.6);

    Widget listHeader() {
      final muted = scheme.onSurface.withOpacity(0.70);

      Text label(String text, {TextAlign? align}) {
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 34,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            SizedBox(width: 32, child: label('')),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: label('Motivo')),
            const SizedBox(width: 12),
            Expanded(flex: 1, child: label('Cajero')),
            const SizedBox(width: 8),
            Expanded(flex: 1, child: label('Sesión')),
            const SizedBox(width: 8),
            Expanded(flex: 1, child: label('Fecha')),
            const SizedBox(width: 8),
            SizedBox(width: 128, child: label('Monto', align: TextAlign.right)),
            const SizedBox(width: 8),
            SizedBox(width: 28, child: label('', align: TextAlign.center)),
          ],
        ),
      );
    }

    Widget emptyState() {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: 64, color: mutedText),
            const SizedBox(height: 14),
            Text(
              'Sin movimientos',
              style: theme.textTheme.titleMedium?.copyWith(color: mutedText),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.trim().isNotEmpty
                  ? 'Intenta cambiar la búsqueda o el rango de fechas.'
                  : 'No hay entradas ni salidas en el rango seleccionado.',
              style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    Widget movementRow(CashMovementModel movement) {
      final isSelected = _selectedMovement?.id == movement.id;
      final isIn = movement.isIn;
      final typeColor = isIn ? scheme.primary : scheme.error;
      final typeLabel = isIn ? 'Entrada' : 'Salida';
      final amountLabel = '${isIn ? '+' : '-'}${money.format(movement.amount)}';

      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _selectMovement(movement, showDetails: true),
          borderRadius: BorderRadius.circular(12),
          hoverColor: scheme.primary.withOpacity(0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEAF2FF).withOpacity(0.82)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF8FB3FF)
                    : Colors.transparent,
                width: isSelected ? 1 : 0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1A56DB)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: typeLabel,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: typeColor.withOpacity(0.18)),
                    ),
                    child: Icon(
                      isIn
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      color: typeColor,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    movement.reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Usuario #${movement.userId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Text(
                    '#${movement.sessionId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Text(
                    dateTime.format(movement.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 128,
                  child: Text(
                    amountLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: typeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: scheme.onSurface.withOpacity(0.58),
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'details') {
                        _showMovementDetails(movement);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'details',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.visibility_outlined, size: 18),
                          title: Text('Ver detalle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            if (movements.isNotEmpty) ...[
              listHeader(),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: movements.isEmpty
                  ? emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: movements.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: scheme.outlineVariant),
                      itemBuilder: (context, index) {
                        return movementRow(movements[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DRAWER LATERAL DE DETALLE DE MOVIMIENTO (estilo Client Detail)
  // ─────────────────────────────────────────────────────────────

  Widget _buildMovementDetailsDrawer(
    CashMovementModel? movement, {
    VoidCallback? onClose,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = CurrencyDisplay.currency();
    final dateTime = _dateTimeFormat;
    final muted = scheme.onSurface.withOpacity(0.62);
    final border = scheme.outlineVariant.withOpacity(0.85);

    Widget sectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.1,
          ),
        ),
      );
    }

    Widget cleanDivider() {
      return Divider(height: 1, thickness: 1, color: border);
    }

    Widget infoLine({
      required IconData icon,
      required String label,
      required String value,
      int maxLines = 1,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: const Color(0xFF1A56DB)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget pill({
      required String text,
      required bool active,
      required IconData icon,
    }) {
      final color = active
          ? const Color(0xFF1A56DB)
          : scheme.onSurfaceVariant.withOpacity(0.85);

      return Expanded(
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? const Color(0xFFBFD1F7) : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (movement == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: border, width: 1)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Selecciona un movimiento para ver el detalle.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final isIn = movement.isIn;
    final movementColor = isIn ? const Color(0xFF1A56DB) : scheme.error;
    final typeText = isIn ? 'Entrada de efectivo' : 'Salida de efectivo';
    final amountLabel = '${isIn ? '+' : '-'}${money.format(movement.amount)}';

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: border, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Detalle del movimiento',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar detalle',
                  onPressed:
                      onClose ??
                      () => _safeSetState(() => _selectedMovement = null),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFEAF2FF),
                        foregroundColor: const Color(0xFF1A56DB),
                        child: Icon(
                          isIn
                              ? Icons.add_circle_outline_rounded
                              : Icons.remove_circle_outline_rounded,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                typeText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                movement.reason,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      pill(
                        text: isIn ? 'Entrada' : 'Salida',
                        active: true,
                        icon: isIn
                            ? Icons.add_circle_outline_rounded
                            : Icons.remove_circle_outline_rounded,
                      ),
                      const SizedBox(width: 8),
                      pill(
                        text: 'Sesión #${movement.sessionId}',
                        active: false,
                        icon: Icons.lock_clock_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Monto',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          amountLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: movementColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  sectionTitle('Datos del movimiento'),
                  infoLine(
                    icon: Icons.person_outline,
                    label: 'Cajero',
                    value: 'Usuario #${movement.userId}',
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.calendar_month_outlined,
                    label: 'Fecha y hora',
                    value: dateTime.format(movement.createdAt),
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.lock_clock_outlined,
                    label: 'Sesión',
                    value: '#${movement.sessionId}',
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.description_outlined,
                    label: 'Motivo / razón',
                    value: movement.reason,
                    maxLines: 3,
                  ),
                  sectionTitle('Auditoría'),
                  infoLine(
                    icon: Icons.person_outline,
                    label: 'Registrado por',
                    value: 'Usuario #${movement.userId}',
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.update_rounded,
                    label: 'Fecha de registro',
                    value: dateTime.format(movement.createdAt),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      'Movimiento registrado el ${dateTime.format(movement.createdAt)}.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
