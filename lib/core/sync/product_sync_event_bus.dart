import 'dart:async';

class ProductSyncChange {
  const ProductSyncChange({
    required this.localProductId,
    this.serverProductId,
    required this.reason,
  });

  final int localProductId;
  final int? serverProductId;
  final String reason;
}

class ProductSyncEventBus {
  ProductSyncEventBus._();

  static final ProductSyncEventBus instance = ProductSyncEventBus._();

  final StreamController<ProductSyncChange> _controller =
      StreamController<ProductSyncChange>.broadcast();

  Stream<ProductSyncChange> get stream => _controller.stream;

  void emit(ProductSyncChange change) {
    if (!_controller.isClosed) {
      _controller.add(change);
    }
  }
}