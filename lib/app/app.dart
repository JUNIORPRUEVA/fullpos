import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bootstrap/app_entry.dart';
import '../core/bootstrap/bootstrap_loading_screen.dart';
import '../core/backup/backup_lifecycle.dart';
import '../core/loading/app_loading_overlay.dart';
import '../core/notifications/fullpos_notification_host.dart';
import '../core/shortcuts/app_shortcuts.dart';
import '../core/window/window_service.dart';
import '../features/settings/providers/business_settings_provider.dart';
import '../features/settings/providers/theme_provider.dart';
import '../core/widgets/app_frame.dart';
import '../core/widgets/app_global_background.dart';
import 'router.dart';

/// Aplicación principal FULLPOS
class FullPosApp extends ConsumerWidget {
  const FullPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(themeDataProvider);
    final lightTheme = themeData.copyWith(
      brightness: Brightness.light,
      colorScheme: themeData.colorScheme.copyWith(brightness: Brightness.light),
      scaffoldBackgroundColor: themeData.scaffoldBackgroundColor,
      canvasColor: themeData.scaffoldBackgroundColor,
      dialogBackgroundColor: themeData.colorScheme.surface,
    );
    final businessSettings = ref.watch(businessSettingsProvider);
    final router = ref.watch(appRouterProvider);

    ref.listen(businessSettingsProvider, (previous, next) {
      if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
      unawaited(
        WindowService.applyBranding(
          businessName: next.businessName,
          logoPath: next.logoPath,
        ),
      );
    });

    return AppShortcuts(
      child: BackupLifecycle(
        child: MaterialApp.router(
          color: themeData.scaffoldBackgroundColor,
          title: businessSettings.businessName.isNotEmpty
              ? businessSettings.businessName
              : 'FULLPOS',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          themeMode: ThemeMode.light,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('es', 'DO'),
            Locale('es'),
            Locale('en'),
          ],
          routerConfig: router,
          builder: (context, child) {
            Widget? effectiveChild = child;

            // En algunos estados transitorios (redirects async / router warmup),
            // go_router puede entregar un placeholder (ej: SizedBox.shrink()).
            // Eso se ve como una pantalla "vacía" con el color de marca.
            if (effectiveChild is SizedBox &&
                effectiveChild.width == 0 &&
                effectiveChild.height == 0 &&
                effectiveChild.child == null) {
              effectiveChild = null;
            }

            final safeChild = effectiveChild ?? const BootstrapLoadingScreen();

            final layered = AppGlobalBackground(child: safeChild);
            final content = AppEntry(child: AppLoadingOverlay(child: layered));
            return AppFrame(child: FullPosNotificationHost(child: content));
          },
        ),
      ),
    );
  }
}
