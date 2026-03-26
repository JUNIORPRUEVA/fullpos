import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Window service for desktop applications.
///
/// **Design**: Simplified, clear responsibilities.
/// - Dart owns window visibility (show/hide/maximize)
/// - One authority per operation
/// - No retry loops or complex state machine
/// - Enforcer only restores visibility, doesn't spam re-maximize
class WindowService {
  static bool _isInitialized = false;
  static bool _isFullScreen = false;
  static bool _isFullscreenTransitioning = false;
  static int _systemDialogDepth = 0;
  static bool _restoreAlwaysOnTopAfterDialog = false;
  static bool _enforcerInstalled = false;

  /// Notifier for UI to react when fullscreen state changes
  static final ValueNotifier<bool> fullScreenListenable = ValueNotifier<bool>(
    false,
  );

  static void _publishFullScreenState(bool value) {
    _isFullScreen = value;
    fullScreenListenable.value = value;
  }

  /// Initialize window_manager
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        debugPrint('[WINDOW] init');
      }
      await windowManager.ensureInitialized();
      _installEnforcer();

      // Load fullscreen state from preferences
      try {
        final prefs = await SharedPreferences.getInstance();
        _publishFullScreenState(prefs.getBool('pos_fullscreen') ?? false);
      } catch (_) {
        _publishFullScreenState(false);
      }

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] init error: $e');
      }
    }
  }

  static Future<void> _runFullscreenTransition(
    Future<void> Function() action,
  ) async {
    if (_isFullscreenTransitioning) {
      if (kDebugMode) {
        debugPrint('[WINDOW] fullscreen transition skipped (already running)');
      }
      return;
    }

    _isFullscreenTransitioning = true;
    try {
      return await action();
    } finally {
      _isFullscreenTransitioning = false;
    }
  }

  /// Apply Windows POS kiosk mode: full screen without system fullscreen.
  /// Called while window is hidden during startup.
  /// MUST NOT be called frequently - only at startup and after minimize/restore.
  static Future<void> _applyWindowsPosKioskMode({
    bool preferCurrentDisplay = true,
  }) async {
    await _runFullscreenTransition(() async {
      if (kDebugMode) {
        debugPrint(
          '[WINDOW] applying kiosk mode, preferCurrentDisplay=$preferCurrentDisplay',
        );
      }

      try {
        await windowManager.setSkipTaskbar(true);
      } catch (e) {
        if (kDebugMode) debugPrint('[WINDOW] setSkipTaskbar(true) failed: $e');
      }

      try {
        await windowManager.setAlwaysOnTop(true);
      } catch (e) {
        if (kDebugMode) debugPrint('[WINDOW] setAlwaysOnTop failed: $e');
      }

      try {
        await windowManager.setFullScreen(true);
      } catch (e) {
        if (kDebugMode) debugPrint('[WINDOW] setFullScreen(true) failed: $e');
      }

      try {
        await windowManager.setResizable(false);
      } catch (e) {
        if (kDebugMode) debugPrint('[WINDOW] setResizable(false) failed: $e');
      }

      if (kDebugMode) {
        debugPrint('[WINDOW] kiosk mode application complete');
      }
    });
  }

  /// Apply POS kiosk mode while window is hidden (startup only).
  /// This is the ONLY place kiosk mode is applied at startup.
  static Future<void> applyWindowsPosKioskModeForStartup({
    bool preferCurrentDisplay = false,
  }) async {
    if (!Platform.isWindows) return;
    await _applyWindowsPosKioskMode(preferCurrentDisplay: preferCurrentDisplay);
  }

  /// Reapply kiosk mode after restore/unmaximize
  /// Used internally by enforcer to restore kiosk state
  static Future<void> _reapplyKioskModeAfterRestore() async {
    if (!Platform.isWindows) return;
    try {
      final stillFullScreen = await windowManager.isFullScreen();
      if (stillFullScreen) {
        try {
          await windowManager.setSkipTaskbar(true);
        } catch (_) {}
        try {
          await windowManager.setAlwaysOnTop(true);
        } catch (_) {}
        try {
          await windowManager.setResizable(false);
        } catch (_) {}
        return;
      }
    } catch (_) {}
    await _applyWindowsPosKioskMode(preferCurrentDisplay: true);
  }

  static Future<void> _applyWindowsWindowedMode() async {
    await _runFullscreenTransition(() async {
      if (kDebugMode) {
        debugPrint('[WINDOW] applying windowed mode');
      }

      try {
        await windowManager.setAlwaysOnTop(false);
      } catch (_) {}

      try {
        await windowManager.setFullScreen(false);
      } catch (_) {}

      try {
        await windowManager.setSkipTaskbar(false);
      } catch (_) {}

      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      } catch (_) {}

      try {
        await windowManager.setResizable(true);
      } catch (_) {}

      try {
        await windowManager.setMinimumSize(const Size(1100, 650));
      } catch (_) {}

      try {
        await windowManager.maximize();
      } catch (_) {}

      if (kDebugMode) {
        debugPrint('[WINDOW] windowed mode application complete');
      }
    });
  }

  /// Apply normal maximized desktop mode after the window is visible.
  static Future<void> ensureWindowedDesktopMode() async {
    if (!Platform.isWindows || !_isInitialized) return;
    await _applyWindowsWindowedMode();
    try {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await windowManager.show();
      }
    } catch (_) {}
    try {
      await windowManager.focus();
    } catch (_) {}
  }

  /// Ensure window appears on restore/unminimize
  static void _installEnforcer() {
    if (_enforcerInstalled) return;
    _enforcerInstalled = true;
    try {
      windowManager.addListener(_PosWindowEnforcer.instance);
    } catch (_) {
      // Ignore
    }
  }

  /// Set fullscreen state
  static Future<void> setFullScreen(
    bool value, {
    bool savePreference = true,
  }) async {
    if (!_isInitialized) return;

    final effectiveValue = value;

    if (Platform.isWindows) {
      if (effectiveValue) {
        // Apply kiosk mode on Windows
        await _applyWindowsPosKioskMode(preferCurrentDisplay: true);
      } else {
        await _applyWindowsWindowedMode();
      }
    } else {
      // Non-Windows platforms: use system fullscreen
      await windowManager.setFullScreen(effectiveValue);

      if (effectiveValue) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await windowManager.setResizable(false);
      } else {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setResizable(true);
        await windowManager.maximize();
      }
    }

    _publishFullScreenState(effectiveValue);

    // Save preference
    if (savePreference) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pos_fullscreen', effectiveValue);
      } catch (_) {
        // Ignore
      }
    }
  }

  /// Toggle fullscreen
  static Future<void> toggleFullScreen() async {
    await setFullScreen(!_isFullScreen);
  }

  /// Get fullscreen state
  static bool isFullScreen() => _isFullScreen;

  /// Run an action while temporarily disabling alwaysOnTop
  /// (Useful for system file dialogs)
  static Future<T> runWithSystemDialog<T>(Future<T> Function() action) async {
    if (!Platform.isWindows || !_isInitialized) {
      return action();
    }

    _systemDialogDepth++;
    if (_systemDialogDepth == 1) {
      _restoreAlwaysOnTopAfterDialog = _isFullScreen;
      if (_restoreAlwaysOnTopAfterDialog) {
        try {
          await windowManager.setAlwaysOnTop(false);
          await Future<void>.delayed(const Duration(milliseconds: 75));
        } catch (_) {}
      }
    }

    try {
      return await action();
    } finally {
      _systemDialogDepth--;
      if (_systemDialogDepth == 0) {
        if (_restoreAlwaysOnTopAfterDialog && _isFullScreen) {
          try {
            await windowManager.setAlwaysOnTop(true);
          } catch (_) {}
        }
        try {
          await windowManager.focus();
        } catch (_) {}
      }
    }
  }

  /// Temporarily disable alwaysOnTop for external application
  static Future<T> runWithExternalApplication<T>(
    Future<T> Function() action, {
    Duration restoreDelay = const Duration(milliseconds: 900),
  }) async {
    if (!Platform.isWindows || !_isInitialized) {
      return action();
    }

    final shouldRestore = _isFullScreen;

    if (shouldRestore) {
      try {
        await windowManager.setAlwaysOnTop(false);
        await Future<void>.delayed(const Duration(milliseconds: 75));
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      if (shouldRestore) {
        Future<void>.delayed(restoreDelay, () async {
          try {
            await windowManager.setAlwaysOnTop(true);
          } catch (_) {}
        });
      }
    }
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
    } catch (_) {}
  }

  static Future<void> minimize() async {
    if (!_isInitialized) return;
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  static Future<void> maximize() async {
    if (!_isInitialized) return;
    try {
      await windowManager.maximize();
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
    } catch (_) {}
  }

  static Future<void> restore() async {
    if (!_isInitialized) return;
    try {
      await windowManager.restore();
    } catch (_) {}
  }

  static Future<void> close() async {
    if (!_isInitialized) return;
    try {
      await windowManager.close();
    } catch (_) {}
  }

  static Future<void> applyBranding({
    required String businessName,
    String? logoPath,
  }) async {
    if (!_isInitialized) return;
    try {
      await windowManager.setTitle('FULLPOS');
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
        }
      } catch (_) {}

      // Refresh bounds to trigger layout
      try {
        final bounds = await windowManager.getBounds();
        await windowManager.setBounds(bounds);
      } catch (_) {}

      // Schedule frame repaint
      WidgetsBinding.instance.scheduleFrame();
    } catch (_) {
      // Ignore recovery errors - don't block app
    }
  }
}

/// Simple enforcer: ensures POS window stays visible and in expected state.
/// Reapplies kiosk mode after minimize/restore/unmaximize.
class _PosWindowEnforcer with WindowListener {
  _PosWindowEnforcer._();

  static final _PosWindowEnforcer instance = _PosWindowEnforcer._();

  bool _restoreInProgress = false;

  @override
  void onWindowRestore() async {
    if (_restoreInProgress) return;
    _restoreInProgress = true;
    try {
      if (kDebugMode) {
        debugPrint('[WINDOW] onWindowRestore triggered');
      }

      // After restore, reapply kiosk mode to ensure it's still configured
      // (Windows may have reset some settings during minimize/restore)
      if (Platform.isWindows && WindowService.isFullScreen()) {
        if (kDebugMode) {
          debugPrint('[WINDOW] reapplying kiosk mode after restore');
        }
        await WindowService._reapplyKioskModeAfterRestore();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] onWindowRestore error: $e');
      }
    } finally {
      _restoreInProgress = false;
    }
  }

  @override
  void onWindowUnmaximize() async {
    if (kDebugMode) {
      debugPrint('[WINDOW] onWindowUnmaximize triggered');
    }

    // If user unmaximizes, reapply kiosk mode (POS should stay at full size)
    try {
      if (Platform.isWindows && WindowService.isFullScreen()) {
        if (kDebugMode) {
          debugPrint('[WINDOW] reapplying kiosk mode after unmaximize');
        }
        await WindowService._reapplyKioskModeAfterRestore();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] onWindowUnmaximize error: $e');
      }
    }
  }
}
