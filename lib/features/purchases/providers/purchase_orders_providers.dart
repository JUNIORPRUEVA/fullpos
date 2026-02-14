import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/purchase_order_models.dart';
import '../data/purchases_repository.dart';

class PurchaseOrdersFilterState {
  final String query;
  final String? status; // PENDIENTE | RECIBIDA | null
  final int? supplierId;
  final DateTimeRange? range;

  const PurchaseOrdersFilterState({
    required this.query,
    required this.status,
    required this.supplierId,
    required this.range,
  });

  factory PurchaseOrdersFilterState.initial() {
    return const PurchaseOrdersFilterState(
      query: '',
      status: null,
      supplierId: null,
      range: null,
    );
  }

  PurchaseOrdersFilterState copyWith({
    String? query,
    String? status,
    bool clearStatus = false,
    int? supplierId,
    bool clearSupplier = false,
    DateTimeRange? range,
    bool clearRange = false,
  }) {
    return PurchaseOrdersFilterState(
      query: query ?? this.query,
      status: clearStatus ? null : (status ?? this.status),
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      range: clearRange ? null : (range ?? this.range),
    );
  }
}

final purchaseOrdersFiltersProvider = StateProvider<PurchaseOrdersFilterState>(
  (ref) => PurchaseOrdersFilterState.initial(),
);

final purchaseOrdersRepoProvider = Provider<PurchasesRepository>((ref) {
  return PurchasesRepository();
});

final purchaseOrdersListProvider =
    FutureProvider<List<PurchaseOrderSummaryDto>>((ref) async {
      final repo = ref.watch(purchaseOrdersRepoProvider);
      final filters = ref.watch(purchaseOrdersFiltersProvider);

      final result = await repo.listOrders(
        supplierId: filters.supplierId,
        status: filters.status,
      );

      final q = filters.query.trim().toLowerCase();
      final range = filters.range;

      bool matches(PurchaseOrderSummaryDto dto) {
        if (q.isNotEmpty) {
          final idStr = (dto.order.id ?? 0).toString();
          if (!dto.supplierName.toLowerCase().contains(q) &&
              !idStr.contains(q)) {
            return false;
          }
        }

        if (range != null) {
          final created = DateTime.fromMillisecondsSinceEpoch(
            dto.order.createdAtMs,
          );
          if (created.isBefore(range.start) || created.isAfter(range.end)) {
            return false;
          }
        }

        return true;
      }

      return result.where(matches).toList(growable: false);
    });

final purchaseSelectedOrderIdProvider = StateProvider<int?>((ref) => null);

final purchaseSelectedOrderDetailProvider =
    FutureProvider<PurchaseOrderDetailDto?>((ref) async {
      final repo = ref.watch(purchaseOrdersRepoProvider);
      final id = ref.watch(purchaseSelectedOrderIdProvider);
      if (id == null) return null;
      return repo.getOrderById(id);
    });
