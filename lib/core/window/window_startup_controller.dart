import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

  /// Apply window options (size, position, kiosk mode) while window is hidden.
  /// Called from main() before runApp() to ensure options are set before show.
  Future<void> applyStartupOptions() async {
    if (_optionsApplied) return;
    _optionsApplied = true;

    if (!Platform.isWindows) return;

    // For Windows POS, we want kiosk mode (full screen, frameless).
    // Don't use size/position options; kiosk will handle bounds.
    const options = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(1100, 650),
      center: true,
      backgroundColor: AppColors.bgDark,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'FULLPOS',
    );

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
        // Apply kiosk mode at startup
        // This ensures: frameless, always-on-top, non-resizable, full screen bounds
        await WindowService.applyWindowsPosKioskModeForStartup(
          preferCurrentDisplay: true,
        );

        if (kDebugMode) {
          debugPrint('[WINDOW] kiosk mode applied (startup)');
        }
      } catch (e) {
        // Fallback: normal maximized window
        if (kDebugMode) {
          debugPrint('[WINDOW] kiosk mode failed, applying fallback: $e');
        }
        try {
          await windowManager.setMinimumSize(const Size(1100, 650));
          await windowManager.maximize();
          await windowManager.setResizable(false);
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

