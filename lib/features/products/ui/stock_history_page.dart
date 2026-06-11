import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_colors.dart';
import '../data/stock_repository.dart';
import '../models/stock_movement_model.dart';
import 'widgets/products_surface.dart';

/// Historial completo de inventario (entradas, salidas y ajustes)
class StockHistoryPage extends StatefulWidget {
  const StockHistoryPage({super.key, this.embedded = false, this.onBack});

  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<StockHistoryPage> createState() => _StockHistoryPageState();
}

class _StockHistoryPageState extends State<StockHistoryPage> {
  final StockRepository _stockRepo = StockRepository();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final NumberFormat _qtyFormat = NumberFormat.decimalPattern();

  bool _loading = false;
  List<StockMovementDetail> _history = [];
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
      if (!mounted) return;
      setState(() {
        _history = items;
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

  Color _movementColor(StockMovementModel movement) {
    if (movement.isInput) return Colors.green;
    if (movement.isOutput) return Colors.red;
    return movement.quantity >= 0 ? Colors.orange : Colors.deepOrange;
  }

  String _qtyLabel(StockMovementModel movement) {
    if (movement.isOutput) {
      return '-${_qtyFormat.format(movement.quantity)}';
    }
    if (movement.isInput) {
      return '+${_qtyFormat.format(movement.quantity)}';
    }
    return movement.quantity >= 0
        ? '+${_qtyFormat.format(movement.quantity)}'
        : _qtyFormat.format(movement.quantity);
  }

  String _typeLabel(StockMovementModel movement) {
    if (movement.isInput) return 'Entrada';
    if (movement.isOutput) return 'Salida';
    return movement.quantity >= 0 ? 'Ajuste +' : 'Ajuste -';
  }

  Widget _buildHeaderCell(
    String label, {
    required int flex,
    TextAlign textAlign = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: AppColors.textSecondary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  Widget _buildValueCell(
    String value, {
    required int flex,
    TextAlign textAlign = TextAlign.left,
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: fontWeight,
          color: color ?? AppColors.textPrimary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          _buildHeaderCell('Fecha', flex: 18),
          const SizedBox(width: 12),
          _buildHeaderCell('Producto', flex: 24),
          const SizedBox(width: 12),
          _buildHeaderCell('Tipo', flex: 14),
          const SizedBox(width: 12),
          _buildHeaderCell('Usuario', flex: 15),
          const SizedBox(width: 12),
          _buildHeaderCell('Nota', flex: 19),
          const SizedBox(width: 12),
          _buildHeaderCell('Stock', flex: 12, textAlign: TextAlign.right),
          const SizedBox(width: 12),
          _buildHeaderCell('Cantidad', flex: 12, textAlign: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildMovementTile(StockMovementDetail detail) {
    final movement = detail.movement;
    final color = _movementColor(movement);
    final dateLabel = _dateFormat.format(movement.createdAt.toLocal());
    final productLabel = detail.productCode == null
        ? detail.productLabel
        : '${detail.productLabel} • ${detail.productCode}';
    final noteLabel = (movement.note?.trim().isNotEmpty ?? false)
        ? movement.note!.trim()
        : 'Sin nota';
    final stockLabel = detail.currentStock == null
        ? 'N/D'
        : _qtyFormat.format(detail.currentStock);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildValueCell(dateLabel, flex: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          _buildValueCell(productLabel, flex: 24, fontWeight: FontWeight.w700),
          const SizedBox(width: 12),
          Expanded(
            flex: 14,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _typeLabel(movement),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildValueCell(
            detail.userLabel,
            flex: 15,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          _buildValueCell(noteLabel, flex: 19, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          _buildValueCell(
            stockLabel,
            flex: 12,
            textAlign: TextAlign.right,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          _buildValueCell(
            _qtyLabel(movement),
            flex: 12,
            textAlign: TextAlign.right,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(double availableWidth) {
    final tableWidth = math.max(availableWidth, 1220.0);

    if (_history.isEmpty) {
      return Container(
        width: tableWidth,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: const Text(
          'Sin movimientos',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
            color: AppColors.textPrimary,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: tableWidth,
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(height: 14),
            _buildHistoryHeader(),
            const Divider(height: 1, thickness: 1, color: AppColors.borderSoft),
            ...List.generate(_history.length, (index) {
              final item = _history[index];
              return Column(
                children: [
                  _buildMovementTile(item),
                  if (index != _history.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.borderSoft,
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 900;
    final rangeLabel = _range == null
        ? null
        : '${DateFormat('dd/MM/yyyy').format(_range!.start)} - ${DateFormat('dd/MM/yyyy').format(_range!.end)}';

    final content = RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: productsResponsivePagePadding(
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
                top: widget.embedded ? 8 : 14,
              ),
              children: [
                if (widget.onBack != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Volver'),
                      style: FilledButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue,
                        backgroundColor: AppColors.lightBlueHover,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                if (widget.onBack != null) const SizedBox(height: 10),
                ProductsSurface(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (isCompact || rangeLabel != null)
                        const SizedBox(height: 8),
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
                                border: Border.all(color: AppColors.borderSoft),
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
                ProductsSurface(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildHistoryList(constraints.maxWidth),
                      );
                    },
                  ),
                ),
              ],
            ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(backgroundColor: Colors.transparent, body: content);
  }
}
