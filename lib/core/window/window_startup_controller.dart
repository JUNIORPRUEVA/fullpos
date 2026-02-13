import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_colors.dart';
import 'window_service.dart';

/// Centraliza el arranque de ventana en Desktop (especialmente Windows).
///
/// Objetivo:
/// - Aplicar opciones/tamaño con la ventana oculta (sin "cajita"/flash)
/// - Mostrar SOLO cuando el bootstrap esté READY y el layout ya esté pintado.
class WindowStartupController {
  WindowStartupController._();

  static final WindowStartupController instance = WindowStartupController._();

  bool _hiddenApplied = false;
  bool _shown = false;

  Future<void> applyHiddenStartup() async {
    if (_hiddenApplied) return;
    _hiddenApplied = true;

    if (!Platform.isWindows) return;

    const options = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(1100, 650),
      center: true,
      // Debe coincidir con el splash/marca para evitar flash blanco.
      backgroundColor: AppColors.bgDark,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'FULLPOS',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      try {
        await windowManager.hide();
        if (kDebugMode) {
          debugPrint('[WINDOW] hidden, applying options');
        }
      } catch (_) {
        // Ignorar.
      }

      // Importante: NO mostrar aquí.
      // Aplicar modo POS kiosko en Windows ANTES del show.
      // Esto asegura que la ventana aparezca una sola vez, ya a tamaño final.
      try {
        await WindowService.init();
        await WindowService.applyWindowsPosKioskModeForStartup(
          preferCurrentDisplay: false,
        );
      } catch (_) {
        // Fallback: ventana normal maximizada.
        try {
          await windowManager.setMinimumSize(const Size(1100, 650));
        } catch (_) {}
        try {
          await windowManager.maximize();
        } catch (_) {}
        try {
          await windowManager.setResizable(false);
        } catch (_) {}
      }
    });
  }

  Future<void> showWhenReady() {
    if (_shown) return Future<void>.value();
    _shown = true;

    if (!Platform.isWindows) return Future<void>.value();

    final completer = Completer<void>();

    // Esperar a que el frame post-ready esté pintado.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (kDebugMode) {
        debugPrint('[WINDOW] show once (after boot ready)');
      }
      try {
        final isMin = await windowManager.isMinimized();
        if (isMin) {
          await windowManager.restore();
        }
      } catch (_) {}

      try {
        await windowManager.show();
      } catch (_) {}
      try {
        await windowManager.focus();
      } catch (_) {}
      completer.complete();
    });

    return completer.future;
  }
}
