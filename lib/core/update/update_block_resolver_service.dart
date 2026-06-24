import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../errors/error_handler.dart';
import '../logging/app_logger.dart';
import 'update_block_reason.dart';

/// Servicio que navega a la pantalla correcta según la razón de bloqueo
/// de la actualización.
///
/// No fuerza cierres ni mata procesos. Solo guía al usuario a la pantalla
/// donde puede resolver el problema de forma segura.
class UpdateBlockResolverService {
  const UpdateBlockResolverService();

  /// Navega a la pantalla correspondiente según la [reason].
  ///
  /// Retorna `true` si pudo intentar la navegación, `false` si no había
  /// contexto de navegador disponible.
  Future<bool> navigateToBlocker(UpdateBlockReason reason) async {
    final navigator = ErrorHandler.navigatorKey.currentState;
    final context = navigator?.overlay?.context;
    if (navigator == null || context == null || !context.mounted) {
      await AppLogger.instance.logWarn(
        'UpdateBlockResolver: no navigator context available for ${reason.code}',
        module: 'app_update',
      );
      return false;
    }

    await AppLogger.instance.logInfo(
      'UpdateBlockResolver: navigating to ${reason.action} for ${reason.code}',
      module: 'app_update',
    );

    try {
      switch (reason.action) {
        case BlockNavigationAction.openSales:
          _go(context, '/sales');
        case BlockNavigationAction.openPayment:
          _go(context, '/cash');
        case BlockNavigationAction.openCashClose:
          _go(context, '/cash');
        case BlockNavigationAction.openPrintStatus:
          _go(context, '/settings/printers');
        case BlockNavigationAction.openImportExport:
          _go(context, '/inventory');
        case BlockNavigationAction.openSyncStatus:
          _go(context, '/settings');
        case BlockNavigationAction.openBackupStatus:
          _go(context, '/settings/backup');
        case BlockNavigationAction.openShiftClose:
          _go(context, '/cash');
        case BlockNavigationAction.openUnsavedForm:
          // No hay una ruta genérica; el usuario debe resolverlo manualmente.
          _showGenericMessage(context);
        case BlockNavigationAction.closeCriticalDialog:
          // Intentar cerrar el diálogo actual si es posible.
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        case BlockNavigationAction.none:
          _showGenericMessage(context);
      }
      return true;
    } catch (error) {
      await AppLogger.instance.logWarn(
        'UpdateBlockResolver: navigation failed for ${reason.code}: $error',
        module: 'app_update',
      );
      return false;
    }
  }

  void _go(BuildContext context, String path) {
    // Evitar navegar a la misma ruta.
    final currentLocation = GoRouterState.of(context).uri.toString();
    if (currentLocation == path) return;
    context.go(path);
  }

  void _showGenericMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Finaliza el proceso pendiente y luego intenta actualizar nuevamente.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }
}
