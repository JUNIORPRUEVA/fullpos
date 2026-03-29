import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ComparativeStatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const ComparativeStatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final today = stats['today'] ?? {'sales': 0.0, 'count': 0};
    final yesterday = stats['yesterday'] ?? {'sales': 0.0, 'count': 0};
    final thisWeek = stats['thisWeek'] ?? {'sales': 0.0, 'count': 0};
    final lastWeek = stats['lastWeek'] ?? {'sales': 0.0, 'count': 0};
    final thisMonth = stats['thisMonth'] ?? {'sales': 0.0, 'count': 0};
    final lastMonth = stats['lastMonth'] ?? {'sales': 0.0, 'count': 0};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildComparisonRow(
          context,
          'Hoy',
          (today['sales'] as num).toDouble(),
          (today['count'] as num).toInt(),
          'Ayer',
          (yesterday['sales'] as num).toDouble(),
          (yesterday['count'] as num).toInt(),
          Icons.today,
        ),
        const SizedBox(height: 10),
        _buildComparisonRow(
          context,
          'Esta semana',
          (thisWeek['sales'] as num).toDouble(),
          (thisWeek['count'] as num).toInt(),
          'Semana pasada',
          (lastWeek['sales'] as num).toDouble(),
          (lastWeek['count'] as num).toInt(),
          Icons.date_range,
        ),
        const SizedBox(height: 10),
        _buildComparisonRow(
          context,
          'Este mes',
          (thisMonth['sales'] as num).toDouble(),
          (thisMonth['count'] as num).toInt(),
          'Mes pasado',
          (lastMonth['sales'] as num).toDouble(),
          (lastMonth['count'] as num).toInt(),
          Icons.calendar_month,
        ),
      ],
    );
  }

  Widget _buildComparisonRow(
    BuildContext context,
    String currentLabel,
    double currentValue,
    int currentCount,
    String previousLabel,
    double previousValue,
    int previousCount,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );
    final change = previousValue > 0
        ? ((currentValue - previousValue) / previousValue * 100)
        : (currentValue > 0 ? 100 : 0);
    final isPositive = change >= 0;
    final changeColor = isPositive ? scheme.tertiary : scheme.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: scheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      currentLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: scheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: changeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositive
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 14,
                            color: changeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: changeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  currency.format(currentValue),
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$currentCount ventas | $previousLabel: ${currency.format(previousValue)} ($previousCount ventas)',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.62),
                    fontWeight: FontWeight.w500,
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
