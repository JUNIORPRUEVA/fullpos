import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/ui/splash_page.dart';
import '../brand/fullpos_brand_theme.dart';
import 'app_bootstrap_controller.dart';
import '../window/window_service.dart';

final _minSplashDelayProvider = FutureProvider<void>((ref) async {
  if (Platform.isWindows) {
    // En Windows, la ventana se mantiene oculta durante el bootstrap.
    // No necesitamos un delay artificial para un arranque “pro”.
    return;
  }
  // Mantener el splash visible un mínimo para un arranque "POS" profesional.
  await Future<void>.delayed(const Duration(seconds: 5));
});

/// Gate visual del arranque.
///
/// - Mantiene un Splash/Error estable mientras se ejecuta el bootstrap.
/// - Evita “rebotes” de navegación durante init (no hay push/pop/replaces).
class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<AppEntry> {
  bool _windowShown = false;

  void _maybeShowWindowOnce({required bool showSplash}) {
    if (_windowShown) return;
    if (showSplash) return;

    _windowShown = true;
    assert(() {
      // ignore: avoid_print
      print('[WINDOW] bootstrap ready');
      return true;
    }());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Mostrar SOLO cuando el UI final ya está en pantalla.
      WindowService.showOnce();
    });
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(appBootstrapProvider).snapshot;
    final delay = ref.watch(_minSplashDelayProvider);

    final showSplash =
        boot.status != BootStatus.ready || (!Platform.isWindows && delay.isLoading);
    _maybeShowWindowOnce(showSplash: showSplash);

    final body = showSplash
        ? const FullposBrandScope(child: SplashPage())
        : widget.child;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey<bool>(showSplash), child: body),
    );
  }
}
