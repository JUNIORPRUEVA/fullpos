import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'window_service.dart';

/// Centralizes Windows startup so the native window stays hidden until Flutter
/// paints a real frame.
class WindowStartupController {
  WindowStartupController._();

  static final WindowStartupController instance = WindowStartupController._();

  bool _optionsApplied = false;
  bool _shown = false;

  Future<WindowOptions> _resolveStartupOptions() async {
    const fallbackSize = Size(1600, 900);
    var startupSize = fallbackSize;

    try {
      final display = await screenRetriever.getPrimaryDisplay();
      startupSize = display.visibleSize ?? display.size;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] primary display size unavailable: $e');
      }
    }

    if (startupSize.width < 1100 || startupSize.height < 650) {
      startupSize = const Size(1280, 720);
    }

    return WindowOptions(
      size: startupSize,
      minimumSize: const Size(1100, 650),
      center: true,
      backgroundColor: const Color(0xFFFFFFFF),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'FULLPOS',
    );
  }

  /// Apply startup window options while hidden.
  Future<void> applyStartupOptions() async {
    if (_optionsApplied) return;
    _optionsApplied = true;

    if (!Platform.isWindows) return;

    final options = await _resolveStartupOptions();

    try {
      await windowManager.waitUntilReadyToShow(options, () async {
        try {
          await windowManager.hide();
        } catch (_) {
          // Ignore - the window may already be hidden.
        }

        if (kDebugMode) {
          debugPrint('[WINDOW] startup options applied (hidden)');
        }
      });

      try {
        await WindowService.init();
        await windowManager.setMinimumSize(const Size(1100, 650));
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setResizable(true);
        await windowManager.maximize();

        if (kDebugMode) {
          debugPrint('[WINDOW] startup window prepared (hidden, maximized)');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[WINDOW] startup window preparation failed: $e');
        }
        try {
          await windowManager.setMinimumSize(const Size(1100, 650));
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
          await windowManager.setResizable(true);
          await windowManager.maximize();
        } catch (_) {
          // Ignore fallback failures to avoid blocking startup.
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] startup options error: $e');
      }
    }
  }

  /// Show the hidden window exactly once after Flutter paints its first frame.
  Future<void> showWhenReady() async {
    if (_shown) return;
    _shown = true;

    if (!Platform.isWindows) return;

    if (kDebugMode) {
      debugPrint('[WINDOW] show (first Flutter frame)');
    }

    try {
      try {
        final isMin = await windowManager.isMinimized();
        if (isMin) {
          await windowManager.restore();
        }
      } catch (_) {
        // Ignore restore failures.
      }

      await windowManager.show();

      try {
        await windowManager.focus();
      } catch (_) {
        // Ignore focus failures.
      }

      if (kDebugMode) {
        debugPrint('[WINDOW] shown successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] show error: $e');
      }
    }
  }
}

