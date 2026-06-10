import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:window_manager/window_manager.dart';

/// Window service for desktop applications.
class WindowService {
  static bool _isInitialized = false;
  static int _lastWindowModeTransitionAtMs = 0;

  static void _markWindowModeTransition() {
    _lastWindowModeTransitionAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Initialize window_manager
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        debugPrint('[WINDOW] init');
      }
      await windowManager.ensureInitialized();
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] init error: $e');
      }
    }
  }

  static bool wasRecentWindowModeTransition({int withinMs = 1500}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - _lastWindowModeTransitionAtMs) <= withinMs;
  }

  /// Run an action while temporarily disabling alwaysOnTop
  /// (Useful for system file dialogs)
  static Future<T> runWithSystemDialog<T>(Future<T> Function() action) async {
    final result = await action();
    try {
      if (_isInitialized &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await windowManager.focus();
      }
    } catch (_) {}
    return result;
  }

  /// Temporarily disable alwaysOnTop for external application
  static Future<T> runWithExternalApplication<T>(
    Future<T> Function() action, {
    Duration restoreDelay = const Duration(milliseconds: 900),
  }) async {
    return action();
  }

  // Simple window operations (delegated to windowManager)

  static Future<void> setAlwaysOnTop(bool value) async {
    if (!_isInitialized) return;
    try {
      await windowManager.setAlwaysOnTop(value);
    } catch (_) {}
  }

  static Future<void> setPreventClose(bool value) async {
    if (!_isInitialized) return;
    try {
      await windowManager.setPreventClose(value);
    } catch (_) {}
  }

  static Future<void> show() async {
    if (!_isInitialized) return;
    try {
      await windowManager.show();
      _markWindowModeTransition();
    } catch (_) {}
  }

  static Future<void> minimize() async {
    if (!_isInitialized) return;
    try {
      await windowManager.minimize();
      _markWindowModeTransition();
    } catch (_) {}
  }

  static Future<void> maximize() async {
    if (!_isInitialized) return;
    try {
      await windowManager.maximize();
      _markWindowModeTransition();
    } catch (_) {}
  }

  static Future<bool> isMaximized() async {
    if (!_isInitialized) return false;
    try {
      return await windowManager.isMaximized();
    } catch (_) {
      return false;
    }
  }

  static Future<void> toggleMaximize() async {
    if (!_isInitialized) return;
    try {
      final maximized = await isMaximized();
      if (maximized) {
        await windowManager.restore();
      } else {
        await windowManager.maximize();
      }
      _markWindowModeTransition();
    } catch (_) {}
  }

  static Future<void> restore() async {
    if (!_isInitialized) return;
    try {
      await windowManager.restore();
      _markWindowModeTransition();
    } catch (_) {}
  }

  static Future<void> close() async {
    if (!_isInitialized) return;
    try {
      await windowManager.close();
    } catch (_) {}
  }

  static Future<void> forceClose() async {
    await close();
  }

  static Future<void> applyBranding({
    required String businessName,
    String? logoPath,
  }) async {
    if (!_isInitialized) return;
    try {
      await windowManager.setTitle('FullPOS - Sistema de facturación');
    } catch (_) {}
  }

  /// Recover visual state after app resume (minimize/restore cycle)
  /// Ensures window is visible, not minimized, and layout is refreshed
  static Future<void> recoverVisualState({bool forceSizeNudge = false}) async {
    if (!_isInitialized || !Platform.isWindows) return;

    try {
      // Ensure window is visible
      try {
        final isVisible = await windowManager.isVisible();
        if (!isVisible) {
          await windowManager.show();
        }
      } catch (_) {}

      // Restore if minimized
      try {
        final isMin = await windowManager.isMinimized();
        if (isMin) {
          await windowManager.restore();
          _markWindowModeTransition();
        }
      } catch (_) {}

      // Refresh bounds to trigger layout
      if (forceSizeNudge) {
        try {
          final bounds = await windowManager.getBounds();
          await windowManager.setBounds(bounds);
        } catch (_) {}
      }

      // Schedule frame repaint
      WidgetsBinding.instance.scheduleFrame();
    } catch (_) {
      // Ignore recovery errors - don't block app
    }
  }
}
