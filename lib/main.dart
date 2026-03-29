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

      // Desktop window startup (Windows): Apply options before runApp.
      // This ensures window is configured while hidden, preventing flicker.
      // No show here - AppEntry controls show when bootstrap is ready.
      try {
        await windowManager.ensureInitialized();
        await WindowStartupController.instance.applyStartupOptions();
      } catch (_) {
        // Ignore: app must work even if window startup fails
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
