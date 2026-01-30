import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/reports_repository.dart';
import '../../../../core/constants/app_colors.dart';

class SalesLineChart extends StatelessWidget {
  final List<SeriesDataPoint> data;

  const SalesLineChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Text(
          'No hay datos para mostrar',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    final maxY = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final minY = 0.0;

    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 16, bottom: 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 5 : 1,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.shade300,
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
                interval: data.length > 10 ? (data.length / 7).ceilToDouble() : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) {
                    return const Text('');
                  }
                  final label = data[index].label;
                  // Mostrar solo día (últimos 2 dígitos de fecha YYYY-MM-DD)
                  final parts = label.split('-');
                  final day = parts.length == 3 ? parts[2] : label;
                  return Text(
                    day,
                    style: const TextStyle(
                      color: Colors.black54,
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
                    style: const TextStyle(
                      color: Colors.black54,
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
              left: BorderSide(color: Colors.grey.shade300),
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          minX: 0,
          maxX: data.length.toDouble() - 1,
          minY: minY,
          maxY: maxY * 1.1,
          lineBarsData: [
            LineChartBarData(
              spots: data.asMap().entries.map((entry) {
                return FlSpot(entry.key.toDouble(), entry.value.value);
              }).toList(),
              isCurved: true,
              color: AppColors.teal,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: data.length <= 15,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: AppColors.teal,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.teal.withAlpha((0.2 * 255).round()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMoney(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toStringAsFixed(0);
  }
}
