import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bootstrap/app_entry.dart';
import '../core/backup/backup_lifecycle.dart';
import '../core/loading/app_loading_overlay.dart';
import '../core/shortcuts/app_shortcuts.dart';
import '../core/window/window_service.dart';
import '../features/settings/providers/business_settings_provider.dart';
import '../features/settings/providers/theme_provider.dart';
import '../core/widgets/app_frame.dart';
import 'router.dart';

/// Aplicación principal FULLPOS
class FullPosApp extends ConsumerWidget {
  const FullPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(themeDataProvider);
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
          title: businessSettings.businessName.isNotEmpty
              ? businessSettings.businessName
              : 'FULLPOS',
          debugShowCheckedModeBanner: false,
          theme: themeData,
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
            final content = AppEntry(
              child: AppLoadingOverlay(
                child: child ?? const SizedBox.shrink(),
              ),
            );
            return AppFrame(child: content);
          },
        ),
      ),
    );
  }
}
