import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/loader_watchdog.dart';
import '../debug/render_diagnostics.dart';

/// Controlador global de loading.
/// Usa un contador para soportar cargas anidadas sin apagarse antes de tiempo.
class AppLoadingController extends StateNotifier<int> {
  AppLoadingController() : super(0);

  LoaderWatchdog? _watchdog;

  void show() {
    final wasIdle = state <= 0;
    state = state + 1;
    if (wasIdle) {
      _watchdog?.dispose();
      _watchdog = LoaderWatchdog.start(stage: 'overlay/global_loading');
    }
    unawaited(
      RenderDiagnostics.instance.logOverlay(
        'show',
        data: {'depth': state},
      ),
    );
  }

  void hide() {
    final next = state - 1;
    state = next < 0 ? 0 : next;
    if (state == 0) {
      _watchdog?.dispose();
      _watchdog = null;
    }
    unawaited(
      RenderDiagnostics.instance.logOverlay(
        'hide',
        data: {'depth': state},
      ),
    );
  }

  Future<T> wrap<T>(Future<T> Function() action) async {
    show();
    try {
      return await action();
    } finally {
      hide();
    }
  }

  @override
  void dispose() {
    _watchdog?.dispose();
    _watchdog = null;
    super.dispose();
  }
}

final appLoadingProvider = StateNotifierProvider<AppLoadingController, int>((
  ref,
) {
  return AppLoadingController();
});

final appIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(appLoadingProvider) > 0;
});
