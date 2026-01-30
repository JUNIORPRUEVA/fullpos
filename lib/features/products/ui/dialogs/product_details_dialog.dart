import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../widgets/product_thumbnail.dart';

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
            child: Container(
              width: 600,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            product.code,
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            product.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Badges de estado
                    Wrap(
                      spacing: 8,
                      children: [
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
                    const Divider(height: 32),

                    // Imagen del producto
                    _buildSection(
                      context,
                      'Imagen',
                      [
                        SizedBox(
                          height: 220,
                          width: double.infinity,
                          child: ProductThumbnail.fromProduct(
                            product,
                            width: double.infinity,
                            height: 220,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),

                    // Información general
                    _buildSection(context, 'Información General', [
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

                    // Precios
                    _buildSection(context, 'Precios y Finanzas', [
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
                          valueColor:
                              product.profit > 0 ? scheme.tertiary : scheme.error,
                        ),
                      if (showProfit)
                        _buildInfoRow(
                          context,
                          'Margen de Ganancia',
                          '${product.profitPercentage.toStringAsFixed(2)}%',
                          Icons.percent,
                          valueColor:
                              product.profit > 0 ? scheme.tertiary : scheme.error,
                        ),
                    ]),

                    // Inventario
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
                          currencyFormat.format(product.profit * product.stock),
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

                    // Fechas
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

                    const SizedBox(height: 16),
                    // Botón cerrar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 20),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurface.withOpacity(0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withOpacity(0.75),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
