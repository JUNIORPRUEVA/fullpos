import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:screen_retriever/screen_retriever.dart';
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
  static int _systemDialogDepth = 0;
  static bool _restoreAlwaysOnTopAfterDialog = false;
  static bool _enforcerInstalled = false;

  /// Notifier for UI to react when fullscreen state changes
  static final ValueNotifier<bool> fullScreenListenable = ValueNotifier<bool>(
    false,
  );

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
        if (Platform.isWindows) {
          _isFullScreen = true;
          fullScreenListenable.value = true;
          await prefs.setBool('pos_fullscreen', true);
        } else {
          _isFullScreen = prefs.getBool('pos_fullscreen') ?? false;
          fullScreenListenable.value = _isFullScreen;
        }
      } catch (_) {
        _isFullScreen = Platform.isWindows;
        fullScreenListenable.value = _isFullScreen;
      }

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WINDOW] init error: $e');
      }
    }
  }

  static Future<Rect> _getWindowsKioskBounds({
    bool preferCurrentDisplay = true,
  }) async {
    Display display = await screenRetriever.getPrimaryDisplay();

    if (preferCurrentDisplay) {
      try {
        final windowBounds = await windowManager.getBounds();
        final windowCenter = Offset(
          windowBounds.left + (windowBounds.width / 2),
          windowBounds.top + (windowBounds.height / 2),
        );

        final displays = await screenRetriever.getAllDisplays();
        for (final d in displays) {
          final origin = d.visiblePosition ?? Offset.zero;
          final rect = Rect.fromLTWH(
            origin.dx,
            origin.dy,
            d.size.width,
            d.size.height,
          );
          if (rect.contains(windowCenter)) {
            display = d;
            break;
          }
        }
      } catch (_) {
        // Use primary display on error
      }
    }

    final origin = display.visiblePosition ?? Offset.zero;
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      display.size.width,
      display.size.height,
    );
  }

  /// Apply Windows POS kiosk mode: full screen without system fullscreen.
  /// Called while window is hidden during startup.
  /// MUST NOT be called frequently - only at startup and after minimize/restore.
  static Future<void> _applyWindowsPosKioskMode({
    bool preferCurrentDisplay = true,
  }) async {
    if (kDebugMode) {
      debugPrint('[WINDOW] applying kiosk mode, preferCurrentDisplay=$preferCurrentDisplay');
    }

    // Step 1: Disable system fullscreen (can leave screen black on some PCs)
    try {
      await windowManager.setFullScreen(false);
    } catch (e) {
      if (kDebugMode) debugPrint('[WINDOW] setFullScreen(false) failed: $e');
    }

    // Step 2: Hide title bar for full POS mode
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    } catch (e) {
      if (kDebugMode) debugPrint('[WINDOW] setTitleBarStyle failed: $e');
    }

    // Step 3: Make frameless for maximum usable space
    try {
      await windowManager.setAsFrameless();
    } catch (e) {
      if (kDebugMode) debugPrint('[WINDOW] setAsFrameless failed: $e');
    }

    // Step 4: Non-resizable to prevent accidental resizing and hit-test issues
    try {
      await windowManager.setResizable(false);
    } catch (e) {
      if (kDebugMode) debugPrint('[WINDOW] setResizable(false) failed: $e');
    }

    // Step 5: Always on top in POS mode (prevents other windows from covering)
    try {
      await windowManager.setAlwaysOnTop(true);
    } catch (e) {
      if (kDebugMode) debugPrint('[WINDOW] setAlwaysOnTop failed: $e');
    }

    // Step 6: Set bounds to cover entire display
    try {
      final bounds = await _getWindowsKioskBounds(
        preferCurrentDisplay: preferCurrentDisplay,
      );

      if (kDebugMode) {
        debugPrint('[WINDOW] kiosk bounds: ${bounds.left},${bounds.top} ${bounds.width}x${bounds.height}');
      }

      // Try to set bounds directly
      try {
        await windowManager.setBounds(bounds);
        if (kDebugMode) debugPrint('[WINDOW] setBounds succeeded');
      } catch (e) {
        if (kDebugMode) debugPrint('[WINDOW] setBounds failed, trying with temp resizable: $e');
        // setBounds may need temp resizable on some systems
        try {
          await windowManager.setResizable(true);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await windowManager.setBounds(bounds);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await windowManager.setResizable(false);
          if (kDebugMode) debugPrint('[WINDOW] setBounds succeeded with temp resizable');
        } catch (e2) {
          if (kDebugMode) debugPrint('[WINDOW] setBounds with temp resizable also failed: $e2, trying maximize');
          // Fallback to maximize if setBounds fails completely
          try {
            await windowManager.maximize();
            if (kDebugMode) debugPrint('[WINDOW] maximize fallback succeeded');
          } catch (e3) {
            if (kDebugMode) debugPrint('[WINDOW] maximize also failed: $e3');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WINDOW] _getWindowsKioskBounds failed: $e');
      // Final fallback
      try {
        await windowManager.maximize();
      } catch (_) {}
    }

    if (kDebugMode) {
      debugPrint('[WINDOW] kiosk mode application complete');
    }
  }

  /// Apply POS kiosk mode while window is hidden (startup only).
  /// This is the ONLY place kiosk mode is applied at startup.
  static Future<void> applyWindowsPosKioskModeForStartup({
    bool preferCurrentDisplay = false,
  }) async {
    if (!Platform.isWindows) return;
    await _applyWindowsPosKioskMode(preferCurrentDisplay: preferCurrentDisplay);
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
  static Future<void> setFullScreen(bool value, {bool savePreference = true}) async {
    if (!_isInitialized) return;

    // On Windows POS, always maintain fullscreen/kiosk mode
    final effectiveValue = Platform.isWindows ? true : value;
    _isFullScreen = effectiveValue;
    fullScreenListenable.value = effectiveValue;

    if (Platform.isWindows) {
      if (effectiveValue) {
        // Apply kiosk mode on Windows
        await _applyWindowsPosKioskMode(preferCurrentDisplay: true);
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
    if (Platform.isWindows) {
      // Windows POS always stays in fullscreen
      await setFullScreen(true);
      return;
    }
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
/// Only restores visibility - does NOT spam maximize.
class _PosWindowEnforcer with WindowListener {
  _PosWindowEnforcer._();

  static final _PosWindowEnforcer instance = _PosWindowEnforcer._();

  bool _restoreInProgress = false;

  @override
  void onWindowRestore() async {
    if (_restoreInProgress) return;
    _restoreInProgress = true;
    try {
      // Ensure window is visible and maximized after restore
      final isMaxed = await WindowService.isMaximized();
      if (!isMaxed) {
        await WindowService.maximize();
      }
    } catch (_) {
    } finally {
      _restoreInProgress = false;
    }
  }

  @override
  void onWindowUnmaximize() async {
    // If user unmaximizes, re-maximize once (POS should stay at full size)
    try {
      await WindowService.maximize();
    } catch (_) {}
  }
}

