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
      locale: 'en_US',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );
    final numberFormat = NumberFormat.decimalPattern();
    final statusColor = _resolveStatusColor(scheme);
    final mutedText = scheme.onSurface.withOpacity(0.65);
    final textPrimary = scheme.onSurface;
    final textSecondary = scheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1080;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withOpacity(0.055)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            hoverColor: theme.hoverColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: compact ? 42 : 48,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ProductThumbnail.fromProduct(
                    product,
                    size: compact ? 40 : 46,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                product.code,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  fontFamily: 'Inter',
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            if (product.isDeleted)
                              _buildMiniBadge('Eliminado', scheme.error, scheme)
                            else if (!product.isActive)
                              _buildMiniBadge(
                                'Inactivo',
                                scheme.outline,
                                scheme,
                              )
                            else if (product.isOutOfStock)
                              _buildMiniBadge('Agotado', scheme.error, scheme)
                            else if (product.hasLowStock)
                              _buildMiniBadge(
                                'Stock bajo',
                                scheme.tertiary,
                                scheme,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          product.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: compact ? 13 : 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                                ?categoryName,
                                ?supplierName,
                              ].isEmpty
                              ? 'Sin clasificación adicional'
                              : [
                                  ?categoryName,
                                  ?supplierName,
                                ].join(' • '),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Inter',
                            color: textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    _buildCompactInfo(
                      'Venta',
                      currencyFormat.format(product.salePrice),
                      scheme.tertiary,
                      mutedText,
                    ),
                    const SizedBox(width: 10),
                    _buildCompactInfo(
                      'Stock',
                      numberFormat.format(product.stock),
                      statusColor,
                      mutedText,
                    ),
                    const SizedBox(width: 10),
                    if (showPurchasePrice) ...[
                      _buildCompactInfo(
                        'Compra',
                        currencyFormat.format(product.purchasePrice),
                        scheme.primary,
                        mutedText,
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (showProfit)
                      _buildCompactInfo(
                        'Margen',
                        '${product.profitPercentage.toStringAsFixed(0)}%',
                        product.profit > 0 ? scheme.tertiary : scheme.error,
                        mutedText,
                      ),
                  ] else ...[
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currencyFormat.format(product.salePrice),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                            color: scheme.tertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${numberFormat.format(product.stock)} en stock',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Inter',
                            color: mutedText,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onToggleActive != null)
                        _buildActionIcon(
                          icon: product.isActive
                              ? Icons.toggle_on_outlined
                              : Icons.toggle_off_outlined,
                          color: product.isActive ? scheme.tertiary : mutedText,
                          tooltip: product.isActive ? 'Desactivar' : 'Activar',
                          onPressed: onToggleActive,
                        ),
                      if (onEdit != null)
                        _buildActionIcon(
                          icon: Icons.edit_outlined,
                          color: scheme.primary,
                          tooltip: 'Editar',
                          onPressed: onEdit,
                        ),
                      if (onDelete != null)
                        _buildActionIcon(
                          icon: product.isDeleted
                              ? Icons.restore_from_trash_outlined
                              : Icons.delete_outline,
                          color: product.isDeleted
                              ? scheme.tertiary
                              : scheme.error,
                          tooltip: product.isDeleted ? 'Restaurar' : 'Eliminar',
                          onPressed: onDelete,
                        ),
                      if (onAddStock != null && !product.isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: SizedBox(
                            height: 32,
                            child: FilledButton.tonalIcon(
                              onPressed: onAddStock,
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 16,
                              ),
                              label: const Text('Stock'),
                              style: FilledButton.styleFrom(
                                foregroundColor: scheme.primary,
                                backgroundColor: scheme.primaryContainer,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Inter',
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
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
      },
    );
  }

  Widget _buildMiniBadge(String label, Color color, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
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
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: mutedText,
              fontFamily: 'Inter',
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
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
      icon: Icon(icon, size: 18, color: color),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(5),
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
        foregroundColor: color,
      ),
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
