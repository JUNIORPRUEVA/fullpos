import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/ui/responsive_grid.dart';
import '../../../../core/utils/currency_display.dart';
import '../../../../theme/app_colors.dart' as ui_colors;
import '../../../products/models/product_model.dart';
import '../../../products/ui/widgets/product_thumbnail.dart';
import '../../providers/purchase_catalog_provider.dart';
import '../../providers/purchase_draft_provider.dart';
import 'purchase_ui.dart';

class PurchaseProductsGrid extends ConsumerWidget {
  const PurchaseProductsGrid({super.key});

  static const double _productTileMaxExtent = 280;
  static const double _minTileHeight = 82.0;
  static const double _gridCrossSpacing = 8.0;
  static const double _gridMainSpacing = 8.0;

  double _tileHeightFor(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return _minTileHeight;
    }
    final relativeWidth = (availableWidth / 1200).clamp(0.72, 1.0);
    final size = (92.0 * relativeWidth).clamp(_minTileHeight, 94.0);
    return size.isFinite && size > 0 ? size : _minTileHeight;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = CurrencyDisplay.currency();

    final productsAsync = ref.watch(purchaseFilteredProductsProvider);

    return productsAsync.when(
      loading: () => const _ProductsGridSkeleton(),
      error: (e, _) => Center(
        child: Text(
          'Error cargando productos: $e',
          style: TextStyle(color: scheme.error),
        ),
      ),
      data: (products) {
        if (products.isEmpty) {
          return _EmptyProducts(
            title: 'Sin productos',
            message:
                'Ajusta el filtro, el proveedor o la categoría para recuperar inventario elegible.',
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final tileHeight = _tileHeightFor(constraints.maxWidth);
            double maxExtent = stableMaxCrossAxisExtent(
              availableWidth: constraints.maxWidth,
              desiredMaxExtent: _productTileMaxExtent,
              spacing: _gridCrossSpacing,
              minExtent: 240,
            );
            if (!maxExtent.isFinite || maxExtent <= 0) {
              maxExtent = _productTileMaxExtent;
            }

            return GridView.builder(
              padding: kPurchasePagePadding,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: maxExtent,
                mainAxisExtent: tileHeight,
                crossAxisSpacing: _gridCrossSpacing,
                mainAxisSpacing: _gridMainSpacing,
              ),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return _ProductCard(
                  product: product,
                  currency: currency,
                  onAdd: () {
                    ref
                        .read(purchaseDraftProvider.notifier)
                        .addProduct(product, qty: 1);
                  },
                  tileHeight: tileHeight,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ProductCard extends StatefulWidget {
  final ProductModel product;
  final NumberFormat currency;
  final VoidCallback onAdd;
  final double tileHeight;

  const _ProductCard({
    required this.product,
    required this.currency,
    required this.onAdd,
    required this.tileHeight,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final border = scheme.outlineVariant.withOpacity(0.55);
    final stock = widget.product.stock;
    final isOutOfStock = stock <= 0;
    final isLowStock = stock > 0 && stock <= 10;
    final stockColor = isOutOfStock
        ? ui_colors.AppColors.error
        : (isLowStock ? ui_colors.AppColors.warning : scheme.primary);
    final stockLabel = isOutOfStock ? 'Sin stock' : 'Disp. ${stock.toInt()}';
    final formattedCost = widget.currency.format(widget.product.purchasePrice);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hovered
              ? Color.alphaBlend(
                  scheme.primary.withOpacity(0.025),
                  scheme.surface,
                )
              : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(_hovered ? 0.14 : 0.08),
              blurRadius: _hovered ? 16 : 10,
              spreadRadius: _hovered ? 1.2 : 0.4,
              offset: Offset(0, _hovered ? 6 : 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              hoverColor: ui_colors.AppColors.lightBlueHover.withOpacity(0.25),
              onTap: widget.onAdd,
              child: SizedBox(
                height: widget.tileHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ProductThumbnail.fromProduct(
                          widget.product,
                          width: 54,
                          height: 54,
                          borderRadius: BorderRadius.circular(10),
                          showBorder: false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.product.code.toUpperCase()}  •  $stockLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: stockColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Costo',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withOpacity(0.62),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'RD\$ $formattedCost',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ],
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
}

class _ProductsGridSkeleton extends StatelessWidget {
  const _ProductsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withOpacity(0.55);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: PurchaseProductsGrid._productTileMaxExtent,
        mainAxisSpacing: PurchaseProductsGrid._gridMainSpacing,
        crossAxisSpacing: PurchaseProductsGrid._gridCrossSpacing,
        mainAxisExtent: PurchaseProductsGrid._minTileHeight,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
          ),
        );
      },
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyProducts({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(AppSizes.paddingL),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 44, color: scheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
