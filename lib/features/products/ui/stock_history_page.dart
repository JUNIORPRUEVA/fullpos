import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/stock_repository.dart';
import '../models/stock_movement_model.dart';
import 'widgets/kpi_card.dart';

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

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(
            movement.isInput
                ? Icons.call_made
                : movement.isOutput
                ? Icons.call_received
                : Icons.tune,
            color: color,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                detail.productLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _qtyLabel(movement),
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  movement.type.label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                if (detail.productCode != null)
                  Text(
                    'Cód: ${detail.productCode}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$dateLabel • ${detail.userLabel}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            if (movement.note?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                'Nota: ${movement.note}',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                ),
              ),
            ],
            if (detail.currentStock != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Stock actual: ${_qtyFormat.format(detail.currentStock)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Inventario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
            tooltip: 'Filtrar por fechas',
          ),
          if (_range != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearRange,
              tooltip: 'Limpiar rango',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const Text(
                        'Movimientos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: _filterType == null,
                        onSelected: (_) => _setFilter(null),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Entradas'),
                        selected: _filterType == StockMovementType.input,
                        onSelected: (_) => _setFilter(StockMovementType.input),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Salidas'),
                        selected: _filterType == StockMovementType.output,
                        onSelected: (_) => _setFilter(StockMovementType.output),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Ajustes'),
                        selected: _filterType == StockMovementType.adjust,
                        onSelected: (_) => _setFilter(StockMovementType.adjust),
                      ),
                    ],
                  ),
                  if (_range != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Rango: ${DateFormat('dd/MM/yyyy').format(_range!.start)} - ${DateFormat('dd/MM/yyyy').format(_range!.end)}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildSummary(),
                  const SizedBox(height: 16),
                  if (_history.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.inbox, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 10),
                          const Text(
                            'No hay movimientos registrados',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Cada entrada, salida o ajuste quedará archivado aquí.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: _history
                          .map((m) => _buildMovementTile(m))
                          .toList(),
                    ),
                ],
              ),
      ),
    );
  }
}
