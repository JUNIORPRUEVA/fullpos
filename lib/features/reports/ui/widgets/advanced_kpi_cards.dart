import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/reports_repository.dart';

class AdvancedKpiCards extends StatelessWidget {
  final KpisData kpis;

  const AdvancedKpiCards({super.key, required this.kpis});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMainKpiCard(
                title: 'Total Ventas',
                value: kpis.totalSales,
                icon: Icons.point_of_sale,
                color: scheme.primary,
                subtitle: '${kpis.salesCount} transacciones',
                currency: currency,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMainKpiCard(
                title: 'Ganancia Neta',
                value: kpis.totalProfit,
                icon: Icons.trending_up,
                color: scheme.tertiary,
                subtitle:
                    '${_calculateMargin(kpis.totalProfit, kpis.totalSales).toStringAsFixed(1)}% margen',
                currency: currency,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSecondaryKpiCard(
                title: 'Ticket Promedio',
                value: currency.format(kpis.avgTicket),
                icon: Icons.receipt_long,
                color: scheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSecondaryKpiCard(
                title: 'Cotizaciones',
                value: '${kpis.quotesCount}',
                icon: Icons.description_outlined,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSecondaryKpiCard(
                title: 'Conversion',
                value: kpis.quotesCount > 0
                    ? '${((kpis.quotesConverted / kpis.quotesCount) * 100).toStringAsFixed(0)}%'
                    : '0%',
                icon: Icons.swap_horiz,
                color: scheme.tertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSecondaryKpiCard(
                title: 'Ingresos Caja',
                value: currency.format(kpis.cashIncome),
                icon: Icons.arrow_downward,
                color: scheme.tertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSecondaryKpiCard(
                title: 'Egresos Caja',
                value: currency.format(kpis.cashExpense),
                icon: Icons.arrow_upward,
                color: scheme.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSecondaryKpiCard(
                title: 'Balance Caja',
                value: currency.format(kpis.cashIncome - kpis.cashExpense),
                icon: Icons.account_balance,
                color: (kpis.cashIncome - kpis.cashExpense) >= 0
                    ? scheme.tertiary
                    : scheme.error,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainKpiCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
    required String subtitle,
    required NumberFormat currency,
    bool isAlert = false,
    String? alertText,
  }) {
    return Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                  if (isAlert && alertText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning,
                            size: 12,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            alertText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                currency.format(value),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSecondaryKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _calculateMargin(double profit, double sales) {
    if (sales <= 0) return 0;
    return (profit / sales) * 100;
  }
}
