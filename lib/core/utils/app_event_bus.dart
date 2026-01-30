import 'dart:async';

/// Eventos globales de la app (simple EventBus).
///
/// Se usa para sincronizar pantallas como Reportes cuando se completa una venta,
/// sin acoplar UI con repositorios.
class AppEventBus {
  AppEventBus._();

  static final StreamController<AppEvent> _controller =
      StreamController<AppEvent>.broadcast();

  static Stream<AppEvent> get stream => _controller.stream;

  static void emit(AppEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }
}

sealed class AppEvent {
  const AppEvent();
}

class SaleCompletedEvent extends AppEvent {
  final int saleId;
  final int createdAtMs;

  const SaleCompletedEvent({required this.saleId, required this.createdAtMs});
}
