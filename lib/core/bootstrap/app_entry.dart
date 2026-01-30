import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/ui/splash_page.dart';
import 'app_bootstrap_controller.dart';

final _minSplashDelayProvider = FutureProvider<void>((ref) async {
  // Mantener el splash visible un mínimo para un arranque "POS" profesional.
  await Future<void>.delayed(const Duration(seconds: 5));
});

/// Gate visual del arranque.
///
/// - Mantiene un Splash/Error estable mientras se ejecuta el bootstrap.
/// - Evita “rebotes” de navegación durante init (no hay push/pop/replaces).
class AppEntry extends ConsumerWidget {
  const AppEntry({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootstrapProvider).snapshot;
    final delay = ref.watch(_minSplashDelayProvider);

    final showSplash = boot.status != BootStatus.ready || delay.isLoading;
    final body = showSplash ? const SplashPage() : child;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey<bool>(showSplash),
        child: body,
      ),
    );
  }
}
