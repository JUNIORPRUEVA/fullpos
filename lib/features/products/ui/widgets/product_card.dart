import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/product_model.dart';
import 'product_thumbnail.dart';

/// Widget para mostrar una tarjeta de producto
class ProductCard extends StatelessWidget {
  final ProductModel product;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleActive;
  final VoidCallback? onAddStock;
  final String? categoryName;
  final String? supplierName;
  final bool showPurchasePrice;
  final bool showProfit;

  const ProductCard({
    super.key,
    required this.product,
    this.isSelected = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleActive,
    this.onAddStock,
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
    final statusColor = _resolveStatusColor(scheme);
    final mutedText = scheme.onSurface.withOpacity(0.65);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: scheme.surface,
      elevation: isSelected ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? scheme.primary : scheme.outlineVariant,
          width: isSelected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Imagen del producto (thumbnail)
              ProductThumbnail.fromProduct(
                product,
                size: 48,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(width: 10),

              // Código del producto - Ancho fijo
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  product.code,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),

              // Nombre del producto - Expandible
              Expanded(
                flex: 2,
                child: Text(
                  [
                    product.name,
                    if (categoryName != null || supplierName != null)
                      [
                        if (categoryName != null) categoryName!,
                        if (supplierName != null) supplierName!,
                      ].join(' • '),
                  ].join('  •  '),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),

              // Precio Compra
              if (showPurchasePrice) ...[
                _buildCompactInfo(
                  'Compra',
                  currencyFormat.format(product.purchasePrice),
                  scheme.primary,
                  mutedText,
                ),
                const SizedBox(width: 6),
              ],

              // Precio Venta
              _buildCompactInfo(
                'Venta',
                currencyFormat.format(product.salePrice),
                scheme.tertiary,
                mutedText,
              ),
              const SizedBox(width: 6),

              // Stock
              _buildCompactInfo(
                'Stock',
                '${numberFormat.format(product.stock)}/${numberFormat.format(product.stockMin)}',
                statusColor,
                mutedText,
              ),
              const SizedBox(width: 6),

              if (showProfit) ...[
                // Ganancia
                _buildCompactInfo(
                  'Ganancia',
                  currencyFormat.format(product.profit),
                  product.profit > 0 ? scheme.tertiary : scheme.error,
                  mutedText,
                ),
                const SizedBox(width: 6),

                // Margen
                _buildCompactInfo(
                  'Margen',
                  '${product.profitPercentage.toStringAsFixed(0)}%',
                  product.profit > 0 ? scheme.tertiary : scheme.error,
                  mutedText,
                ),
                const SizedBox(width: 6),
              ],

              // Valor Inventario
              if (showPurchasePrice) ...[
                _buildCompactInfo(
                  'Val.Inv',
                  currencyFormat.format(product.inventoryValue),
                  scheme.secondary,
                  mutedText,
                ),
                const SizedBox(width: 6),
              ],

              // Ganancia Potencial
              if (showProfit) ...[
                _buildCompactInfo(
                  'Gan.Pot',
                  currencyFormat.format(product.profit * product.stock),
                  scheme.primary,
                  mutedText,
                ),
                const SizedBox(width: 8),
              ] else ...[
                const SizedBox(width: 8),
              ],

              // Badges y acciones
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Badges de estado
                  if (product.isDeleted)
                    _buildMiniBadge('DEL', scheme.error, scheme)
                  else if (!product.isActive)
                    _buildMiniBadge('INA', scheme.outline, scheme)
                  else if (product.isOutOfStock)
                    _buildMiniBadge('AGO', scheme.error, scheme)
                  else if (product.hasLowStock)
                    _buildMiniBadge('BAJ', scheme.tertiary, scheme),

                  // Botones de acción compactos
                  if (onToggleActive != null)
                    _buildActionIcon(
                      icon: product.isActive
                          ? Icons.toggle_on
                          : Icons.toggle_off,
                      color: product.isActive ? scheme.tertiary : mutedText,
                      tooltip: product.isActive ? 'Desactivar' : 'Activar',
                      onPressed: onToggleActive,
                    ),
                  if (onEdit != null)
                    _buildActionIcon(
                      icon: Icons.edit,
                      color: scheme.primary,
                      tooltip: 'Editar',
                      onPressed: onEdit,
                    ),
                  if (onDelete != null)
                    _buildActionIcon(
                      icon: product.isDeleted
                          ? Icons.restore_from_trash
                          : Icons.delete,
                      color: product.isDeleted ? scheme.tertiary : scheme.error,
                      tooltip: product.isDeleted ? 'Restaurar' : 'Eliminar',
                      onPressed: onDelete,
                    ),
                  if (onAddStock != null && !product.isDeleted)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: onAddStock,
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
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String label, Color color, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color == scheme.outline ? scheme.onSurface : color,
        ),
      ),
    );
  }

  Widget _buildCompactInfo(
    String label,
    String value,
    Color color,
    Color mutedText,
  ) {
    return SizedBox(
      width: 75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: mutedText)),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
    );
  }

  Color _resolveStatusColor(ColorScheme scheme) {
    if (product.isDeleted) return scheme.error;
    if (!product.isActive) return scheme.outline;
    if (product.isOutOfStock) return scheme.error;
    if (product.hasLowStock) return scheme.tertiary;
    return scheme.primary;
  }
}
