import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_colors.dart';
import 'window_service.dart';

/// Centralizes window startup on Desktop (Windows focus).
///
/// **Design**: Dart owns window visibility. Native (C++) creates window but never shows it.
/// This eliminates race conditions and ensures deterministic startup.
///
/// **Flow**:
/// 1. main() calls applyStartupOptions() - apply options while hidden
/// 2. AppEntry detects bootstrap ready - calls showWhenReady()
/// 3. Window shows exactly once, fully formed, no flicker
///
/// **Key principle**: No dual show logic. Native handles rendering.
/// Dart handles visibility and configuration.
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
      backgroundColor: AppColors.bgLightAlt,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'FULLPOS',
    );
  }

  /// Apply window options (size, position, kiosk mode) while window is hidden.
  /// Called from main() before runApp() to ensure options are set before show.
  Future<void> applyStartupOptions() async {
    if (_optionsApplied) return;
    _optionsApplied = true;

    if (!Platform.isWindows) return;

    final options = await _resolveStartupOptions();

    try {
      await windowManager.waitUntilReadyToShow(options, () async {
        // Window is now created but hidden
        try {
          await windowManager.hide();
        } catch (_) {
          // Ignore - may already be hidden
        }

        if (kDebugMode) {
          debugPrint('[WINDOW] startup options applied (hidden)');
        }
      });

      // After waitUntilReadyToShow completes, apply kiosk mode
      // Do this AFTER the initial window setup to ensure it takes effect
      await Future<void>.delayed(const Duration(milliseconds: 50));

      try {
        await WindowService.init();
        if (WindowService.isFullScreen()) {
          // Apply kiosk mode at startup only when user preference enables it.
          await WindowService.applyWindowsPosKioskModeForStartup(
            preferCurrentDisplay: true,
          );

          if (kDebugMode) {
            debugPrint('[WINDOW] kiosk mode applied (startup)');
          }
        } else {
          // In normal mode, keep startup operations minimal while hidden.
          await windowManager.setMinimumSize(const Size(1100, 650));
          await windowManager.setResizable(true);
          await windowManager.maximize();
          await Future<void>.delayed(const Duration(milliseconds: 16));

          if (kDebugMode) {
            debugPrint('[WINDOW] windowed mode prepared (startup maximized)');
          }
        }
      } catch (e) {
        // Fallback: normal maximized window
        if (kDebugMode) {
          debugPrint('[WINDOW] kiosk mode failed, applying fallback: $e');
        }
        try {
          await windowManager.setMinimumSize(const Size(1100, 650));
          await windowManager.setResizable(true);
          await windowManager.maximize();
          await Future<void>.delayed(const Duration(milliseconds: 16));
        } catch (_) {
          // Ensure app doesn't hang if window setup fails
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] startup options error: $e');
      }
    }
  }

  /// Show window exactly once when bootstrap is ready.
  /// Called from AppEntry when BootStatus transitions to ready.
  /// Window appears fully formed with all options already applied.
  Future<void> showWhenReady() async {
    if (_shown) return;
    _shown = true;

    if (!Platform.isWindows) return;

    if (kDebugMode) {
      debugPrint('[WINDOW] show (bootstrap ready)');
    }

    try {
      if (!WindowService.isFullScreen()) {
        try {
          final isMaximized = await windowManager.isMaximized();
          if (!isMaximized) {
            await windowManager.maximize();
            await Future<void>.delayed(const Duration(milliseconds: 16));
          }
        } catch (_) {
          // Ignore
        }
      }

      // Restore if minimized (can happen if user minimized during bootstrap)
      try {
        final isMin = await windowManager.isMinimized();
        if (isMin) {
          await windowManager.restore();
        }
      } catch (_) {
        // Ignore
      }

      // Show window. It's properly sized and kiosk mode applied.
      // No resize, reposition, or mode changes needed - done while hidden.
      await windowManager.show();

      // Optional: focus window
      try {
        await windowManager.focus();
      } catch (_) {
        // Ignore
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

