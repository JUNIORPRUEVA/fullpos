import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bootstrap/app_entry.dart';
import '../core/bootstrap/app_bootstrap_controller.dart';
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
            Widget? effectiveChild = child;

            final bootStatus = ref.watch(
              appBootstrapProvider.select((b) => b.snapshot.status),
            );

            // En algunos estados transitorios (redirects async / router warmup),
            // go_router puede entregar un placeholder (ej: SizedBox.shrink()).
            // Eso se ve como una pantalla "vacía" con el color de marca.
            if (effectiveChild is SizedBox &&
                effectiveChild.width == 0 &&
                effectiveChild.height == 0 &&
                effectiveChild.child == null) {
              effectiveChild = null;
            }

            final safeChild = _StableRouterChild(
              bootReady: bootStatus == BootStatus.ready,
              child: effectiveChild,
            );

            final layered = Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: FullposBrandTheme.background),
                safeChild,
              ],
            );
            final content = AppEntry(child: AppLoadingOverlay(child: layered));
            return AppFrame(child: content);
          },
        ),
      ),
    );
  }
}

class _StableRouterChild extends StatefulWidget {
  const _StableRouterChild({required this.bootReady, required this.child});

  final bool bootReady;
  final Widget? child;

  @override
  State<_StableRouterChild> createState() => _StableRouterChildState();
}

class _StableRouterChildState extends State<_StableRouterChild> {
  Widget? _lastNonNullChild;

  @override
  void didUpdateWidget(covariant _StableRouterChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child != null) {
      _lastNonNullChild = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.bootReady) {
      return widget.child ?? const BootstrapLoadingScreen();
    }

    return widget.child ?? _lastNonNullChild ?? const BootstrapLoadingScreen();
  }
}
