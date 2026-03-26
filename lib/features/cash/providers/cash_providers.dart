import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/session/session_manager.dart';
import '../data/cash_repository.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_summary_model.dart';
import '../data/cash_session_model.dart';
import '../data/operation_flow_service.dart';

// ===================== PROVIDERS PRINCIPALES =====================

/// Provider para la sesión activa del usuario actual.
final activeSessionProvider = FutureProvider<ActiveSession?>((ref) async {
  return OperationFlowService.loadActiveSession();
});

/// Provider para verificar si la sesión operativa está abierta.
final isSessionActiveProvider = FutureProvider<bool>((ref) async {
  return (await OperationFlowService.loadActiveSession()) != null;
});

/// Estado global de la sesión operativa activa.
final activeSessionControllerProvider =
    StateNotifierProvider<ActiveSessionController, AsyncValue<ActiveSession?>>(
      (ref) => ActiveSessionController(ref),
    );

/// Provider para el resumen de la sesión actual
final cashSummaryProvider = FutureProvider<CashSummaryModel?>((ref) async {
  final activeSession = await ref.watch(activeSessionProvider.future);
  if (activeSession == null) return null;
  return CashRepository.buildSummary(sessionId: activeSession.shiftId);
});

/// Provider para los movimientos de la sesión actual
final cashMovementsProvider = FutureProvider<List<CashMovementModel>>((
  ref,
) async {
  final activeSession = await ref.watch(activeSessionProvider.future);
  if (activeSession == null) return [];
  return CashRepository.listMovements(sessionId: activeSession.shiftId);
});

/// Provider para el historial de sesiones cerradas
final closedSessionsProvider = FutureProvider<List<CashSessionModel>>((
  ref,
) async {
  return await CashRepository.listClosedSessions(limit: 50);
});

// ===================== CONTROLADOR STATE NOTIFIER =====================

class ActiveSessionController
    extends StateNotifier<AsyncValue<ActiveSession?>> {
  final Ref _ref;
  StreamSubscription<void>? _sessionSubscription;

  ActiveSessionController(this._ref) : super(const AsyncValue.loading()) {
    _sessionSubscription = SessionManager.changes.listen((_) {
      unawaited(refresh());
    });
    _ref.onDispose(() {
      _sessionSubscription?.cancel();
    });
    refresh();
  }

  Future<void> _loadSession() async {
    state = const AsyncValue.loading();
    try {
      final session = await OperationFlowService.loadActiveSession();
      state = AsyncValue.data(session);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refrescar sesión
  Future<void> refresh() async {
    await _loadSession();
    _ref.invalidate(activeSessionProvider);
    _ref.invalidate(isSessionActiveProvider);
    _ref.invalidate(cashSummaryProvider);
    _ref.invalidate(cashMovementsProvider);
  }

  Future<ActiveSession> startSession({
    required double openingAmount,
    String? note,
  }) async {
    final session = await OperationFlowService.startActiveSession(
      openingAmount: openingAmount,
      note: note,
    );
    await refresh();
    return session;
  }

  Future<void> closeSession({
    required int sessionId,
    required double closingAmount,
    required String note,
  }) async {
    await OperationFlowService.closeActiveSession(
      sessionId: sessionId,
      closingAmount: closingAmount,
      note: note,
    );

    await refresh();
    _ref.invalidate(closedSessionsProvider);
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
    return CashRepository.buildSummary(sessionId: session.shiftId);
  }

  bool get isOpen => state.valueOrNull != null;

  int? get currentSessionId => state.valueOrNull?.shiftId;
}
