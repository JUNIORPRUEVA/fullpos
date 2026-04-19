import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/db/database_manager.dart';
import '../../../core/utils/currency_display.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_repository.dart';

enum MovementFilter { all, income, expense }

class ExpensesOverviewPage extends StatefulWidget {
  const ExpensesOverviewPage({super.key});

  @override
  State<ExpensesOverviewPage> createState() => _ExpensesOverviewPageState();
}

class _ExpensesOverviewPageState extends State<ExpensesOverviewPage> {
  late DateTimeRange _range;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  MovementFilter _filter = MovementFilter.all;
  bool _loading = true;
  String? _error;
  List<CashMovementModel> _movements = [];

  int? _selectedMovementId;

  DateTimeRange _defaultRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
  }

  @override
  void initState() {
    super.initState();
    _range = _defaultRange();
    _loadMovements();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CashMovementModel> get _filteredMovements {
    final query = _searchQuery.trim().toLowerCase();
    return _movements.where((movement) {
      if (_filter == MovementFilter.income && !movement.isIn) return false;
      if (_filter == MovementFilter.expense && !movement.isOut) return false;
      if (query.isEmpty) return true;
      final reason = movement.reason.toLowerCase();
      final session = '#${movement.sessionId}';
      return reason.contains(query) || session.contains(query);
    }).toList();
  }

  void _syncSelection({List<CashMovementModel>? currentFiltered}) {
    final filtered = currentFiltered ?? _filteredMovements;

    if (filtered.isEmpty) {
      _selectedMovementId = null;
      return;
    }

    final currentId = _selectedMovementId;
    if (currentId == null) {
      return;
    }

    final match =
        filtered.cast<CashMovementModel?>().firstWhere(
          (m) => (m?.id ?? m?.createdAtMs) == currentId,
          orElse: () => null,
        ) ??
        filtered.first;

    _selectedMovementId = match.id ?? match.createdAtMs;
  }

  double get _totalIncome => _filteredMovements
      .where((movement) => movement.isIn)
      .fold(0.0, (sum, movement) => sum + movement.amount);

  double get _totalExpense => _filteredMovements
      .where((movement) => movement.isOut)
      .fold(0.0, (sum, movement) => sum + movement.amount);

  double get _net => _totalIncome - _totalExpense;

  Future<void> _loadMovements({bool retrying = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await CashRepository.listMovementsRange(
        from: _range.start,
        to: _range.end,
        limit: 800,
      );
      if (mounted) {
        setState(() {
          _movements = data;
          _syncSelection(currentFiltered: _filteredMovements);
          _loading = false;
        });
      }
    } on DatabaseException catch (dbError) {
      if (!retrying && _isClosedDbError(dbError)) {
        await DatabaseManager.instance.reopen(
          reason: 'expenses_overview_closed',
        );
        return _loadMovements(retrying: true);
      }
      if (mounted) {
        setState(() {
          _error = 'No se pudieron cargar los movimientos.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudieron cargar los movimientos.';
          _loading = false;
        });
      }
    }
  }

  bool _isClosedDbError(DatabaseException error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('database_closed') ||
        msg.contains('database is closed');
  }

  String _movementFilterLabel(MovementFilter filter) {
    switch (filter) {
      case MovementFilter.income:
        return 'Entradas';
      case MovementFilter.expense:
        return 'Salidas';
      case MovementFilter.all:
        return 'Todos';
    }
  }

  String _formatRangeLabel(DateTimeRange range) {
    final formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
  }

  void _updateSearchQuery(String value) {
    if (!mounted) return;
    setState(() {
      _searchQuery = value;
      _syncSelection(currentFiltered: _filteredMovements);
    });
  }

  bool _sameRange(DateTimeRange left, DateTimeRange right) {
    return left.start.millisecondsSinceEpoch ==
            right.start.millisecondsSinceEpoch &&
        left.end.millisecondsSinceEpoch == right.end.millisecondsSinceEpoch;
  }

  Future<void> _showFiltersPanel() async {
    final result = await _ExpensesFiltersSheet.show(
      context,
      initialRange: _range,
      initialFilter: _filter,
      defaultRange: _defaultRange(),
    );

    if (result == null || !mounted) return;

    final rangeChanged = !_sameRange(_range, result.range);
    final filterChanged = _filter != result.filter;

    if (!rangeChanged && !filterChanged) return;

    setState(() {
      _range = result.range;
      _filter = result.filter;
      _syncSelection(currentFiltered: _filteredMovements);
    });

    if (rangeChanged) {
      await _loadMovements();
      return;
    }

    if (mounted) {
      setState(() {
        _syncSelection(currentFiltered: _filteredMovements);
      });
    }
  }

  Future<void> _showSearchPanel() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar búsqueda',
      barrierColor: Colors.black.withOpacity(0.12),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ExpensesSearchSheet(
          controller: _searchController,
          initialValue: _searchQuery,
          onChanged: _updateSearchQuery,
          onClear: () {
            _searchController.clear();
            _updateSearchQuery('');
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _showMovementDetails(CashMovementModel movement) async {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final currency = CurrencyDisplay.currency();
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final isIncome = movement.isIn;
    final badgeColor = isIncome ? scheme.primary : scheme.error;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.paddingM,
              AppSizes.paddingM,
              AppSizes.paddingM,
              AppSizes.spaceXL,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Detalle',
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
                const SizedBox(height: AppSizes.spaceS),
                Container(
                  padding: const EdgeInsets.all(AppSizes.paddingM),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppSizes.radiusL),
                    border: Border.all(color: badgeColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isIncome ? Icons.add_circle : Icons.remove_circle,
                        color: badgeColor,
                      ),
                      const SizedBox(width: AppSizes.spaceS),
                      Expanded(
                        child: Text(
                          movement.reason,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                      Text(
                        '${isIncome ? '+' : '-'}${currency.format(movement.amount)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.spaceS),
                Wrap(
                  spacing: AppSizes.spaceS,
                  runSpacing: AppSizes.spaceS,
                  children: [
                    _pill('Tipo: ${isIncome ? 'Entrada' : 'Salida'}', scheme),
                    _pill('Sesión: #${movement.sessionId}', scheme),
                    _pill('Usuario: #${movement.userId}', scheme),
                    _pill(
                      'Fecha: ${dateFmt.format(movement.createdAt)}',
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

  void _selectMovement(
    CashMovementModel movement, {
    required bool showDetails,
  }) {
    if (!mounted) return;
    setState(() {
      _selectedMovementId = movement.id ?? movement.createdAtMs;
    });
    if (showDetails) {
      _showMovementDetails(movement);
    }
  }

  Widget _pill(String text, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingM,
        vertical: AppSizes.spaceXS,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
      ),
    );
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxWidth);
    final horizontal = ((constraints.maxWidth - contentWidth) / 2).clamp(
      12.0,
      48.0,
    );
    return EdgeInsets.fromLTRB(
      horizontal,
      AppSizes.paddingM,
      horizontal,
      AppSizes.paddingL,
    );
  }

  Widget _buildTopCompactBar({
    required ThemeData theme,
    required NumberFormat currencyFormat,
    required int count,
    required BoxConstraints constraints,
  }) {
    final rangeLabel = _formatRangeLabel(_range);
    final filterLabel = _movementFilterLabel(_filter);

    final searchButton = _HeaderActionIconButton(
      icon: Icons.search_rounded,
      tooltip: _searchQuery.trim().isEmpty
          ? 'Buscar movimientos'
          : 'Editar búsqueda',
      isActive: _searchQuery.trim().isNotEmpty,
      onTap: _showSearchPanel,
    );

    final summaryPanel = _ExpensesHeaderSummary(
      totalIncome: currencyFormat.format(_totalIncome),
      totalExpense: currencyFormat.format(_totalExpense),
      net: currencyFormat.format(_net),
      count: count.toString(),
      rangeLabel: rangeLabel,
      filterLabel: filterLabel,
    );

    final filterButton = SizedBox(
      height: 50,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showFiltersPanel,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCAD8EE)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlueDark.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: AppColors.brandBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Filtros',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlueDark.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: AppColors.surfaceLightBorder),
      ),
      child: Row(
        children: [
          searchButton,
          const SizedBox(width: 14),
          Expanded(child: summaryPanel),
          const SizedBox(width: 14),
          filterButton,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currencyFormat = CurrencyDisplay.currency();

    final filteredMovements = _filteredMovements;

    return Scaffold(
      backgroundColor: AppColors.surfaceLightVariant,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = _contentPadding(constraints);

          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopCompactBar(
                  theme: theme,
                  currencyFormat: currencyFormat,
                  count: filteredMovements.length,
                  constraints: constraints,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : _buildMovementsList(
                          theme: theme,
                          scheme: scheme,
                          currencyFormat: currencyFormat,
                          movements: filteredMovements,
                          isWide: constraints.maxWidth >= 1200,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMovementsList({
    required ThemeData theme,
    required ColorScheme scheme,
    required NumberFormat currencyFormat,
    required List<CashMovementModel> movements,
    required bool isWide,
  }) {
    if (movements.isEmpty) {
      return Center(
        child: Text(
          'No hay registros dentro del rango seleccionado.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: movements.length + 1,
      separatorBuilder: (_, index) => index == 0
          ? const SizedBox.shrink()
          : Divider(
              height: 1,
              thickness: 1,
              color: AppColors.surfaceLightBorder.withOpacity(0.65),
            ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _MovementsHeaderRow(theme: theme, scheme: scheme);
        }

        final movement = movements[index - 1];
        final id = movement.id ?? movement.createdAtMs;
        final isSelected = id == _selectedMovementId;

        return _CompactMovementRow(
          movement: movement,
          currencyFormat: currencyFormat,
          isSelected: isSelected,
          onTap: () => _selectMovement(movement, showDetails: true),
        );
      },
    );
  }
}

class _MovementsHeaderRow extends StatelessWidget {
  final ThemeData theme;
  final ColorScheme scheme;

  const _MovementsHeaderRow({required this.theme, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: AppColors.textDarkMuted,
      letterSpacing: 0.2,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceXS),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text('Tipo', style: labelStyle, maxLines: 1),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 6,
              child: Text('Motivo', style: labelStyle, maxLines: 1),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text('Fecha', style: labelStyle, maxLines: 1),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Text('Sesión', style: labelStyle, maxLines: 1),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Text('Usuario', style: labelStyle, maxLines: 1),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text(
                'Monto',
                style: labelStyle,
                maxLines: 1,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactMovementRow extends StatefulWidget {
  final CashMovementModel movement;
  final NumberFormat currencyFormat;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactMovementRow({
    required this.movement,
    required this.currencyFormat,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CompactMovementRow> createState() => _CompactMovementRowState();
}

class _CompactMovementRowState extends State<_CompactMovementRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final movement = widget.movement;
    final isIncome = movement.isIn;

    final textColor = AppColors.textDark;
    final mutedText = AppColors.textDarkMuted;

    final dateLabel = DateFormat('dd/MM/yy HH:mm').format(movement.createdAt);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.isSelected
            ? AppColors.brandBlue.withOpacity(0.055)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) {
          if (_hovered == value) return;
          setState(() => _hovered = value);
        },
        borderRadius: BorderRadius.circular(12),
        hoverColor: AppColors.brandBlue.withOpacity(0.03),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isIncome
                                ? AppColors.successLight
                                : AppColors.errorLight)
                            .withOpacity(0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isIncome ? 'ENT' : 'SAL',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isIncome ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: Text(
                  movement.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Text(
                  '#${movement.sessionId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Text(
                  movement.userId > 0 ? '#${movement.userId}' : 'General',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  '${isIncome ? '+' : '-'}${widget.currencyFormat.format(movement.amount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isIncome ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpensesHeaderSummary extends StatelessWidget {
  const _ExpensesHeaderSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.net,
    required this.count,
    required this.rangeLabel,
    required this.filterLabel,
  });

  final String totalIncome;
  final String totalExpense;
  final String net;
  final String count;
  final String rangeLabel;
  final String filterLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FAFE), Colors.white],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E2F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _CompactSummaryBadge(
                    label: 'Entradas',
                    value: totalIncome,
                    icon: Icons.south_west_rounded,
                    color: AppColors.success,
                    background: AppColors.successLight,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSummaryBadge(
                    label: 'Salidas',
                    value: totalExpense,
                    icon: Icons.north_east_rounded,
                    color: AppColors.error,
                    background: AppColors.errorLight,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSummaryBadge(
                    label: 'Neto',
                    value: net,
                    icon: Icons.account_balance_wallet_outlined,
                    color: AppColors.brandBlue,
                    background: AppColors.infoLight,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSummaryBadge(
                    label: 'Registros',
                    value: count,
                    icon: Icons.receipt_long_outlined,
                    color: AppColors.textDark,
                    background: AppColors.surfaceLightVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD9E2F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 15,
                  color: AppColors.textDarkMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textDarkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F1FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    filterLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.brandBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSummaryBadge extends StatelessWidget {
  const _CompactSummaryBadge({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.82),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textDarkMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActionIconButton extends StatelessWidget {
  const _HeaderActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? AppColors.brandBlue.withOpacity(0.55)
                    : const Color(0xFFCAD8EE),
              ),
            ),
            child: Stack(
              children: [
                Center(child: Icon(icon, size: 21, color: AppColors.brandBlue)),
                if (isActive)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
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
}

class _ExpensesSearchSheet extends StatefulWidget {
  const _ExpensesSearchSheet({
    required this.controller,
    required this.initialValue,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_ExpensesSearchSheet> createState() => _ExpensesSearchSheetState();
}

class _ExpensesSearchSheetState extends State<_ExpensesSearchSheet> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final width = math.min(size.width - 40, 620.0);

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFDCE3EE)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlueDark.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Buscar movimientos',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Busca por motivo o número de sesión sin ocupar espacio en la cabecera.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textDarkMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    onChanged: widget.onChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar motivo o sesión (#)',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: widget.controller.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                widget.onClear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      filled: true,
                      fillColor: AppColors.surfaceLightVariant,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: AppColors.surfaceLightBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: AppColors.surfaceLightBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (widget.initialValue.trim().isNotEmpty ||
                          widget.controller.text.trim().isNotEmpty)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              widget.onClear();
                              Navigator.of(context).pop();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Limpiar'),
                          ),
                        ),
                      if (widget.initialValue.trim().isNotEmpty ||
                          widget.controller.text.trim().isNotEmpty)
                        const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Listo'),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: AppColors.brandBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpensesFiltersResult {
  const _ExpensesFiltersResult({required this.range, required this.filter});

  final DateTimeRange range;
  final MovementFilter filter;
}

class _ExpensesFiltersSheet extends StatefulWidget {
  const _ExpensesFiltersSheet({
    required this.initialRange,
    required this.initialFilter,
    required this.defaultRange,
  });

  final DateTimeRange initialRange;
  final MovementFilter initialFilter;
  final DateTimeRange defaultRange;

  static Future<_ExpensesFiltersResult?> show(
    BuildContext context, {
    required DateTimeRange initialRange,
    required MovementFilter initialFilter,
    required DateTimeRange defaultRange,
  }) {
    return showGeneralDialog<_ExpensesFiltersResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar filtros',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ExpensesFiltersSheet(
          initialRange: initialRange,
          initialFilter: initialFilter,
          defaultRange: defaultRange,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<_ExpensesFiltersSheet> createState() => _ExpensesFiltersSheetState();
}

class _ExpensesFiltersSheetState extends State<_ExpensesFiltersSheet> {
  late DateTimeRange _range;
  late MovementFilter _filter;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _filter = widget.initialFilter;
  }

  String _filterLabel(MovementFilter filter) {
    switch (filter) {
      case MovementFilter.income:
        return 'Entradas';
      case MovementFilter.expense:
        return 'Salidas';
      case MovementFilter.all:
        return 'Todos';
    }
  }

  String _rangeLabel(DateTimeRange range) {
    final formatter = DateFormat('dd MMM yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
  }

  void _setQuickRange(int days) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final start = days <= 1
        ? startOfToday
        : startOfToday.subtract(Duration(days: days - 1));
    setState(() {
      _range = DateTimeRange(start: start, end: now);
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final width = math.min(
      (size.width * 0.34).clamp(390.0, 480.0),
      size.width - 20,
    );
    final height = math.min(
      (size.height - viewInsets.vertical - 8).clamp(620.0, size.height),
      size.height - 4,
    );

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: width,
            height: height,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF7FAFF), Colors.white, Color(0xFFF3F7FE)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFD7E1F1), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlueDark.withOpacity(0.14),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 16, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0D5EC3), Color(0xFF1A7FFF)],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Filtros de gastos',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Controla el rango, el tipo y actualiza la vista sin sobrecargar el encabezado.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withOpacity(0.9),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FilterSectionCard(
                            title: 'Periodo actual',
                            subtitle:
                                'Selecciona exactamente qué rango deseas revisar.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F7FE),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFD7E1F1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: AppColors.brandBlue
                                              .withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.calendar_month_rounded,
                                          color: AppColors.brandBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _rangeLabel(_range),
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.textDark,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _pickRange,
                                    icon: const Icon(Icons.date_range_rounded),
                                    label: const Text(
                                      'Elegir rango personalizado',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _QuickRangeChip(
                                      label: 'Hoy',
                                      onTap: () => _setQuickRange(1),
                                    ),
                                    _QuickRangeChip(
                                      label: '7 días',
                                      onTap: () => _setQuickRange(7),
                                    ),
                                    _QuickRangeChip(
                                      label: '30 días',
                                      onTap: () => _setQuickRange(30),
                                    ),
                                    _QuickRangeChip(
                                      label: '90 días',
                                      onTap: () => _setQuickRange(90),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _FilterSectionCard(
                            title: 'Tipo de movimiento',
                            subtitle:
                                'Reduce el ruido y enfócate solo en lo que quieres analizar.',
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: MovementFilter.values.map((filter) {
                                final selected = _filter == filter;
                                return ChoiceChip(
                                  label: Text(_filterLabel(filter)),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() => _filter = filter);
                                  },
                                  selectedColor: AppColors.brandBlue,
                                  backgroundColor: const Color(0xFFF4F7FC),
                                  side: BorderSide(
                                    color: selected
                                        ? AppColors.brandBlue
                                        : AppColors.surfaceLightBorder,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  labelStyle: theme.textTheme.bodySmall
                                      ?.copyWith(
                                        color: selected
                                            ? Colors.white
                                            : AppColors.textDarkSecondary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _FilterSectionCard(
                            title: 'Resumen de la vista',
                            subtitle:
                                'Confirma rápidamente cómo quedará aplicado el filtro.',
                            child: Column(
                              children: [
                                _FilterPreviewRow(
                                  label: 'Rango',
                                  value: _rangeLabel(_range),
                                ),
                                const SizedBox(height: 10),
                                _FilterPreviewRow(
                                  label: 'Movimiento',
                                  value: _filterLabel(_filter),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFE),
                      border: Border(top: BorderSide(color: Color(0xFFDCE3EE))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _range = widget.defaultRange;
                                _filter = MovementFilter.all;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Restablecer'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop(
                                _ExpensesFiltersResult(
                                  range: _range,
                                  filter: _filter,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Aplicar filtros'),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: AppColors.brandBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
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
          ),
        ),
      ),
    );
  }
}

class _FilterSectionCard extends StatelessWidget {
  const _FilterSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE3EE)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlueDark.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textDarkMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _QuickRangeChip extends StatelessWidget {
  const _QuickRangeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F7FE),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD7E1F1)),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.brandBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _FilterPreviewRow extends StatelessWidget {
  const _FilterPreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textDarkMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
