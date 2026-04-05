import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/reports_repository.dart';

class SalesBarChart extends StatefulWidget {
  final List<SeriesDataPoint> data;
  final Color? barColor;
  final String title;

  const SalesBarChart({
    super.key,
    required this.data,
    this.barColor,
    this.title = 'Ventas',
  });

  @override
  State<SalesBarChart> createState() => _SalesBarChartState();
}

class _SalesBarChartState extends State<SalesBarChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final barColor = widget.barColor ?? scheme.primary;
    final moneyAxis = NumberFormat('#,##0', 'en_US');

    if (widget.data.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bar_chart,
                size: 42,
                color: scheme.onSurface.withOpacity(0.3),
              ),
              const SizedBox(height: 8),
              Text(
                'No hay datos para mostrar',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
              ),
            ],
          ),
        ),
      );
    }

    final values = widget.data
        .map((entry) => entry.value)
        .toList(growable: false);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxY = maxValue <= 0 ? 0.0 : maxValue * 1.15;
    final minY = minValue >= 0 ? 0.0 : minValue * 1.15;
    final span = (maxY - minY).abs();
    final interval = span > 0 ? span / 4 : 1.0;
    final hasNegativeValues = minY < 0;

    return Padding(
      padding: const EdgeInsets.only(top: 16, right: 16, bottom: 8),
      child: BarChart(
        BarChartData(
          minY: minY,
          maxY: maxY,
          baselineY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => scheme.onSurface.withOpacity(0.9),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final item = widget.data[group.x.toInt()];
                return BarTooltipItem(
                  '${_formatDate(item.label)}\n',
                  TextStyle(
                    color: scheme.surface,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: _formatCurrency(item.value),
                      style: TextStyle(
                        color: scheme.surface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                );
              },
            ),
            touchCallback: (FlTouchEvent event, barTouchResponse) {
              setState(() {
                if (!event.isInterestedForInteractions ||
                    barTouchResponse == null ||
                    barTouchResponse.spot == null) {
                  touchedIndex = -1;
                  return;
                }
                touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
              });
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= widget.data.length) {
                    return const SizedBox.shrink();
                  }

                  final showEvery = widget.data.length > 14
                      ? 3
                      : (widget.data.length > 7 ? 2 : 1);
                  if (index % showEvery != 0 &&
                      index != widget.data.length - 1) {
                    return const SizedBox.shrink();
                  }

                  final label = widget.data[index].label;
                  final parts = label.split('-');
                  final day = parts.length >= 3
                      ? '${parts[2]}/${parts[1]}'
                      : label;

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      day,
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  return Text(
                    moneyAxis.format(value),
                    style: TextStyle(
                      color: scheme.onSurface.withOpacity(0.6),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: scheme.outlineVariant),
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: scheme.outlineVariant.withOpacity(0.5),
                strokeWidth: value == 0 ? 1.3 : 1,
              );
            },
          ),
          barGroups: _buildBarGroups(
            maxY: maxY,
            minY: minY,
            hasNegativeValues: hasNegativeValues,
            barColor: barColor,
            scheme: scheme,
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups({
    required double maxY,
    required double minY,
    required bool hasNegativeValues,
    required Color barColor,
    required ColorScheme scheme,
  }) {
    return widget.data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final isTouched = index == touchedIndex;
      final rodColor = item.value >= 0
          ? (isTouched ? barColor.withOpacity(0.8) : barColor)
          : (isTouched ? scheme.error.withOpacity(0.8) : scheme.error);

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            fromY: 0,
            toY: item.value,
            color: rodColor,
            width: _calculateBarWidth(),
            borderRadius: item.value >= 0
                ? const BorderRadius.vertical(top: Radius.circular(4))
                : const BorderRadius.vertical(bottom: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: !hasNegativeValues,
              fromY: minY,
              toY: maxY,
              color: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      );
    }).toList();
  }

  double _calculateBarWidth() {
    final count = widget.data.length;
    if (count <= 7) return 28;
    if (count <= 14) return 18;
    if (count <= 21) return 12;
    return 8;
  }

  String _formatCurrency(double value) {
    final normalized = value.isFinite ? value : 0;
    final sign = normalized < 0 ? '-' : '';
    final formatter = NumberFormat('#,##0', 'en_US');
    return '${sign}RD\$ ${formatter.format(normalized.abs().round())}';
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length >= 3) {
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return dateStr;
  }
}
