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
              desiredMaxExtent: 220,
              spacing: spacing,
              minExtent: 160,
            );

            return GridView.builder(
              padding: const EdgeInsets.only(bottom: AppSizes.paddingL),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: extent,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: 1.15,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Agregado: ${product.name}'),
                        duration: const Duration(milliseconds: 700),
                      ),
                    );
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

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      onTap: onAdd,
      child: Ink(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProductThumbnail.fromProduct(product, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurface.withOpacity(0.65),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
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
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: const Text('Agregar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
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
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(AppSizes.radiusXL),
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
