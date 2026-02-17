import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/db/database_manager.dart';
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

  CashMovementModel? _selectedMovement;
  int? _selectedMovementId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
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
      _selectedMovement = null;
      _selectedMovementId = null;
      return;
    }

    final currentId = _selectedMovementId;
    if (currentId == null) {
      _selectedMovement = filtered.first;
      _selectedMovementId = filtered.first.id ?? filtered.first.createdAtMs;
      return;
    }

    final match =
        filtered.cast<CashMovementModel?>().firstWhere(
          (m) => (m?.id ?? m?.createdAtMs) == currentId,
          orElse: () => null,
        ) ??
        filtered.first;

    _selectedMovement = match;
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _range,
    );

    if (picked == null) return;
    if (!mounted) return;
    setState(() => _range = picked);
    await _loadMovements();
  }

  Future<void> _showMovementDetails(CashMovementModel movement) async {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
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
                    _pill('Turno: #${movement.sessionId}', scheme),
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
      _selectedMovement = movement;
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

  Widget _buildFilterChipsInline(ColorScheme scheme) {
    final theme = Theme.of(context);
    final labels = {
      MovementFilter.all: 'Todos',
      MovementFilter.income: 'Entradas',
      MovementFilter.expense: 'Salidas',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: MovementFilter.values.map((filter) {
        final isSelected = _filter == filter;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            height: 40,
            child: ChoiceChip(
              label: Text(labels[filter]!),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _filter = filter;
                  _syncSelection(currentFiltered: _filteredMovements);
                });
              },
              selectedColor: AppColors.brandBlue,
              backgroundColor: AppColors.surfaceLightVariant,
              side: BorderSide(
                color: isSelected
                    ? AppColors.brandBlue
                    : AppColors.surfaceLightBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              labelStyle: theme.textTheme.bodySmall?.copyWith(
                color: isSelected ? Colors.white : AppColors.textDarkSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTopCompactBar({
    required ThemeData theme,
    required ColorScheme scheme,
    required NumberFormat currencyFormat,
    required DateFormat dateFormat,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlueDark.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.surfaceLightBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                '${dateFormat.format(_range.start)} — ${dateFormat.format(_range.end)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.8,
                ),
              ),
              ),
            ),
            const SizedBox(width: 10),
            _buildFilterChipsInline(scheme),
            const SizedBox(width: 10),
            SizedBox(
              width: 280,
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _syncSelection(currentFiltered: _filteredMovements);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar motivo o turno (#)',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: AppColors.surfaceLightVariant,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: AppColors.surfaceLightBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: AppColors.surfaceLightBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.brandBlue),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _InlineMetricPill(
              label: 'Entradas',
              value: currencyFormat.format(_totalIncome),
              color: AppColors.success,
              background: AppColors.successLight,
            ),
            const SizedBox(width: 8),
            _InlineMetricPill(
              label: 'Salidas',
              value: currencyFormat.format(_totalExpense),
              color: AppColors.error,
              background: AppColors.errorLight,
            ),
            const SizedBox(width: 8),
            _InlineMetricPill(
              label: 'Neto',
              value: currencyFormat.format(_net),
              color: AppColors.brandBlue,
              background: AppColors.infoLight,
            ),
            const SizedBox(width: 8),
            _InlineMetricPill(
              label: 'Registros',
              value: count.toString(),
              color: scheme.secondary,
              background: AppColors.surfaceLightVariant,
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _loadMovements,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualizar'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  textStyle: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currencyFormat = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$ ',
    );
    final dateFormat = DateFormat('dd/MM/yyyy');

    final filteredMovements = _filteredMovements;

    return Scaffold(
      backgroundColor: AppColors.surfaceLightVariant,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = _contentPadding(constraints);
          final isWide = constraints.maxWidth >= 1200;
          final detailWidth = (constraints.maxWidth * 0.25).clamp(320.0, 460.0);

          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopCompactBar(
                  theme: theme,
                  scheme: scheme,
                  currencyFormat: currencyFormat,
                  dateFormat: dateFormat,
                  count: filteredMovements.length,
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
                      : isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildMovementsList(
                                theme: theme,
                                scheme: scheme,
                                currencyFormat: currencyFormat,
                                movements: filteredMovements,
                                isWide: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: detailWidth,
                              child: SizedBox.expand(
                                child: _buildMovementDetailsPanel(
                                  theme: theme,
                                  scheme: scheme,
                                  currencyFormat: currencyFormat,
                                  movement: _selectedMovement,
                                ),
                              ),
                            ),
                          ],
                        )
                      : _buildMovementsList(
                          theme: theme,
                          scheme: scheme,
                          currencyFormat: currencyFormat,
                          movements: filteredMovements,
                          isWide: false,
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
      separatorBuilder: (_, index) =>
          index == 0 ? const SizedBox.shrink() : const SizedBox(height: 12),
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
          onTap: () => _selectMovement(movement, showDetails: !isWide),
        );
      },
    );
  }

  Widget _buildMovementDetailsPanel({
    required ThemeData theme,
    required ColorScheme scheme,
    required NumberFormat currencyFormat,
    required CashMovementModel? movement,
  }) {
    if (movement == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceLightBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlueDark.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle de movimiento',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selecciona un movimiento para ver sus detalles.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    final isIncome = movement.isIn;
    final badgeColor = isIncome ? scheme.primary : scheme.error;
    final dateFmt = DateFormat('dd/MM/yy HH:mm');
    final idLabel = movement.id == null
        ? 'MOV-—'
        : 'MOV-${movement.id!.toString().padLeft(5, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLightBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlueDark.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
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
                    color: AppColors.surfaceLightVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surfaceLightBorder),
                  ),
                  child: Text(
                    idLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDarkSecondary,
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
                    color: (isIncome
                            ? AppColors.successLight
                            : AppColors.errorLight)
                        .withOpacity(0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isIncome ? 'ENTRADA' : 'SALIDA',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isIncome ? AppColors.success : AppColors.error,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              movement.reason,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              dateFmt.format(movement.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 14),
            _DetailMetric(
              label: 'Monto',
              value:
                  '${isIncome ? '+' : '-'}${currencyFormat.format(movement.amount)}',
              color: badgeColor,
              emphasize: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DetailMetric(
                    label: 'Turno',
                    value: '#${movement.sessionId}',
                    color: AppColors.textDark,
                    backgroundColor: AppColors.surfaceLightVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DetailMetric(
                    label: 'Usuario',
                    value: movement.userId > 0
                        ? '#${movement.userId}'
                        : 'General',
                    color: AppColors.textDark,
                    backgroundColor: AppColors.surfaceLightVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLightVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceLightBorder),
        ),
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
              child: Text('Turno', style: labelStyle, maxLines: 1),
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

    final bgColor = Colors.white;
    final textColor = AppColors.textDark;
    final mutedText = AppColors.textDarkMuted;

    final dateLabel = DateFormat('dd/MM/yy HH:mm').format(movement.createdAt);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isSelected
              ? AppColors.brandBlue.withOpacity(0.35)
              : AppColors.surfaceLightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlueDark.withOpacity(
              widget.isSelected ? 0.10 : (_hovered ? 0.09 : 0.06),
            ),
            blurRadius: widget.isSelected ? 18 : (_hovered ? 16 : 12),
            offset: Offset(0, _hovered ? 6 : 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) {
          if (_hovered == value) return;
          setState(() => _hovered = value);
        },
        borderRadius: BorderRadius.circular(14),
        hoverColor: AppColors.brandBlue.withOpacity(0.03),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    color: (isIncome
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

class _DetailMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool emphasize;
  final Color? backgroundColor;

  const _DetailMetric({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor ??
            (emphasize
                ? AppColors.surfaceLightVariant
                : AppColors.surfaceLight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: emphasize ? 20 : 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _InlineMetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color? background;

  const _InlineMetricPill({
    required this.label,
    required this.value,
    required this.color,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background ?? AppColors.surfaceLightVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLightBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withOpacity(0.75),
            ),
            maxLines: 1,
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
