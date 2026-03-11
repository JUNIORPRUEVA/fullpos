import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/debug/render_diagnostics.dart';
import 'core/db/db_init.dart';
import 'core/errors/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'core/services/cloud_sync_service.dart';
import 'core/sync/product_sync_service.dart';
import 'core/theme/theme_audit.dart';
import 'core/window/window_startup_controller.dart';
import 'package:window_manager/window_manager.dart';
import 'debug/db_audit.dart';
import 'features/settings/data/business_settings_model.dart';
import 'features/settings/data/business_settings_repository.dart';
import 'features/settings/providers/business_settings_provider.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Desktop window startup (Windows): ocultar y fijar tamaño ANTES de cualquier init pesado.
      // Esto reduce al mínimo el “flash” de la ventanita al arrancar.
      try {
        await windowManager.ensureInitialized();
        await WindowStartupController.instance.applyHiddenStartup();
      } catch (_) {
        // Ignorar: la app debe poder arrancar igual.
      }

      final diagnostics = RenderDiagnostics.instance;
      await diagnostics.ensureInitialized();
      diagnostics.installGlobalErrorHandlers();

      // Temporary: make sure Flutter framework errors are always visible in the
      // Debug Console with a full stack trace.
      final originalFlutterOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        final stack = details.stack ?? StackTrace.current;
        final message = details.exceptionAsString();

        // Ignore noisy, non-fatal image 404s (e.g. sample Unsplash URLs) so
        // navigation doesn't spam the console.
        if (message.contains('NetworkImageLoadException') &&
            message.contains('statusCode: 404') &&
            message.contains('images.unsplash.com/')) {
          return;
        }

        debugPrint('FLUTTER_ERROR: $message');
        debugPrint('$stack');
        try {
          ErrorHandler.instance.reportPlatformError(
            details.exception,
            stack,
            module: 'flutter',
          );
        } catch (_) {}
        unawaited(
          AppLogger.instance.logWarn(
            'FLUTTER_ERROR: $message',
            module: 'flutter',
          ),
        );
        if (originalFlutterOnError != null) {
          originalFlutterOnError(details);
        } else {
          FlutterError.dumpErrorToConsole(details);
        }
      };

      try {
        await AppLogger.instance.init();
      } catch (_) {
        // Si falla el logger, no detenemos el arranque.
      }

      // Configuración central (base URL, UA, etc.).
      await AppConfig.init();

      DbInit.ensureInitialized();
      if (kDebugMode) {
        ThemeAudit.run();
        await runDbAudit();
      }

      // FULLPOS DB HARDENING: sincronizar configuracion en la nube sin bloquear UI.
      // Importante: estas tareas pueden ser pesadas (leer DB, armar payloads grandes, subir imágenes).
      // Para evitar “cámara lenta”/jank, se difieren y se escalonan después del primer frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>(() async {
          try {
            CloudSyncService.instance.startRealtimeSyncEngine();
            ProductSyncService.instance.start();
            CloudSyncService.instance.scheduleUsersSyncSoon(
              delay: const Duration(milliseconds: 100),
              reason: 'startup_users',
            );
            CloudSyncService.instance.scheduleCompanyConfigSyncSoon(
              delay: const Duration(milliseconds: 150),
              reason: 'startup_company_config',
            );
            CloudSyncService.instance.scheduleClientsSyncSoon(
              delay: const Duration(milliseconds: 200),
              reason: 'startup_clients',
            );
            CloudSyncService.instance.scheduleCategoriesSyncSoon(
              delay: const Duration(milliseconds: 220),
              reason: 'startup_categories',
            );
            CloudSyncService.instance.scheduleSuppliersSyncSoon(
              delay: const Duration(milliseconds: 240),
              reason: 'startup_suppliers',
            );
            CloudSyncService.instance.scheduleProductsSyncSoon(
              delay: const Duration(milliseconds: 250),
              reason: 'startup_products',
            );
            CloudSyncService.instance.scheduleCashSyncSoon(
              delay: const Duration(milliseconds: 350),
              reason: 'startup_cash',
            );
            CloudSyncService.instance.scheduleSalesSyncSoon(
              delay: const Duration(milliseconds: 450),
              reason: 'startup_sales',
            );
            CloudSyncService.instance.scheduleQuotesSyncSoon(
              delay: const Duration(milliseconds: 550),
              reason: 'startup_quotes',
            );
          } catch (_) {
            // Nunca bloquear UI por sync.
          }
        });
      });

      final businessRepo = BusinessSettingsRepository();
      final initialSettings = BusinessSettings.defaultSettings;

      diagnostics.markRunAppStart();
      runApp(
        ProviderScope(
          overrides: [
            businessRepositoryProvider.overrideWithValue(businessRepo),
            businessSettingsProvider.overrideWith(
              (ref) => BusinessSettingsNotifier(
                businessRepo,
                initial: initialSettings,
              ),
            ),
          ],
          child: const FullPosApp(),
        ),
      );

      // La ventana se muestra una sola vez desde AppEntry cuando bootstrap está listo.
    },
    (error, stack) {
      debugPrint('UNCAUGHT_ZONE_ERROR: $error');
      debugPrint('$stack');
      try {
        ErrorHandler.instance.reportPlatformError(
          error,
          stack,
          module: 'zoned',
        );
      } catch (_) {}
      unawaited(
        AppLogger.instance.logWarn(
          'UNCAUGHT_ZONE_ERROR: $error',
          module: 'zoned',
        ),
      );
    },
  );
}
