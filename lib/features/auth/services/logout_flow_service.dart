import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/authz_service.dart';
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
    final routerContext = ErrorHandler.navigatorKey.currentContext ?? context;
    final messengerContext =
        ErrorHandler.navigatorKey.currentState?.overlay?.context ??
        routerContext;

    try {
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.maybeOf(messengerContext)?.hideCurrentSnackBar();

      final container = ProviderScope.containerOf(routerContext, listen: false);
      container.read(appBootstrapProvider).forceLoggedOut();

      // Clear all temporary authorization overrides before destroying the session.
      // This ensures a cashier logging in after an admin (or vice-versa) does NOT
      // inherit any in-memory temporary overrides from the previous session.
      AuthzService.clearOverrideCache();

      await SessionManager.logout();

      try {
        await container
            .read(appBootstrapProvider)
            .refreshAuth()
            .timeout(const Duration(seconds: 2));
      } on TimeoutException catch (error) {
        debugPrint('Logout refreshAuth agotó tiempo, continuando salida: $error');
      } catch (error) {
        debugPrint('Logout refreshAuth falló, continuando salida: $error');
      }

      final navigator = ErrorHandler.navigatorKey.currentState;
      while (navigator?.canPop() == true) {
        navigator?.pop();
      }

      if (!routerContext.mounted) return;

      final router = GoRouter.of(routerContext);
      router.refresh();
      router.go('/login');
    } catch (error) {
      debugPrint('Logout inmediato falló de forma no fatal: $error');
    }
  }
}
