import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/authz_audit_service.dart';
import '../../../core/session/session_manager.dart';
import '../../cash/data/operation_flow_service.dart';
import '../../cash/ui/cash_close_dialog.dart';
import '../data/auth_repository.dart';

enum _LogoutAction { closeShiftAndExit, exitWithoutClosing, cancel }

class LogoutFlowService {
  LogoutFlowService._();

  static Future<void> requestLogout(
    BuildContext context, {
    required Future<void> Function() performLogout,
  }) async {
    final gate = await OperationFlowService.loadGateState();
    final openShift = gate.userOpenShift;

    if (openShift == null || !gate.hasUserShiftOpen) {
      await performLogout();
      return;
    }

    final canExitWithOpenShift = await _canExitWithOpenShift();
    if (!context.mounted) return;

    final action = await _showOpenShiftDialog(
      context,
      canExitWithOpenShift: canExitWithOpenShift,
    );
    if (action == null || action == _LogoutAction.cancel) return;

    if (action == _LogoutAction.closeShiftAndExit) {
      final sessionId = openShift.id;
      if (sessionId == null || !context.mounted) return;
      final closed = await CashCloseDialog.show(context, sessionId: sessionId);
      if (closed == true) {
        await performLogout();
      }
      return;
    }

    if (action == _LogoutAction.exitWithoutClosing) {
      if (!canExitWithOpenShift) return;
      final reason = await _promptRequiredReason(context);
      if (reason == null || reason.trim().isEmpty) return;

      await _auditExitWithOpenShift(
        shiftId: openShift.id,
        cashboxId: openShift.cashboxDailyId,
        businessDate: openShift.businessDate,
        reason: reason.trim(),
      );
      await performLogout();
    }
  }

  static Future<void> defaultPerformLogout(BuildContext context) async {
    await SessionManager.logout();
    if (!context.mounted) return;
    final rootCtx = ErrorHandler.navigatorKey.currentContext ?? context;
    GoRouter.of(rootCtx).refresh();
    GoRouter.of(rootCtx).go('/login');
  }

  static Future<bool> _canExitWithOpenShift() async {
    final role = (await SessionManager.role() ?? '').trim().toLowerCase();
    if (role == 'admin' || role == 'supervisor') return true;
    final perms = await AuthRepository.getCurrentPermissions();
    return perms.canExitWithOpenShift;
  }

  static Future<_LogoutAction?> _showOpenShiftDialog(
    BuildContext context, {
    required bool canExitWithOpenShift,
  }) {
    return showDialog<_LogoutAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Turno abierto detectado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tu turno sigue abierto. ¿Qué deseas hacer?'),
              if (!canExitWithOpenShift) ...[
                const SizedBox(height: 10),
                Text(
                  'Salir sin cerrar turno requiere permiso CAN_EXIT_WITH_OPEN_SHIFT (admin/supervisor).',
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _LogoutAction.cancel),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: canExitWithOpenShift
                  ? () => Navigator.pop(context, _LogoutAction.exitWithoutClosing)
                  : null,
              child: const Text('Salir sin cerrar turno'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _LogoutAction.closeShiftAndExit),
              child: const Text('Cerrar turno y salir'),
            ),
          ],
        );
      },
    );
  }

  static Future<String?> _promptRequiredReason(BuildContext context) async {
    final reasonCtrl = TextEditingController();
    try {
      return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          String? error;
          return StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Motivo obligatorio'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Debes indicar el motivo para salir sin cerrar turno.'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Motivo',
                      hintText: 'Ej: relevo de turno, incidencia técnica, etc.',
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = reasonCtrl.text.trim();
                    if (value.isEmpty) {
                      setLocal(() => error = 'El motivo es obligatorio.');
                      return;
                    }
                    Navigator.pop(context, value);
                  },
                  child: const Text('Confirmar salida'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      reasonCtrl.dispose();
    }
  }

  static Future<void> _auditExitWithOpenShift({
    required int? shiftId,
    required int? cashboxId,
    required String? businessDate,
    required String reason,
  }) async {
    final companyId = await SessionManager.companyId() ?? 1;
    final userId = await SessionManager.userId();
    final terminalId =
        (await SessionManager.terminalId()) ?? await SessionManager.ensureTerminalId();

    await AuthzAuditService.log(
      companyId: companyId,
      permissionCode: 'session.exit_with_open_shift',
      result: 'EXIT_WITH_OPEN_SHIFT',
      terminalId: terminalId,
      requestedByUserId: userId,
      method: 'logout',
      resourceType: 'cash_session',
      resourceId: shiftId?.toString(),
      meta: {
        'action': 'EXIT_WITH_OPEN_SHIFT',
        'reason': reason,
        'cashbox_id': cashboxId,
        'shift_id': shiftId,
        'business_date': businessDate,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
