import 'package:flutter/material.dart';
import '../../data/reports_repository.dart';
import '../../../../core/constants/app_colors.dart';

class KpiCardsRow extends StatelessWidget {
  final KpisData kpis;

  const KpiCardsRow({
    super.key,
    required this.kpis,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = (width - 40) / 3; // 3 cards por fila en desktop

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildKpiCard(
              title: 'Total Vendido',
              value: 'RD\$ ${_formatMoney(kpis.totalSales)}',
              icon: Icons.attach_money,
              color: AppColors.teal,
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Ganancia',
              value: 'RD\$ ${_formatMoney(kpis.totalProfit)}',
              icon: Icons.trending_up,
              color: AppColors.gold,
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Ventas',
              value: '${kpis.salesCount}',
              icon: Icons.shopping_cart,
              color: Colors.blue.shade700,
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Ticket Promedio',
              value: 'RD\$ ${_formatMoney(kpis.avgTicket)}',
              icon: Icons.receipt_long,
              color: Colors.purple.shade700,
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Cotizaciones',
              value: '${kpis.quotesCount}',
              icon: Icons.description,
              color: Colors.orange.shade700,
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Conversión',
              value: kpis.quotesCount > 0
                  ? '${((kpis.quotesConverted / kpis.quotesCount) * 100).toStringAsFixed(1)}%'
                  : '0%',
              icon: Icons.check_circle,
              color: Colors.green.shade700,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minWidth: 180),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withAlpha((0.15 * 255).round()),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMoney(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(2);
  }
}
