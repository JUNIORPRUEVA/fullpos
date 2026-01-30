import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/product_model.dart';
import 'product_thumbnail.dart';

/// Tarjeta compacta de producto para inventario (estilo corporativo)
class CompactProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback? onTap;
  final VoidCallback? onAddStockTap;
  final String? categoryName;
  final String? supplierName;
  final bool showPurchasePrice;
  final bool showProfit;

  const CompactProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onAddStockTap,
    this.categoryName,
    this.supplierName,
    this.showPurchasePrice = true,
    this.showProfit = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currencyFormat = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: 2,
    );
    final numberFormat = NumberFormat.decimalPattern();
    final statusColor = _getStatusColor(scheme);
    final mutedText = scheme.onSurface.withOpacity(0.65);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
      color: scheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Indicador de estado (barra lateral)
              Container(
                width: 3,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),

              ProductThumbnail.fromProduct(
                product,
                size: 44,
                showBorder: false,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(width: 10),

              // Código del producto
              Container(
                width: 70,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  product.code,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),

              // Nombre del producto
              Expanded(
                flex: 2,
                child: Text(
                  product.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),

              // Stock
              _buildMiniInfo(
                numberFormat.format(product.stock),
                'Stock',
                _getStockColor(scheme),
                mutedText,
              ),
              const SizedBox(width: 8),

              // Valor Inventario (costo)
              if (showPurchasePrice) ...[
                _buildMiniInfo(
                  currencyFormat.format(product.inventoryValue),
                  'Valor',
                  scheme.secondary,
                  mutedText,
                ),
                const SizedBox(width: 8),
              ],

              // Margen
              if (showProfit) ...[
                _buildMiniInfo(
                  '${product.profitPercentage.toStringAsFixed(0)}%',
                  'Margen',
                  product.profit > 0 ? scheme.tertiary : scheme.error,
                  mutedText,
                ),
                const SizedBox(width: 4),
              ],

              // Icono de estado
              Icon(_getStatusIcon(), size: 16, color: statusColor),
              const SizedBox(width: 8),

              // Botón de Agregar Stock
              if (onAddStockTap != null)
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: onAddStockTap,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Stock'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniInfo(
    String value,
    String label,
    Color color,
    Color mutedText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 8, color: mutedText)),
      ],
    );
  }

  Color _getStatusColor(ColorScheme scheme) {
    if (product.isDeleted) return scheme.error;
    if (!product.isActive) return scheme.outline;
    if (product.isOutOfStock) return scheme.error;
    if (product.hasLowStock) return scheme.tertiary;
    return scheme.primary;
  }

  Color _getStockColor(ColorScheme scheme) {
    if (product.isOutOfStock) return scheme.error;
    if (product.hasLowStock) return scheme.tertiary;
    return scheme.onSurface;
  }

  IconData _getStatusIcon() {
    if (product.isDeleted) return Icons.delete_forever;
    if (!product.isActive) return Icons.pause_circle;
    if (product.isOutOfStock) return Icons.error;
    if (product.hasLowStock) return Icons.warning;
    return Icons.check_circle;
  }
}
