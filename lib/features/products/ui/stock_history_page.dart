import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_colors.dart';
import '../data/stock_repository.dart';
import '../models/stock_movement_model.dart';
import 'widgets/kpi_card.dart';
import 'widgets/products_surface.dart';

/// Historial completo de inventario (entradas, salidas y ajustes)
class StockHistoryPage extends StatefulWidget {
  const StockHistoryPage({super.key});

  @override
  State<StockHistoryPage> createState() => _StockHistoryPageState();
}

class _StockHistoryPageState extends State<StockHistoryPage> {
  final StockRepository _stockRepo = StockRepository();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final NumberFormat _qtyFormat = NumberFormat.decimalPattern();

  bool _loading = false;
  List<StockMovementDetail> _history = [];
  StockSummary? _summary;
  StockMovementType? _filterType;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final items = await _stockRepo.getDetailedHistory(
        type: _filterType,
        from: _range?.start,
        to: _range?.end,
        limit: 300,
      );
      final summary = await _stockRepo.summarize(
        type: _filterType,
        from: _range?.start,
        to: _range?.end,
      );
      if (!mounted) return;
      setState(() {
        _history = items;
        _summary = summary;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar historial: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setFilter(StockMovementType? type) {
    setState(() => _filterType = type);
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final lastMonth = now.subtract(const Duration(days: 30));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _range ?? DateTimeRange(start: lastMonth, end: now),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _range = picked);
    _load();
  }

  void _clearRange() {
    setState(() => _range = null);
    _load();
  }

  Color _movementColor(StockMovementModel m) {
    if (m.isInput) return Colors.green;
    if (m.isOutput) return Colors.red;
    return m.quantity >= 0 ? Colors.orange : Colors.deepOrange;
  }

  String _qtyLabel(StockMovementModel m) {
    if (m.isOutput) {
      return '-${_qtyFormat.format(m.quantity)}';
    }
    if (m.isInput) {
      return '+${_qtyFormat.format(m.quantity)}';
    }
    return m.quantity >= 0
        ? '+${_qtyFormat.format(m.quantity)}'
        : _qtyFormat.format(m.quantity);
  }

  Widget _buildSummary() {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();

    final widgets = <Widget>[
      SizedBox(
        width: 210,
        child: KpiCard(
          title: 'Entradas',
          value: _qtyFormat.format(summary.totalInputs),
          icon: Icons.call_made,
          color: Colors.green,
        ),
      ),
      SizedBox(
        width: 210,
        child: KpiCard(
          title: 'Salidas',
          value: _qtyFormat.format(summary.totalOutputs),
          icon: Icons.call_received,
          color: Colors.red,
        ),
      ),
      SizedBox(
        width: 210,
        child: KpiCard(
          title: 'Ajustes',
          value: summary.totalAdjustments >= 0
              ? '+${_qtyFormat.format(summary.totalAdjustments)}'
              : _qtyFormat.format(summary.totalAdjustments),
          icon: Icons.tune,
          color: summary.totalAdjustments >= 0
              ? Colors.orange
              : Colors.deepOrange,
        ),
      ),
      SizedBox(
        width: 210,
        child: KpiCard(
          title: 'Movimientos',
          value: summary.movementsCount.toString(),
          icon: Icons.timeline,
          color: Colors.blueGrey,
        ),
      ),
      SizedBox(
        width: 210,
        child: KpiCard(
          title: 'Balance neto',
          value: summary.netChange >= 0
              ? '+${_qtyFormat.format(summary.netChange)}'
              : _qtyFormat.format(summary.netChange),
          icon: Icons.equalizer,
          color: summary.netChange >= 0 ? Colors.teal : Colors.redAccent,
        ),
      ),
    ];

    return Wrap(spacing: 12, runSpacing: 12, children: widgets);
  }

  Widget _buildMovementTile(StockMovementDetail detail) {
    final movement = detail.movement;
    final color = _movementColor(movement);
    final dateLabel = _dateFormat.format(movement.createdAt.toLocal());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              movement.isInput
                  ? Icons.call_made
                  : movement.isOutput
                  ? Icons.call_received
                  : Icons.tune,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        detail.productLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _qtyLabel(movement),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        movement.type.label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    if (detail.productCode != null)
                      Text(
                        'Cód: ${detail.productCode}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$dateLabel • ${detail.userLabel}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFamily: 'Inter',
                  ),
                ),
                if (movement.note?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Nota: ${movement.note}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
                if (detail.currentStock != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Stock actual: ${_qtyFormat.format(detail.currentStock)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Inter',
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

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 900;
    final rangeLabel = _range == null
        ? null
        : '${DateFormat('dd/MM/yyyy').format(_range!.start)} - ${DateFormat('dd/MM/yyyy').format(_range!.end)}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ProductsSurface(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Todos'),
                                    selected: _filterType == null,
                                    onSelected: (_) => _setFilter(null),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Entradas'),
                                    selected:
                                        _filterType == StockMovementType.input,
                                    onSelected: (_) =>
                                        _setFilter(StockMovementType.input),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Salidas'),
                                    selected:
                                        _filterType == StockMovementType.output,
                                    onSelected: (_) =>
                                        _setFilter(StockMovementType.output),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Ajustes'),
                                    selected:
                                        _filterType == StockMovementType.adjust,
                                    onSelected: (_) =>
                                        _setFilter(StockMovementType.adjust),
                                  ),
                                ],
                              ),
                            ),
                            if (!isCompact) ...[
                              const SizedBox(width: 10),
                              FilledButton.tonalIcon(
                                onPressed: _pickRange,
                                icon: const Icon(Icons.date_range),
                                label: const Text('Rango'),
                                style: FilledButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  backgroundColor: AppColors.lightBlueHover,
                                ),
                              ),
                              if (_range != null) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: _clearRange,
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Limpiar'),
                                ),
                              ],
                            ],
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (isCompact)
                              FilledButton.tonalIcon(
                                onPressed: _pickRange,
                                icon: const Icon(Icons.date_range),
                                label: const Text('Rango'),
                                style: FilledButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  backgroundColor: AppColors.lightBlueHover,
                                ),
                              ),
                            if (isCompact && _range != null)
                              OutlinedButton.icon(
                                onPressed: _clearRange,
                                icon: const Icon(Icons.clear),
                                label: const Text('Limpiar'),
                              ),
                            if (rangeLabel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackgroundAlt,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.borderSoft,
                                  ),
                                ),
                                child: Text(
                                  rangeLabel,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ProductsSurface(child: _buildSummary()),
                  const SizedBox(height: 12),
                  ProductsSurface(
                    child: _history.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            child: const Text(
                              'Sin movimientos',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                                color: AppColors.textPrimary,
                              ),
                            ),
                          )
                        : Column(
                            children: _history.map(_buildMovementTile).toList(),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
