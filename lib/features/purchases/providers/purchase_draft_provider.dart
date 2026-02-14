import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../products/models/product_model.dart';
import '../../products/models/supplier_model.dart';

@immutable
class PurchaseDraftLine {
  final ProductModel product;
  final double qty;
  final double unitCost;

  const PurchaseDraftLine({
    required this.product,
    required this.qty,
    required this.unitCost,
  });

  double get subtotal => qty * unitCost;

  PurchaseDraftLine copyWith({
    ProductModel? product,
    double? qty,
    double? unitCost,
  }) {
    return PurchaseDraftLine(
      product: product ?? this.product,
      qty: qty ?? this.qty,
      unitCost: unitCost ?? this.unitCost,
    );
  }
}

@immutable
class PurchaseDraftState {
  final SupplierModel? supplier;
  final DateTime createdAt;
  final DateTime purchaseDate;
  final double taxRatePercent;
  final String notes;
  final List<PurchaseDraftLine> lines;

  const PurchaseDraftState({
    required this.supplier,
    required this.createdAt,
    required this.purchaseDate,
    required this.taxRatePercent,
    required this.notes,
    required this.lines,
  });

  factory PurchaseDraftState.initial({double taxRatePercent = 18.0}) {
    final now = DateTime.now();
    return PurchaseDraftState(
      supplier: null,
      createdAt: now,
      purchaseDate: now,
      taxRatePercent: taxRatePercent,
      notes: '',
      lines: const [],
    );
  }

  bool get hasChanges => supplier != null || notes.trim().isNotEmpty || lines.isNotEmpty;

  double get subtotal => lines.fold(0.0, (s, l) => s + l.subtotal);
  double get taxAmount => subtotal * (taxRatePercent / 100.0);
  double get total => subtotal + taxAmount;

  PurchaseDraftState copyWith({
    SupplierModel? supplier,
    bool clearSupplier = false,
    DateTime? createdAt,
    DateTime? purchaseDate,
    double? taxRatePercent,
    String? notes,
    List<PurchaseDraftLine>? lines,
  }) {
    return PurchaseDraftState(
      supplier: clearSupplier ? null : (supplier ?? this.supplier),
      createdAt: createdAt ?? this.createdAt,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      notes: notes ?? this.notes,
      lines: lines ?? this.lines,
    );
  }
}

final purchaseDraftProvider = StateNotifierProvider<PurchaseDraftController, PurchaseDraftState>(
  (ref) => PurchaseDraftController(ref),
);

class PurchaseDraftController extends StateNotifier<PurchaseDraftState> {
  final Ref _ref;

  PurchaseDraftController(this._ref) : super(PurchaseDraftState.initial());

  void reset({double? taxRatePercent}) {
    state = PurchaseDraftState.initial(
      taxRatePercent: taxRatePercent ?? state.taxRatePercent,
    );
  }

  void setSupplier(SupplierModel? supplier) {
    state = state.copyWith(supplier: supplier);
  }

  void setPurchaseDate(DateTime date) {
    state = state.copyWith(purchaseDate: date);
  }

  void setTaxRatePercent(double value) {
    final safe = value.isFinite ? value.clamp(0.0, 100.0) : state.taxRatePercent;
    state = state.copyWith(taxRatePercent: safe.toDouble());
  }

  void setNotes(String value) {
    state = state.copyWith(notes: value);
  }

  void addProduct(ProductModel product, {double? qty, double? unitCost}) {
    final productId = product.id;
    if (productId == null) return;

    final existingIndex = state.lines.indexWhere((l) => l.product.id == productId);
    if (existingIndex >= 0) {
      final next = [...state.lines];
      final current = next[existingIndex];
      final newQty = (current.qty + (qty ?? 1)).clamp(0.0, double.infinity);
      next[existingIndex] = current.copyWith(qty: newQty);
      state = state.copyWith(lines: next);
      return;
    }

    final line = PurchaseDraftLine(
      product: product,
      qty: (qty ?? 1).clamp(0.0, double.infinity),
      unitCost: (unitCost ?? product.purchasePrice).clamp(0.0, double.infinity),
    );

    state = state.copyWith(lines: [...state.lines, line]);
  }

  void removeProduct(int productId) {
    state = state.copyWith(
      lines: state.lines.where((l) => l.product.id != productId).toList(growable: false),
    );
  }

  void setQty(int productId, double qty) {
    final next = [...state.lines];
    final index = next.indexWhere((l) => l.product.id == productId);
    if (index < 0) return;
    final safe = qty.isFinite ? qty : next[index].qty;
    if (safe <= 0) {
      next.removeAt(index);
      state = state.copyWith(lines: next);
      return;
    }
    next[index] = next[index].copyWith(qty: safe);
    state = state.copyWith(lines: next);
  }

  void changeQtyBy(int productId, double delta) {
    final line = state.lines.where((l) => l.product.id == productId).cast<PurchaseDraftLine?>().firstOrNull;
    if (line == null) return;
    setQty(productId, line.qty + delta);
  }

  void setUnitCost(int productId, double unitCost) {
    final next = [...state.lines];
    final index = next.indexWhere((l) => l.product.id == productId);
    if (index < 0) return;
    final safe = unitCost.isFinite ? unitCost : next[index].unitCost;
    next[index] = next[index].copyWith(unitCost: safe < 0 ? 0 : safe);
    state = state.copyWith(lines: next);
  }

  void loadFromOrder({
    required SupplierModel supplier,
    required List<PurchaseDraftLine> lines,
    double? taxRatePercent,
    String? notes,
    DateTime? purchaseDate,
  }) {
    state = state.copyWith(
      supplier: supplier,
      lines: lines,
      taxRatePercent: taxRatePercent ?? state.taxRatePercent,
      notes: notes ?? '',
      purchaseDate: purchaseDate ?? DateTime.now(),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
