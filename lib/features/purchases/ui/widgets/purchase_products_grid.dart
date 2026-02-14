import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/ui/responsive_grid.dart';
import '../../../products/models/product_model.dart';
import '../../../products/ui/widgets/product_thumbnail.dart';
import '../../providers/purchase_catalog_provider.dart';
import '../../providers/purchase_draft_provider.dart';

class PurchaseProductsGrid extends ConsumerWidget {
  const PurchaseProductsGrid({super.key});

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
            const spacing = 10.0;
            final extent = stableMaxCrossAxisExtent(
              availableWidth: constraints.maxWidth,
              desiredMaxExtent: 190,
              spacing: spacing,
              minExtent: 170,
            );

            final mainExtent = extent * 1.18;

            return GridView.builder(
              padding: const EdgeInsets.only(bottom: AppSizes.paddingL),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: extent,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                mainAxisExtent: mainExtent,
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
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final NumberFormat currency;
  final VoidCallback onAdd;

  const _ProductCard({
    required this.product,
    required this.currency,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final border = scheme.outlineVariant.withOpacity(0.55);
    final overlayBg = theme.shadowColor.withOpacity(0.62);
    final overlayText = scheme.surface;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onAdd,
      child: Ink(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductThumbnail.fromProduct(
                    product,
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
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, overlayBg],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          color: overlayText,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Text(
                        product.code,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _MetaLine(
                      label: 'Costo',
                      value: currency.format(product.purchasePrice),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetaLine(
                      label: 'Stock',
                      value: product.stock.toStringAsFixed(2),
                      valueColor: product.stock <= 0
                          ? AppColors.error
                          : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetaLine({required this.label, required this.value, this.valueColor});

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
            color: scheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? scheme.onSurface,
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
      padding: const EdgeInsets.only(bottom: AppSizes.paddingL),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 190 * 1.18,
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
