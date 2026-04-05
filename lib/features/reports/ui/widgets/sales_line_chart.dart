import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../data/reports_repository.dart';
import '../../../../core/constants/app_colors.dart';

class SalesLineChart extends StatelessWidget {
  final List<SeriesDataPoint> data;
  final List<SeriesDataPoint> secondaryData;
  final Color? primaryColor;
  final Color? secondaryColor;
  final String? primaryLabel;
  final String? secondaryLabel;

  const SalesLineChart({
    super.key,
    required this.data,
    this.secondaryData = const <SeriesDataPoint>[],
    this.primaryColor,
    this.secondaryColor,
    this.primaryLabel,
    this.secondaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryTone = primaryColor ?? AppColors.teal;
    final secondaryTone = secondaryColor ?? AppColors.gold;

    if (data.isEmpty) {
      return Center(
        child: Text(
          'No hay datos para mostrar',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final allValues = <double>[
      ...data.map((e) => e.value),
      ...secondaryData.map((e) => e.value),
    ];
    final maxY = allValues.reduce((a, b) => a > b ? a : b);
    final minValue = allValues.reduce((a, b) => a < b ? a : b);
    final minY = minValue < 0 ? minValue * 1.15 : 0.0;
    final maxX =
        (data.length > secondaryData.length
                ? data.length
                : secondaryData.length)
            .toDouble() -
        1;

    Widget legendItem(Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 16, bottom: 8),
      child: Column(
        children: [
          if (primaryLabel != null ||
              (secondaryData.isNotEmpty && secondaryLabel != null))
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (primaryLabel != null)
                    legendItem(primaryTone, primaryLabel!),
                  if (secondaryData.isNotEmpty && secondaryLabel != null)
                    legendItem(secondaryTone, secondaryLabel!),
                ],
              ),
            ),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 5 : 1,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: scheme.outlineVariant.withOpacity(0.75),
                      strokeWidth: 1,
                    );
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
                      reservedSize: 30,
                      interval: data.length > 10
                          ? (data.length / 7).ceilToDouble()
                          : 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) {
                          return const SizedBox.shrink();
                        }
                        final label = data[index].label;
                        final parts = label.split('-');
                        final day = parts.length == 3 ? parts[2] : label;
                        return Text(
                          day,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: maxY > 0 ? maxY / 5 : 1,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _formatMoney(value),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
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
                minX: 0,
                maxX: maxX < 0 ? 0 : maxX,
                minY: minY,
                maxY: maxY <= 0 ? 1 : maxY * 1.1,
                lineBarsData: [
                  LineChartBarData(
                    spots: data.asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value.value);
                    }).toList(),
                    isCurved: true,
                    color: primaryTone,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: data.length <= 15,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2,
                          strokeColor: primaryTone,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: primaryTone.withOpacity(0.12),
                    ),
                  ),
                  if (secondaryData.isNotEmpty)
                    LineChartBarData(
                      spots: secondaryData.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), entry.value.value);
                      }).toList(),
                      isCurved: true,
                      color: secondaryTone,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dashArray: const [6, 4],
                      dotData: FlDotData(show: secondaryData.length <= 12),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMoney(double value) {
    final normalized = value.isFinite ? value : 0;
    final sign = normalized < 0 ? '-' : '';
    final formatter = NumberFormat('#,##0', 'en_US');
    return '$sign${formatter.format(normalized.abs().round())}';
  }
}
