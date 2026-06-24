import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/authz_service.dart';
import '../../../core/session/session_manager.dart';
import '../../cash/data/cash_repository.dart';
import '../../cash/ui/cash_close_dialog.dart';

enum _OpenShiftLogoutAction { closeAndLogout, logoutOnly, cancel }

class LogoutFlowService {
  LogoutFlowService._();

  static bool _requestInProgress = false;

  static Future<void> requestLogout(
    BuildContext context, {
    required Future<void> Function() performLogout,
  }) async {
    if (_requestInProgress) return;
    _requestInProgress = true;

    try {
      final userId = await SessionManager.userId();
      if (userId == null) {
        await performLogout();
        return;
      }

      final openShifts = await CashRepository.listOpenSessionsForUser(
        userId: userId,
      );

      // FULLPOS SEGURIDAD: verificar que los turnos realmente pertenecen
      // al usuario actual. Esto es una defensa adicional por si el
      // repositorio no filtrara correctamente.
      final myOpenShifts = openShifts
          .where((s) => s.userId == userId)
          .toList(growable: false);

      if (myOpenShifts.isEmpty) {
        await performLogout();
        return;
      }
      if (myOpenShifts.length > 1) {
        throw StateError(
          'Hay varios turnos abiertos para este usuario (${myOpenShifts.length}). '
          'No se cerrará sesión hasta corregir este estado.',
        );
      }

      final openShift = myOpenShifts.single;
      if (openShift.userId != userId) {
        throw StateError(
          'El turno abierto #${openShift.id} no pertenece a este usuario.',
        );
      }

      final sessionId = openShift.id;
      if (sessionId == null) {
        throw StateError('El turno abierto no tiene un identificador válido.');
      }

      final dialogContext =
          ErrorHandler.navigatorKey.currentState?.overlay?.context ?? context;
      if (!dialogContext.mounted) return;

      final action = await _showOpenShiftDialog(dialogContext);
      switch (action) {
        case _OpenShiftLogoutAction.closeAndLogout:
          if (!dialogContext.mounted) return;
          await CashCloseDialog.show(
            dialogContext,
            sessionId: sessionId,
            logoutAfterClose: true,
          );
          return;
        case _OpenShiftLogoutAction.logoutOnly:
          await performLogout();
          return;
        case _OpenShiftLogoutAction.cancel:
        case null:
          return;
      }
    } catch (error, stackTrace) {
      final errorContext =
          ErrorHandler.navigatorKey.currentState?.overlay?.context ?? context;
      if (!errorContext.mounted) return;
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: errorContext,
        module: 'auth/logout',
      );
    } finally {
      _requestInProgress = false;
    }
  }

  static Future<_OpenShiftLogoutAction?> _showOpenShiftDialog(
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<_OpenShiftLogoutAction>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(Icons.point_of_sale_rounded, color: scheme.primary),
          title: const Text('Tienes un turno abierto'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: const Text(
              'Elige cómo deseas salir. Puedes cerrar y cuadrar el turno '
              'ahora, o conservarlo abierto para continuarlo en tu próximo '
              'inicio de sesión.',
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_OpenShiftLogoutAction.cancel),
              child: const Text('Cancelar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_OpenShiftLogoutAction.logoutOnly),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Salir sin cerrar turno'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_OpenShiftLogoutAction.closeAndLogout),
              icon: const Icon(Icons.lock_clock_rounded),
              label: const Text('Cerrar turno y salir'),
            ),
          ],
        );
      },
    );
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

      // Clear all temporary authorization overrides before destroying the session.
      // This ensures a cashier logging in after an admin (or vice-versa) does NOT
      // inherit any in-memory temporary overrides from the previous session.
      AuthzService.clearOverrideCache();

      await SessionManager.logout();
      container.read(appBootstrapProvider).forceLoggedOut();

      final navigator = ErrorHandler.navigatorKey.currentState;
      while (navigator?.canPop() == true) {
        navigator?.pop();
      }

      if (!routerContext.mounted) return;

      final router = GoRouter.of(routerContext);
      router.go('/login');
      router.refresh();

      unawaited(
        container
            .read(appBootstrapProvider)
            .refreshAuth()
            .timeout(const Duration(seconds: 2))
            .catchError((Object error) {
              debugPrint(
                'Logout refreshAuth falló, continuando salida: $error',
              );
            }),
      );
    } catch (error) {
      debugPrint('Logout inmediato falló de forma no fatal: $error');
    }
  }
}
