import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/session/session_manager.dart';
import '../../cash/data/operation_flow_service.dart';

class LogoutFlowService {
  LogoutFlowService._();

  static Future<void> requestLogout(
    BuildContext context, {
    required Future<void> Function() performLogout,
  }) async {
    final gate = await OperationFlowService.loadGateState();
    final openShift = gate.activeSession;

    if (openShift != null && gate.canOperate) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Finaliza el turno desde el menú de usuario.'),
        ),
      );
      return;
    }

    await performLogout();
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
}
