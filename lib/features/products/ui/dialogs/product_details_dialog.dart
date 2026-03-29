import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../widgets/product_thumbnail.dart';
import '../widgets/products_surface.dart';

/// Diálogo de detalles completos del producto
class ProductDetailsDialog extends StatelessWidget {
  final ProductModel product;
  final String? categoryName;
  final String? supplierName;
  final bool showPurchasePrice;
  final bool showProfit;

  const ProductDetailsDialog({
    super.key,
    required this.product,
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
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.pop(context),
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => Navigator.pop(context),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ProductsSurface(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ProductsSectionHeader(
                              eyebrow: 'PRODUCTO',
                              title: product.name,
                              subtitle: 'Detalle comercial e inventario.',
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              product.code,
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                          if (product.isDeleted)
                            _buildBadge('ELIMINADO', scheme.error),
                          if (!product.isActive && !product.isDeleted)
                            _buildBadge('INACTIVO', scheme.outline),
                          if (product.isOutOfStock && product.isActive)
                            _buildBadge('AGOTADO', scheme.error),
                          if (product.hasLowStock && product.isActive)
                            _buildBadge('STOCK BAJO', scheme.tertiary),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: ProductThumbnail.fromProduct(
                          product,
                          width: double.infinity,
                          height: 200,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildSection(context, 'Información general', [
                        if (categoryName != null)
                          _buildInfoRow(
                            context,
                            'Categoría',
                            categoryName!,
                            Icons.category,
                          ),
                        if (supplierName != null)
                          _buildInfoRow(
                            context,
                            'Suplidor',
                            supplierName!,
                            Icons.business,
                          ),
                      ]),
                      _buildSection(context, 'Precios y finanzas', [
                        if (showPurchasePrice)
                          _buildInfoRow(
                            context,
                            'Precio de Compra',
                            currencyFormat.format(product.purchasePrice),
                            Icons.shopping_cart,
                            valueColor: scheme.primary,
                          ),
                        _buildInfoRow(
                          context,
                          'Precio de Venta',
                          currencyFormat.format(product.salePrice),
                          Icons.sell,
                          valueColor: scheme.tertiary,
                        ),
                        if (showProfit)
                          _buildInfoRow(
                            context,
                            'Ganancia Unitaria',
                            currencyFormat.format(product.profit),
                            Icons.attach_money,
                            valueColor: product.profit > 0
                                ? scheme.tertiary
                                : scheme.error,
                          ),
                        if (showProfit)
                          _buildInfoRow(
                            context,
                            'Margen de Ganancia',
                            '${product.profitPercentage.toStringAsFixed(2)}%',
                            Icons.percent,
                            valueColor: product.profit > 0
                                ? scheme.tertiary
                                : scheme.error,
                          ),
                      ]),
                      _buildSection(context, 'Inventario', [
                        _buildInfoRow(
                          context,
                          'Stock Actual',
                          numberFormat.format(product.stock),
                          Icons.inventory_2,
                          valueColor: product.isOutOfStock
                              ? scheme.error
                              : product.hasLowStock
                              ? scheme.tertiary
                              : scheme.onSurface,
                        ),
                        _buildInfoRow(
                          context,
                          'Stock Mínimo',
                          numberFormat.format(product.stockMin),
                          Icons.warning_amber,
                          valueColor: scheme.tertiary,
                        ),
                        if (showPurchasePrice)
                          _buildInfoRow(
                            context,
                            'Valor en Inventario',
                            currencyFormat.format(product.inventoryValue),
                            Icons.account_balance_wallet,
                            valueColor: scheme.secondary,
                          ),
                        if (showProfit)
                          _buildInfoRow(
                            context,
                            'Ganancia Potencial',
                            currencyFormat.format(
                              product.profit * product.stock,
                            ),
                            Icons.trending_up,
                            valueColor: scheme.primary,
                          ),
                        _buildInfoRow(
                          context,
                          'Valor de Venta Potencial',
                          currencyFormat.format(product.potentialRevenue),
                          Icons.monetization_on,
                          valueColor: scheme.tertiary,
                        ),
                      ]),
                      _buildSection(context, 'Registro', [
                        _buildInfoRow(
                          context,
                          'Fecha de Creación',
                          dateFormat.format(product.createdAt),
                          Icons.calendar_today,
                        ),
                        _buildInfoRow(
                          context,
                          'Última Actualización',
                          dateFormat.format(product.updatedAt),
                          Icons.update,
                        ),
                        if (product.isDeleted && product.deletedAt != null)
                          _buildInfoRow(
                            context,
                            'Fecha de Eliminación',
                            dateFormat.format(product.deletedAt!),
                            Icons.delete_forever,
                            valueColor: scheme.error,
                          ),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Cerrar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFamily: 'Inter',
          color: color,
        ),
      ),
    );
  }
}
