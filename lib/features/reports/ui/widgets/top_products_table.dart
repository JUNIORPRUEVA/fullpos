import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/reports_repository.dart';

class TopProductsTable extends StatelessWidget {
  final List<TopProduct> products;

  const TopProductsTable({
    super.key,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );

    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No hay productos para mostrar',
            style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '#',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Producto',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Ventas',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Cantidad',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Ganancia',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          ...products.asMap().entries.map((entry) {
            final index = entry.key;
            final product = entry.value;
            final rankColor = index < 3 ? scheme.tertiary : scheme.onSurface;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: index % 2 == 0
                    ? scheme.surface
                    : scheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: rankColor,
                        fontWeight:
                            index < 3 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      product.productName,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      money.format(product.totalSales),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Text(
                      product.totalQty.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Text(
                      money.format(product.totalProfit),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
