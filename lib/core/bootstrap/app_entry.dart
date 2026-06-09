import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/ui/splash_page.dart';
import '../session/session_manager.dart';
import '../services/cloud_sync_service.dart';
import '../sync/product_sync_service.dart';
import '../window/window_startup_controller.dart';
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

class _AppEntryState extends ConsumerState<AppEntry> {
  bool _windowShowScheduled = false;
  bool _startupSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showWindowAfterFirstPaint());
      });
    }
  }

  Future<void> _startDeferredSync() async {
    if (_startupSyncScheduled) return;
    if (!await SessionManager.isLoggedIn() ||
        await SessionManager.companyId() == null) {
      return;
    }
    _startupSyncScheduled = true;

    try {
      CloudSyncService.instance.startRealtimeSyncEngine();
      ProductSyncService.instance.start();
      unawaited(CloudSyncService.instance.syncProductsIfEnabled());
      CloudSyncService.instance.scheduleProductsSyncSoon(
        delay: const Duration(milliseconds: 100),
        reason: 'startup_products',
      );
      CloudSyncService.instance.scheduleSalesSyncSoon(
        delay: const Duration(milliseconds: 180),
        reason: 'startup_sales',
      );
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

    final showSplash =
        boot.status != BootStatus.ready || delay.isLoading;

    final switchDuration = Platform.isWindows
        ? Duration.zero
        : const Duration(milliseconds: 350);

    final body = showSplash ? const SplashPage() : widget.child;

    return AnimatedSwitcher(
      duration: switchDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey<bool>(showSplash), child: body),
    );
  }
}
