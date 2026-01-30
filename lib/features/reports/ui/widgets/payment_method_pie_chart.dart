import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/reports_repository.dart';

class PaymentMethodPieChart extends StatefulWidget {
  final List<PaymentMethodData> data;

  const PaymentMethodPieChart({super.key, required this.data});

  @override
  State<PaymentMethodPieChart> createState() => _PaymentMethodPieChartState();
}

class _PaymentMethodPieChartState extends State<PaymentMethodPieChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chartColors = <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      scheme.primaryContainer,
      scheme.secondaryContainer,
    ];

    if (widget.data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pie_chart_outline,
              size: 48,
              color: scheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'No hay datos para mostrar',
              style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
      );
    }

    final total = widget.data.fold<double>(0, (sum, item) => sum + item.amount);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        pieTouchResponse == null ||
                        pieTouchResponse.touchedSection == null) {
                      touchedIndex = -1;
                      return;
                    }
                    touchedIndex =
                        pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: _buildSections(total, chartColors, scheme),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.data.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final color = chartColors[index % chartColors.length];
              final percentage = total > 0 ? (item.amount / total * 100) : 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.method,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: touchedIndex == index
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: scheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${percentage.toStringAsFixed(1)}% • ${item.count} ventas',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections(
    double total,
    List<Color> chartColors,
    ColorScheme scheme,
  ) {
    return widget.data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final isTouched = index == touchedIndex;
      final fontSize = isTouched ? 14.0 : 11.0;
      final radius = isTouched ? 65.0 : 55.0;
      final color = chartColors[index % chartColors.length];
      final percentage = total > 0 ? (item.amount / total * 100) : 0;

      return PieChartSectionData(
        color: color,
        value: item.amount,
        title: '${percentage.toStringAsFixed(0)}%',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: scheme.onPrimary,
          shadows: const [Shadow(blurRadius: 2, color: Colors.black26)],
        ),
      );
    }).toList();
  }
}
