import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

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

  Widget _buildFilterChips(ColorScheme scheme) {
    final labels = {
      MovementFilter.all: 'Todos',
      MovementFilter.income: 'Entradas',
      MovementFilter.expense: 'Salidas',
    };

    return Wrap(
      spacing: AppSizes.spaceS,
      children: MovementFilter.values.map((filter) {
        final isSelected = _filter == filter;
        return ChoiceChip(
          label: Text(labels[filter]!),
          selected: isSelected,
          onSelected: (_) => setState(() => _filter = filter),
          selectedColor: scheme.primary,
          labelStyle: TextStyle(
            color: isSelected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummarySection(
    ThemeData theme,
    NumberFormat currencyFormat,
    ColorScheme scheme,
    BoxConstraints constraints,
  ) {
    final stats = [
      _SummaryMetric(
        label: 'Entradas',
        value: currencyFormat.format(_totalIncome),
        icon: Icons.arrow_circle_up,
        color: scheme.primary,
      ),
      _SummaryMetric(
        label: 'Salidas',
        value: currencyFormat.format(_totalExpense),
        icon: Icons.arrow_circle_down,
        color: scheme.error,
      ),
      _SummaryMetric(
        label: 'Balance neto',
        value: currencyFormat.format(_net),
        icon: _net >= 0 ? Icons.trending_up : Icons.trending_down,
        color: _net >= 0 ? scheme.primary : scheme.error,
      ),
      _SummaryMetric(
        label: 'Movimientos',
        value: _filteredMovements.length.toString(),
        icon: Icons.list_alt,
        color: scheme.secondary,
      ),
    ];

    final maxCardWidth = 280.0;
    final availableWidth =
        constraints.maxWidth -
        ((constraints.maxWidth - math.min(constraints.maxWidth, 1280.0)) / 2) *
            2 -
        AppSizes.paddingM * 2;
    final cardWidth = math.min(
      maxCardWidth,
      (availableWidth - AppSizes.spaceM * 2) / 2,
    );

    return Wrap(
      spacing: AppSizes.spaceM,
      runSpacing: AppSizes.spaceM,
      children: stats
          .map(
            (metric) => SizedBox(
              width: cardWidth,
              child: _MetricCard(
                metric: metric,
                color: scheme.surface,
                onPrimary: scheme.onSurface,
              ),
            ),
          )
          .toList(),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gastos e ingresos',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = _contentPadding(constraints);

          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickRange,
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          '${dateFormat.format(_range.start)} — ${dateFormat.format(_range.end)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceS),
                    ElevatedButton.icon(
                      onPressed: _loadMovements,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.spaceS),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar por motivo o turno (#)',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: scheme.surfaceVariant.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusL),
                      borderSide: BorderSide(
                        color: scheme.outlineVariant.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.spaceS),
                _buildFilterChips(scheme),
                const SizedBox(height: AppSizes.spaceS),
                _buildSummarySection(
                  theme,
                  currencyFormat,
                  scheme,
                  constraints,
                ),
                const SizedBox(height: AppSizes.spaceS),
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
                      : _buildHistoryList(theme, scheme, currencyFormat),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryList(
    ThemeData theme,
    ColorScheme scheme,
    NumberFormat currencyFormat,
  ) {
    final movements = _filteredMovements;

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
      separatorBuilder: (_, index) => const SizedBox(height: AppSizes.spaceS),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceXS),
            child: Row(
              children: [
                Text(
                  'Historial',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${movements.length} registros',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          );
        }

        final movement = movements[index - 1];
        final isIncome = movement.isIn;
        final color = isIncome ? scheme.primary : scheme.error;
        final dateFmt = DateFormat('dd/MM HH:mm');

        return Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          child: InkWell(
            onTap: () => _showMovementDetails(movement),
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingM,
                vertical: AppSizes.spaceS,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSizes.radiusL),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSizes.spaceS),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movement.reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '#${movement.sessionId}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(width: AppSizes.spaceS),
                            Text(
                              movement.userId > 0
                                  ? 'Usuario #${movement.userId}'
                                  : 'Usuario general',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateFmt.format(movement.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSizes.spaceS),
                  Text(
                    '${isIncome ? '+' : '-'}${currencyFormat.format(movement.amount)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SummaryMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _MetricCard extends StatelessWidget {
  final _SummaryMetric metric;
  final Color color;
  final Color onPrimary;

  const _MetricCard({
    required this.metric,
    required this.color,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.paddingM),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: onPrimary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: metric.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppSizes.radiusL),
            ),
            child: Icon(metric.icon, color: metric.color, size: 20),
          ),
          const SizedBox(width: AppSizes.spaceS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: onPrimary.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metric.value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
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
