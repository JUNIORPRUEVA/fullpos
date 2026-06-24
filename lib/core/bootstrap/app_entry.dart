import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/ui/splash_page.dart';
import '../session/session_manager.dart';
import '../services/cloud_sync_service.dart';
import '../sync/product_sync_service.dart';
import '../window/window_startup_controller.dart';
import '../update/app_update_coordinator.dart';
import '../update/update_gate.dart';
import 'app_bootstrap_controller.dart';

final _minSplashDelayProvider = FutureProvider<void>((ref) async {
  await Future<void>.delayed(
    Platform.isWindows
        ? const Duration(milliseconds: 2200)
        : const Duration(milliseconds: 2600),
  );
});

class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<AppEntry>
    with SingleTickerProviderStateMixin {
  bool _windowShowScheduled = false;
  bool _startupSyncScheduled = false;
  late AnimationController _splashAnimController;
  late Animation<double> _splashOpacity;

  @override
  void initState() {
    super.initState();
    _splashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _splashOpacity = CurvedAnimation(
      parent: _splashAnimController,
      curve: Curves.easeOutCubic,
    );
    // Inicia con opacidad 1.0 (splash visible)
    _splashAnimController.value = 1.0;
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showWindowAfterFirstPaint());
      });
      // Iniciar verificación de actualizaciones una sola vez al arrancar.
      // No debe estar en el redirect del router porque se ejecuta en cada
      // navegación y puede causar descargas/diálogos repetidos.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(AppUpdateCoordinator.instance.ensureStarted());
      });
    }
  }

  @override
  void dispose() {
    _splashAnimController.dispose();
    super.dispose();
  }

  Future<void> _startDeferredSync() async {
    if (_startupSyncScheduled) return;
    if (!await SessionManager.isLoggedIn() ||
        await SessionManager.companyId() == null) {
      return;
    }
    _startupSyncScheduled = true;

    try {
      ProductSyncService.instance.start();
      await CloudSyncService.instance.syncRequiredTargetsNow(
        reason: 'app_start_required_sync',
      );
      CloudSyncService.instance.startRealtimeSyncEngine();
      await ProductSyncService.instance.retryFailedNow();
      await ProductSyncService.instance.flushNow();
    } catch (_) {
      // Nunca bloquear UI por sync.
    }
  }

  Future<void> _showWindowAfterFirstPaint() async {
    if (_windowShowScheduled) return;
    _windowShowScheduled = true;

    try {
      await WindowStartupController.instance.showWhenReady();
    } finally {
      _windowShowScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BootStatus>(
      appBootstrapProvider.select((b) => b.snapshot.status),
      (prev, next) {
        if (next == BootStatus.ready && prev != BootStatus.ready) {
          unawaited(_startDeferredSync());
        }
      },
    );

    final boot = ref.watch(appBootstrapProvider).snapshot;
    final delay = ref.watch(_minSplashDelayProvider);

    final showSplash = boot.status != BootStatus.ready || delay.isLoading;

    // Cuando ambas condiciones se cumplen, iniciar el fade-out del splash
    if (!showSplash && _splashAnimController.isCompleted) {
      _splashAnimController.reverse();
    }

    // Stack con hijos FIJOS (nunca cambian) para evitar que Flutter
    // reconstruya el Navigator del router.
    // El splash se desvanece sobre la app que ya está renderizada detrás.
    return UpdateGate(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Capa inferior: la app siempre renderizada y estable
          widget.child,

          // Capa superior: splash que se desvanece, siempre en el árbol
          FadeTransition(
            opacity: _splashOpacity,
            child: const IgnorePointer(
              child: SplashPage(),
            ),
          ),
        ],
      ),
    );
  }
}
