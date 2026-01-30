import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_summary_model.dart';

// ===================== PROVIDERS PRINCIPALES =====================

/// Provider para la sesión de caja abierta actual
final openCashSessionProvider = FutureProvider<CashSessionModel?>((ref) async {
  return await CashRepository.getOpenSession();
});

/// Provider para verificar si hay caja abierta
final isCashOpenProvider = FutureProvider<bool>((ref) async {
  return await CashRepository.hasOpenSession();
});

/// Controlador de sesiones de caja
final cashSessionControllerProvider =
    StateNotifierProvider<CashSessionController, AsyncValue<CashSessionModel?>>(
  (ref) => CashSessionController(ref),
);

/// Provider para el resumen de la sesión actual
final cashSummaryProvider = FutureProvider<CashSummaryModel?>((ref) async {
  final sessionId = await CashRepository.getCurrentSessionId();
  if (sessionId == null) return null;
  return await CashRepository.buildSummary(sessionId: sessionId);
});

/// Provider para los movimientos de la sesión actual
final cashMovementsProvider =
    FutureProvider<List<CashMovementModel>>((ref) async {
  final sessionId = await CashRepository.getCurrentSessionId();
  if (sessionId == null) return [];
  return await CashRepository.listMovements(sessionId: sessionId);
});

/// Provider para el historial de sesiones cerradas
final closedSessionsProvider =
    FutureProvider<List<CashSessionModel>>((ref) async {
  return await CashRepository.listClosedSessions(limit: 50);
});

// ===================== CONTROLADOR STATE NOTIFIER =====================

class CashSessionController
    extends StateNotifier<AsyncValue<CashSessionModel?>> {
  final Ref _ref;

  CashSessionController(this._ref) : super(const AsyncValue.loading()) {
    _loadSession();
  }

  /// Cargar sesión actual
  Future<void> _loadSession() async {
    state = const AsyncValue.loading();
    try {
      final session = await CashRepository.getOpenSession();
      state = AsyncValue.data(session);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refrescar sesión
  Future<void> refresh() async {
    await _loadSession();
    // Invalidar providers relacionados
    _ref.invalidate(openCashSessionProvider);
    _ref.invalidate(isCashOpenProvider);
    _ref.invalidate(cashSummaryProvider);
    _ref.invalidate(cashMovementsProvider);
  }

  /// Abrir nueva sesión de caja
  Future<int> openSession({
    required int userId,
    required String userName,
    required double openingAmount,
  }) async {
    try {
      final id = await CashRepository.openSession(
        userId: userId,
        userName: userName,
        openingAmount: openingAmount,
      );
      await refresh();
      return id;
    } catch (e) {
      rethrow;
    }
  }

  /// Cerrar sesión de caja
  Future<void> closeSession({
    required int sessionId,
    required double closingAmount,
    required String note,
  }) async {
    try {
      // Obtener resumen antes de cerrar
      final summary = await CashRepository.buildSummary(sessionId: sessionId);

      await CashRepository.closeSession(
        sessionId: sessionId,
        closingAmount: closingAmount,
        note: note,
        summary: summary,
      );

      await refresh();
      _ref.invalidate(closedSessionsProvider);
    } catch (e) {
      rethrow;
    }
  }

  /// Agregar movimiento de caja
  Future<int> addMovement({
    required int sessionId,
    required String type,
    required double amount,
    required String reason,
    required int userId,
  }) async {
    try {
      final id = await CashRepository.addMovement(
        sessionId: sessionId,
        type: type,
        amount: amount,
        reason: reason,
        userId: userId,
      );
      _ref.invalidate(cashSummaryProvider);
      _ref.invalidate(cashMovementsProvider);
      return id;
    } catch (e) {
      rethrow;
    }
  }

  /// Obtener resumen de la sesión actual
  Future<CashSummaryModel?> getSummary() async {
    final session = state.valueOrNull;
    if (session == null) return null;
    return await CashRepository.buildSummary(sessionId: session.id!);
  }

  /// Helper: verificar si la caja está abierta
  bool get isOpen => state.valueOrNull != null;

  /// Helper: obtener ID de sesión actual
  int? get currentSessionId => state.valueOrNull?.id;
}
