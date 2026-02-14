import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../products/data/categories_repository.dart';
import '../../products/data/products_repository.dart';
import '../../products/data/suppliers_repository.dart';
import '../../products/models/category_model.dart';
import '../../products/models/product_model.dart';
import '../../products/models/supplier_model.dart';
import 'purchase_draft_provider.dart';

class PurchaseCatalogFilterState {
  final String query;
  final int? categoryId;
  final bool onlySupplierProducts;

  const PurchaseCatalogFilterState({
    required this.query,
    required this.categoryId,
    required this.onlySupplierProducts,
  });

  factory PurchaseCatalogFilterState.initial() {
    return const PurchaseCatalogFilterState(
      query: '',
      categoryId: null,
      onlySupplierProducts: true,
    );
  }

  PurchaseCatalogFilterState copyWith({
    String? query,
    int? categoryId,
    bool clearCategory = false,
    bool? onlySupplierProducts,
  }) {
    return PurchaseCatalogFilterState(
      query: query ?? this.query,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      onlySupplierProducts: onlySupplierProducts ?? this.onlySupplierProducts,
    );
  }
}

final purchaseCatalogFiltersProvider =
    StateProvider<PurchaseCatalogFilterState>(
      (ref) => PurchaseCatalogFilterState.initial(),
    );

final purchaseSuppliersProvider = FutureProvider<List<SupplierModel>>((
  ref,
) async {
  final repo = SuppliersRepository();
  return repo.getAll(includeInactive: false);
});

final purchaseCategoriesProvider = FutureProvider<List<CategoryModel>>((
  ref,
) async {
  final repo = CategoriesRepository();
  return repo.getAll(includeInactive: false, includeDeleted: false);
});

final purchaseProductsBaseProvider = FutureProvider<List<ProductModel>>((
  ref,
) async {
  // Reload base list when supplier/category/onlySupplier changes.
  final filters = ref.watch(purchaseCatalogFiltersProvider);
  final supplier = ref.watch(purchaseDraftProvider.select((s) => s.supplier));

  final productsRepo = ProductsRepository();

  final supplierId = (filters.onlySupplierProducts && supplier?.id != null)
      ? supplier!.id
      : null;

  return productsRepo.getAll(
    filters: ProductFilters(
      categoryId: filters.categoryId,
      supplierId: supplierId,
      isActive: true,
    ),
    includeDeleted: false,
  );
});

final purchaseFilteredProductsProvider =
    Provider<AsyncValue<List<ProductModel>>>((ref) {
      final base = ref.watch(purchaseProductsBaseProvider);
      final filters = ref.watch(purchaseCatalogFiltersProvider);

      return base.whenData((products) {
        final q = filters.query.trim().toLowerCase();
        if (q.isEmpty) return products;

        bool matches(ProductModel p) {
          if (p.name.toLowerCase().contains(q)) return true;
          if (p.code.toLowerCase().contains(q)) return true;
          return false;
        }

        return products.where(matches).toList(growable: false);
      });
    });
