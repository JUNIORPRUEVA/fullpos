import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/debug/render_diagnostics.dart';
import 'core/db/db_init.dart';
import 'core/errors/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'core/services/cloud_sync_service.dart';
import 'core/theme/theme_audit.dart';
import 'core/window/window_service.dart';
import 'features/settings/data/business_settings_model.dart';
import 'features/settings/data/business_settings_repository.dart';
import 'features/settings/providers/business_settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final diagnostics = RenderDiagnostics.instance;
  await diagnostics.ensureInitialized();
  diagnostics.installGlobalErrorHandlers();

  // Temporary: make sure Flutter framework errors are always visible in the
  // Debug Console with a full stack trace.
  final originalFlutterOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final stack = details.stack ?? StackTrace.current;
    final message = details.exceptionAsString();
    debugPrint('FLUTTER_ERROR: $message');
    debugPrint('$stack');
    try {
      ErrorHandler.instance
          .reportPlatformError(details.exception, stack, module: 'flutter');
    } catch (_) {}
    unawaited(
      AppLogger.instance
          .logWarn('FLUTTER_ERROR: $message', module: 'flutter'),
    );
    if (originalFlutterOnError != null) {
      originalFlutterOnError(details);
    } else {
      FlutterError.dumpErrorToConsole(details);
    }
  };

  await runZonedGuarded(() async {
  try {
    await AppLogger.instance.init();
  } catch (_) {
    // Si falla el logger, no detenemos el arranque.
  }

  DbInit.ensureInitialized();
  if (kDebugMode) {
    ThemeAudit.run();
  }

  // Desktop window init (fullscreen/kiosk + titlebar hidden en Windows).
  // No bloquea el arranque si falla.
  try {
    await WindowService.init();
    WindowService.scheduleInitialLayoutFix();
  } catch (_) {
    // Ignorar: la app debe poder arrancar igual.
  }
  // FULLPOS DB HARDENING: sincronizar configuracion en la nube sin bloquear UI.
  // Importante: estas tareas pueden ser pesadas (leer DB, armar payloads grandes, subir imágenes).
  // Para evitar “cámara lenta”/jank, se difieren y se escalonan después del primer frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>(() async {
      try {
        await Future<void>.delayed(const Duration(seconds: 2));
        await CloudSyncService.instance.syncCompanyConfigIfEnabled();

        await Future<void>.delayed(const Duration(seconds: 4));
        await CloudSyncService.instance.syncProductsIfEnabled();

        await Future<void>.delayed(const Duration(seconds: 6));
        await CloudSyncService.instance.syncCashIfEnabled();

        await Future<void>.delayed(const Duration(seconds: 8));
        await CloudSyncService.instance.syncSalesIfEnabled();

        await Future<void>.delayed(const Duration(seconds: 10));
        await CloudSyncService.instance.syncQuotesIfEnabled();
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
          (ref) =>
              BusinessSettingsNotifier(businessRepo, initial: initialSettings),
        ),
      ],
      child: const FullPosApp(),
    ),
  );

  // Mostrar la ventana después del primer frame (evita pantalla negra en Windows).
  try {
    WindowService.scheduleShowAfterFirstFrame();
  } catch (_) {
    // Ignorar.
  }
  }, (error, stack) {
    debugPrint('UNCAUGHT_ZONE_ERROR: $error');
    debugPrint('$stack');
    try {
      ErrorHandler.instance.reportPlatformError(error, stack, module: 'zoned');
    } catch (_) {}
    unawaited(
      AppLogger.instance
          .logWarn('UNCAUGHT_ZONE_ERROR: $error', module: 'zoned'),
    );
  });
}
