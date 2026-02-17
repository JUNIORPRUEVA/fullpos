import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/ui/responsive_grid.dart';
import '../../../../theme/app_colors.dart' as ui_colors;
import '../../../products/models/product_model.dart';
import '../../../products/ui/widgets/product_thumbnail.dart';
import '../../providers/purchase_catalog_provider.dart';
import '../../providers/purchase_draft_provider.dart';

class PurchaseProductsGrid extends ConsumerWidget {
  const PurchaseProductsGrid({super.key});

  static const double _productCardSize = 104;
  static const double _productTileMaxExtent = 116;
  static const double _minProductCardSize = 72.0;
  static const double _gridCrossSpacing = 3.0;
  static const double _gridMainSpacing = 6.0;
  static const double _productCardAspect = 1.15;

  double _productCardSizeFor(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return _minProductCardSize;
    }
    final relativeWidth = (availableWidth / 1200).clamp(0.6, 1.0);
    final scale = relativeWidth < 0.85 ? 0.85 : relativeWidth;
    final size = (_productCardSize * scale).clamp(_minProductCardSize, 130.0);
    return size.isFinite && size > 0 ? size : _minProductCardSize;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat('#,##0.00', 'en_US');

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
            message: 'Prueba ajustar el filtro o buscar por código/nombre.',
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final cardSize = _productCardSizeFor(constraints.maxWidth);
            double maxExtent = stableMaxCrossAxisExtent(
              availableWidth: constraints.maxWidth,
              desiredMaxExtent: _productTileMaxExtent,
              spacing: _gridCrossSpacing,
              minExtent: _productTileMaxExtent,
            );
            if (!maxExtent.isFinite || maxExtent <= 0) {
              maxExtent = _productTileMaxExtent;
            }

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: maxExtent,
                mainAxisExtent: cardSize * _productCardAspect,
                crossAxisSpacing: _gridCrossSpacing,
                mainAxisSpacing: _gridMainSpacing,
              ),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return Center(
                  child: SizedBox(
                    width: cardSize,
                    height: cardSize * _productCardAspect,
                    child: _ProductCard(
                      product: product,
                      currency: currency,
                      onAdd: () {
                        ref
                            .read(purchaseDraftProvider.notifier)
                            .addProduct(product, qty: 1);
                      },
                    ),
                  ),
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

  const _ProductCard({
    required this.product,
    required this.currency,
    required this.onAdd,
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
    final overlayBg = theme.shadowColor.withOpacity(0.62);
    final overlayText = scheme.surface;
    final stock = widget.product.stock;
    final stockColor = stock <= 0 ? ui_colors.AppColors.error : scheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: scheme.surface,
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
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: SizedBox(
                  width: PurchaseProductsGrid._productCardSize,
                  height:
                      PurchaseProductsGrid._productCardSize *
                      PurchaseProductsGrid._productCardAspect,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ProductThumbnail.fromProduct(
                              widget.product,
                              width: double.infinity,
                              height: double.infinity,
                              borderRadius: BorderRadius.circular(12),
                              showBorder: false,
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, overlayBg],
                                    stops: const [0.0, 1.0],
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Text(
                                    widget.product.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.1,
                                      letterSpacing: 0.1,
                                    ).copyWith(color: overlayText),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 66),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ui_colors.AppColors.cardBackground
                                        .withOpacity(0.92),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: ui_colors.AppColors.borderSoft,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    widget.product.code.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                      letterSpacing: 0.3,
                                    ).copyWith(
                                      color: ui_colors.AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _MetaLine(
                                  label: 'COSTO',
                                  value:
                                      '\$${widget.currency.format(widget.product.purchasePrice)}',
                                  labelSize: 6.5,
                                  valueSize: 16,
                                  valueWeight: FontWeight.w900,
                                  labelColor: scheme.onSurface.withOpacity(0.62),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: stockColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            stock <= 0
                                                ? Icons.remove_circle_outline
                                                : Icons.inventory_2,
                                            size: 11,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            stock <= 0
                                                ? 'Agot.'
                                                : stock.toInt().toString(),
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              height: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
}

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;
  final double labelSize;
  final double valueSize;
  final FontWeight valueWeight;
  final Color? labelColor;

  const _MetaLine({
    required this.label,
    required this.value,
    this.labelSize = 11,
    this.valueSize = 14,
    this.valueWeight = FontWeight.w800,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: labelColor ?? scheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.w600,
            fontSize: labelSize,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: valueWeight,
              fontSize: valueSize,
              color: scheme.onSurface,
              height: 1.0,
            ),
          ),
        ),
      ],
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
        mainAxisExtent:
            PurchaseProductsGrid._productCardSize *
            PurchaseProductsGrid._productCardAspect,
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
