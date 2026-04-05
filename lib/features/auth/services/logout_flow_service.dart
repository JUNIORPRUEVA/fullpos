import 'dart:async';

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
    final stableContext =
        ErrorHandler.navigatorKey.currentState?.overlay?.context ??
        ErrorHandler.navigatorKey.currentContext ??
        context;

    try {
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.maybeOf(stableContext)?.hideCurrentSnackBar();

      final container = ProviderScope.containerOf(stableContext, listen: false);
      container.read(appBootstrapProvider).forceLoggedOut();

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

      final routerContext =
          navigator?.overlay?.context ??
          ErrorHandler.navigatorKey.currentContext ??
          stableContext;
      if (!routerContext.mounted) return;

      final router = GoRouter.of(routerContext);
      router.refresh();
      router.go('/login');
    } catch (error) {
      debugPrint('Logout inmediato falló de forma no fatal: $error');
    }
  }
}
