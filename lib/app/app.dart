import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bootstrap/app_entry.dart';
import '../core/bootstrap/bootstrap_loading_screen.dart';
import '../core/backup/backup_lifecycle.dart';
import '../core/brand/fullpos_brand_theme.dart';
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
          color: FullposBrandTheme.background,
          title: businessSettings.businessName.isNotEmpty
              ? businessSettings.businessName
              : 'FULLPOS',
          debugShowCheckedModeBanner: false,
          theme: themeData.copyWith(
            scaffoldBackgroundColor: FullposBrandTheme.background,
          ),
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
            final safeChild = child ?? const BootstrapLoadingScreen();

            final layered = Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: FullposBrandTheme.background),
                safeChild,
              ],
            );
            final content = AppEntry(
              child: AppLoadingOverlay(
                child: layered,
              ),
            );
            return AppFrame(child: content);
          },
        ),
      ),
    );
  }
}
