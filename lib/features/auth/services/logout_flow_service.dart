import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/session/session_manager.dart';
import '../../cash/data/operation_flow_service.dart';
import '../../cash/ui/cash_close_dialog.dart';

enum _LogoutAction { closeSessionAndExit, cancel }

class LogoutFlowService {
  LogoutFlowService._();

  static Future<void> requestLogout(
    BuildContext context, {
    required Future<void> Function() performLogout,
  }) async {
    final gate = await OperationFlowService.loadGateState();
    final openShift = gate.activeSession;

    if (openShift == null || !gate.canOperate) {
      await performLogout();
      return;
    }

    if (!context.mounted) return;

    final action = await _showActiveSessionDialog(context);
    if (action == null || action == _LogoutAction.cancel) return;

    if (action == _LogoutAction.closeSessionAndExit) {
      final sessionId = openShift.shiftId;
      if (!context.mounted) return;
      await CashCloseDialog.show(
        context,
        sessionId: sessionId,
        logoutAfterClose: true,
      );
    }
  }

  static Future<void> defaultPerformLogout(BuildContext context) async {
    final rootCtx = ErrorHandler.navigatorKey.currentContext ?? context;
    FocusManager.instance.primaryFocus?.unfocus();
    ScaffoldMessenger.maybeOf(rootCtx)?.hideCurrentSnackBar();

    final container = ProviderScope.containerOf(rootCtx, listen: false);
    container.read(appBootstrapProvider).forceLoggedOut();

    await SessionManager.logout();
    await container.read(appBootstrapProvider).refreshAuth();

    if (!rootCtx.mounted) return;
    final navigator = ErrorHandler.navigatorKey.currentState;
    while (navigator?.canPop() == true) {
      navigator?.pop();
    }
    GoRouter.of(rootCtx).refresh();
    GoRouter.of(rootCtx).go('/login');
  }

  static Future<_LogoutAction?> _showActiveSessionDialog(BuildContext context) {
    return showDialog<_LogoutAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sesión activa detectada'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Debes cerrar la sesión activa para salir. El sistema cerrará la sesión operativa, emitirá el cierre y luego cerrará tu acceso.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _LogoutAction.cancel),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, _LogoutAction.closeSessionAndExit),
              child: const Text('Cerrar sesión y salir'),
            ),
          ],
        );
      },
    );
  }
}
