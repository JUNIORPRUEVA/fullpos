import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/material.dart' show Size;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_colors.dart';

/// Servicio para controlar la ventana en aplicaciones Desktop
class WindowService {
  static bool _isInitialized = false;
  static bool _shownOnce = false;
  static bool _isFullScreen = false;
  static bool _postFrameRefreshScheduled = false;
  static bool _enforcerInstalled = false;
  static bool _windowsKioskApplied = false;
  static bool _windowsAlwaysOnTopSet = false;
  static int _systemDialogDepth = 0;
  static bool _restoreAlwaysOnTopAfterDialog = false;

  /// Notificador para reaccionar en UI cuando cambia fullscreen.
  static final ValueNotifier<bool> fullScreenListenable = ValueNotifier<bool>(
    false,
  );

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
        // Ignorar y usar primary display.
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

  static Future<void> _applyWindowsPosKioskMode({
    bool preferCurrentDisplay = true,
  }) async {
    // Objetivo: cubrir toda la pantalla (incluida barra de tareas) sin usar
    // fullscreen del sistema (que en algunos equipos deja pantalla negra).
    try {
      await windowManager.setFullScreen(false);
    } catch (_) {}

    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    } catch (_) {}

    try {
      await windowManager.setAsFrameless();
    } catch (_) {}

    if (!_windowsAlwaysOnTopSet) {
      try {
        await windowManager.setAlwaysOnTop(true);
        _windowsAlwaysOnTopSet = true;
      } catch (_) {}
    }

    try {
      final bounds = await _getWindowsKioskBounds(
        preferCurrentDisplay: preferCurrentDisplay,
      );

      Rect? currentBounds;
      try {
        currentBounds = await windowManager.getBounds();
      } catch (_) {}

      final alreadyCorrect =
          currentBounds != null &&
          (currentBounds.left - bounds.left).abs() < 0.5 &&
          (currentBounds.top - bounds.top).abs() < 0.5 &&
          (currentBounds.width - bounds.width).abs() < 0.5 &&
          (currentBounds.height - bounds.height).abs() < 0.5;

      if (!_windowsKioskApplied || !alreadyCorrect) {
        try {
          await windowManager.setBounds(bounds);
        } catch (_) {
          try {
            await windowManager.setResizable(true);
          } catch (_) {}

          try {
            await windowManager.setBounds(bounds);
          } catch (_) {}

          try {
            await windowManager.setResizable(false);
          } catch (_) {}
        }
      }
    } catch (_) {
      await windowManager.maximize();
    }

    await _refreshAfterWindowModeChange();
    _windowsKioskApplied = true;
  }

  /// Inicializar window_manager
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        debugPrint('[WINDOW] init start');
      }
      await windowManager.ensureInitialized();
      _installEnforcer();

      // En Windows, ocultar/mostrar puede verse como "minimizado" y causar flash.
      // Con el runner pintando el fondo de marca, preferimos mantener la ventana
      // visible y solo corregir estado (restore/maximize) de forma suave.
      if (Platform.isWindows) {
        try {
          final isMin = await windowManager.isMinimized();
          if (isMin) await windowManager.restore();
        } catch (_) {
          // Ignorar.
        }
      }

      // Cargar configuración guardada ANTES de mostrar la ventana, para que
      // arranque ya maximizada/fullscreen (evita que se vea minimizada al abrir).
      final prefs = await SharedPreferences.getInstance();
      // En un POS, por defecto debe abrir en pantalla completa/maximizado.
      // En Windows usamos "fullscreen estable" (titlebar oculta + maximizado).
      final savedFullscreen = Platform.isWindows
          ? true
          : (prefs.getBool('pos_fullscreen') ?? false);
      if (Platform.isWindows) {
        // Modo POS: siempre arrancar en pantalla completa/maximizado.
        await prefs.setBool('pos_fullscreen', true);
      }

      // Configuración inicial de la ventana
      const windowOptions = WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(1100, 650),
        center: true,
        // Debe coincidir con el Splash (evita flash blanco al arrancar).
        backgroundColor: AppColors.bgDark,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'FULLPOS',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        // Clave: NO mostrar mientras carga bootstrap. Ocultar antes de cualquier show.
        // Esto evita el "mini -> grande" y el parpadeo en Windows.
        try {
          await windowManager.hide();
          if (kDebugMode) {
            debugPrint('[WINDOW] hidden, applying options');
          }
        } catch (_) {
          // Ignorar: seguiremos aplicando opciones.
        }

        try {
          // Importante: aplicar estado (fullscreen/maximizado) ANTES de show().
          _isFullScreen = savedFullscreen;
          fullScreenListenable.value = savedFullscreen;

          if (Platform.isWindows) {
            // En Windows evitamos el fullscreen del sistema (a veces deja negro).
            if (savedFullscreen) {
              await _applyWindowsPosKioskMode(preferCurrentDisplay: false);
            } else {
              await windowManager.setTitleBarStyle(TitleBarStyle.normal);
              await windowManager.setResizable(false);
              await windowManager.maximize();
            }
          } else {
            await windowManager.setFullScreen(savedFullscreen);
            if (savedFullscreen) {
              await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
              await windowManager.setResizable(false);
            } else {
              await windowManager.setTitleBarStyle(TitleBarStyle.normal);
              await windowManager.setResizable(true);
              await windowManager.maximize();
            }
          }
        } catch (_) {
          // Si algo falla aquí y la ventana fue ocultada, garantizamos un fallback visible.
          try {
            await windowManager.setTitleBarStyle(TitleBarStyle.normal);
          } catch (_) {}
          try {
            await windowManager.setResizable(true);
          } catch (_) {}
          try {
            await windowManager.maximize();
          } catch (_) {}
          try {
            await windowManager.show();
          } catch (_) {}
        }

        // No hacer show/focus aquí: se evita flash. El post-frame aplica nudge.
      });

      // Marcar inicializado después de configurar la ventana.
      _isInitialized = true;
    } catch (_) {
      // Si init falla por cualquier razón, no dejamos la app "colgada" invisible.
      _isInitialized = false;
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      } catch (_) {}
      try {
        await windowManager.setResizable(true);
      } catch (_) {}
      try {
        await windowManager.maximize();
      } catch (_) {}
      try {
        await windowManager.show();
      } catch (_) {}
    }
  }

  /// Agenda un refresh post-frame para corregir casos donde el contenido de
  /// Flutter inicia con un tamaño incorrecto y solo se arregla al redimensionar.
  static void scheduleInitialLayoutFix() {
    if (_postFrameRefreshScheduled) return;
    _postFrameRefreshScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Este "nudge" puede causar parpadeo visible en algunas PCs.
      // Por defecto lo desactivamos en release para un arranque 100% estable.
      if (!kDebugMode) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _forceInitialResizeRefresh();
    });
  }

  static bool _showAfterFirstFrameScheduled = false;

  /// Mostrar la ventana SOLO una vez (Windows: después del bootstrap).
  static Future<void> showOnce({bool focus = true}) async {
    if (!_isInitialized) return;
    if (_shownOnce) return;
    _shownOnce = true;

    if (kDebugMode) {
      debugPrint('[WINDOW] show once');
    }

    try {
      if (Platform.isWindows) {
        try {
          final isMin = await windowManager.isMinimized();
          if (isMin) await windowManager.restore();
        } catch (_) {}
      }

      await windowManager.show();

      // Asegurar modo/tamaño final ya visible (sin toggle manual).
      if (Platform.isWindows) {
        await _ensureWindowsPosModeAfterShow();
      } else {
        await ensureMaximized(force: true);
      }

      if (focus) {
        await windowManager.focus();
      }
    } catch (_) {
      // Ignorar.
    }
  }

  /// Mostrar/enfocar la ventana una vez Flutter haya pintado el primer frame.
  static void scheduleShowAfterFirstFrame() {
    if (_showAfterFirstFrameScheduled) return;
    _showAfterFirstFrameScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isInitialized) return;
      try {
        await showOnce();
      } catch (_) {
        // Ignorar.
      }
    });
  }

  static void _installEnforcer() {
    if (_enforcerInstalled) return;
    _enforcerInstalled = true;
    try {
      windowManager.addListener(_PosWindowEnforcer.instance);
    } catch (_) {
      // Ignorar.
    }
  }

  static Future<void> ensureMaximized({bool force = false}) async {
    if (!_isInitialized) return;
    try {
      if (Platform.isWindows && _isFullScreen) {
        await _applyWindowsPosKioskMode(preferCurrentDisplay: true);
        return;
      }

      if (force || !await windowManager.isMaximized()) {
        // En Windows, maximizar puede fallar si la ventana estß bloqueada como no-resizable.
        if (Platform.isWindows) {
          try {
            await windowManager.setResizable(true);
          } catch (_) {}

          try {
            await windowManager.setFullScreen(false);
          } catch (_) {}

          try {
            await windowManager.setTitleBarStyle(
              _isFullScreen ? TitleBarStyle.hidden : TitleBarStyle.normal,
            );
          } catch (_) {}
        }

        await windowManager.maximize();

        if (Platform.isWindows) {
          try {
            await windowManager.setResizable(false);
          } catch (_) {}
        }
      }
      await _refreshAfterWindowModeChange();
    } catch (_) {
      // Ignorar.
    }
  }

  static Future<void> _ensureWindowsPosModeAfterShow() async {
    try {
      final isMin = await windowManager.isMinimized();
      if (isMin) await windowManager.restore();
    } catch (_) {}

    if (_isFullScreen) {
      await _applyWindowsPosKioskMode(preferCurrentDisplay: true);
      return;
    }

    // Reaplica el modo POS en Windows ya con la ventana visible.
    // Esto soluciona casos donde la app inicia "cortada" y solo se corrige
    // al hacer un toggle manual de fullscreen/maximize.
    try {
      await windowManager.setResizable(true);
    } catch (_) {}

    try {
      // Nunca usar fullscreen del sistema en Windows (puede dejar negro).
      await windowManager.setFullScreen(false);
    } catch (_) {}

    try {
      await windowManager.setTitleBarStyle(
        _isFullScreen ? TitleBarStyle.hidden : TitleBarStyle.normal,
      );
    } catch (_) {}

    await windowManager.maximize();

    await _refreshAfterWindowModeChange();
    await _forceInitialResizeRefresh();

    try {
      await windowManager.setResizable(false);
    } catch (_) {}
  }

  static Future<void> _forceInitialResizeRefresh() async {
    try {
      // Un pequeño delta (1px) es suficiente para forzar el refresh sin impacto.
      final size = await windowManager.getSize();
      if (size.width <= 0 || size.height <= 0) return;
      await windowManager.setSize(Size(size.width + 1, size.height));
      await windowManager.setSize(size);
    } catch (_) {
      // No bloquear la app si el plugin falla.
    }
  }

  static Future<void> applyBranding({
    required String businessName,
    String? logoPath,
  }) async {
    if (!_isInitialized) return;

    // CRÍTICO (marca FULLPOS): el branding de ventana NO debe depender de
    // configuración del cliente. El icono del sistema debe venir fijo desde
    // los recursos nativos (exe/launcher) generados por build.
    try {
      await windowManager.setTitle('FULLPOS');
    } catch (_) {
      // Ignorar.
    }
  }

  /// Activar/desactivar pantalla completa
  static Future<void> setFullScreen(
    bool value, {
    bool savePreference = true,
  }) async {
    if (!_isInitialized) return;

    // En Windows el POS debe permanecer siempre en modo pantalla completa/"kiosk"
    // para evitar que reaparezca la barra superior y se pierda espacio.
    final effectiveValue = Platform.isWindows ? true : value;

    _isFullScreen = effectiveValue;
    fullScreenListenable.value = effectiveValue;

    // En Windows, el fullscreen real a veces deja el contenido en negro.
    // Usamos un modo POS estable: ocultar barra de título + maximizar.
    if (Platform.isWindows) {
      if (effectiveValue) {
        await _applyWindowsPosKioskMode(preferCurrentDisplay: true);
      }

      await _refreshAfterWindowModeChange();
    } else {
      await windowManager.setFullScreen(effectiveValue);

      if (effectiveValue) {
        // En fullscreen, ocultar título pero mantener en taskbar
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await windowManager.setResizable(false);
      } else {
        // Normal: mostrar título y permitir redimensionar
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setResizable(true);
        // Volver a un estado cómodo (normalmente el POS se usa maximizado)
        await windowManager.maximize();
      }
    }

    // Guardar preferencia
    if (savePreference) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pos_fullscreen', effectiveValue);
    }
  }

  /// Alternar pantalla completa
  static Future<void> toggleFullScreen() async {
    if (Platform.isWindows) {
      // En Windows el POS permanece siempre en modo pantalla completa.
      await setFullScreen(true);
      return;
    }

    await setFullScreen(!_isFullScreen);
  }

  /// Obtener estado de pantalla completa
  static bool isFullScreen() => _isFullScreen;

  /// En Windows, el modo POS usa `alwaysOnTop` para evitar que otras ventanas
  /// tapen el sistema. Eso puede provocar que los diálogos del sistema (como
  /// el selector de archivos) se abran "detrás" de la app.
  ///
  /// Este helper desactiva temporalmente `alwaysOnTop` mientras se ejecuta una
  /// operación que abre un diálogo del sistema y luego restaura el estado.
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
        } catch (_) {}
        // Dar tiempo a Windows a actualizar el z-order antes de abrir el diálogo.
        await Future<void>.delayed(const Duration(milliseconds: 75));
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

  /// En Windows POS, la app puede estar en modo "always on top". Para abrir
  /// una aplicación externa (por ejemplo WhatsApp Web/Desktop o el navegador),
  /// conviene desactivar temporalmente el `alwaysOnTop` para que el usuario
  /// pueda interactuar con la ventana externa.
  ///
  /// A diferencia de [runWithSystemDialog], este helper NO fuerza focus de
  /// vuelta al POS al final.
  static Future<T> runWithExternalApplication<T>(
    Future<T> Function() action, {
    Duration restoreDelay = const Duration(milliseconds: 900),
  }) async {
    if (!Platform.isWindows || !_isInitialized) {
      return action();
    }

    // Solo aplica si estamos en modo POS (fullscreen lógico).
    final shouldRestore = _isFullScreen;

    if (shouldRestore) {
      try {
        await windowManager.setAlwaysOnTop(false);
      } catch (_) {}
      // Dar tiempo a Windows a actualizar el z-order.
      await Future<void>.delayed(const Duration(milliseconds: 75));
    }

    try {
      return await action();
    } finally {
      if (shouldRestore) {
        // Restaurar luego de un breve delay. Si el POS fue minimizado, esto
        // no interfiere con la app externa; al volver, recupera el comportamiento.
        Future<void>.delayed(restoreDelay, () async {
          try {
            await windowManager.setAlwaysOnTop(true);
          } catch (_) {}
        });
      }
    }
  }

  /// Establecer ventana siempre visible (opcional)
  static Future<void> setAlwaysOnTop(bool value) async {
    if (!_isInitialized) return;
    await windowManager.setAlwaysOnTop(value);
  }

  /// Prevenir cierre de ventana (opcional)
  static Future<void> setPreventClose(bool value) async {
    if (!_isInitialized) return;
    await windowManager.setPreventClose(value);
  }

  /// Mostrar/ocultar ventana
  static Future<void> show() async {
    if (!_isInitialized) return;
    await windowManager.show();
  }

  /// Minimizar ventana
  static Future<void> minimize() async {
    if (!_isInitialized) return;
    await windowManager.minimize();
  }

  /// Maximizar ventana
  static Future<void> maximize() async {
    if (!_isInitialized) return;
    await windowManager.maximize();
  }

  /// Saber si la ventana está maximizada
  static Future<bool> isMaximized() async {
    if (!_isInitialized) return false;
    try {
      return await windowManager.isMaximized();
    } catch (_) {
      return false;
    }
  }

  /// Alternar maximizado/restaurar
  static Future<void> toggleMaximize() async {
    if (!_isInitialized) return;
    final maximized = await isMaximized();
    if (maximized) {
      await windowManager.restore();
    } else {
      await windowManager.maximize();
    }

    await _refreshAfterWindowModeChange();
  }

  static Future<void> _refreshAfterWindowModeChange() async {
    // Forzar un refresh sin “nudge” visible: setBounds con los mismos bounds.
    try {
      final bounds = await windowManager.getBounds();
      await windowManager.setBounds(bounds);
    } catch (_) {
      // Fallback: nada.
    }
  }

  /// Restaurar tamaño ventana
  static Future<void> restore() async {
    if (!_isInitialized) return;
    await windowManager.restore();
  }

  /// Cerrar aplicación
  static Future<void> close() async {
    if (!_isInitialized) return;
    await windowManager.close();
  }
}

class _PosWindowEnforcer with WindowListener {
  _PosWindowEnforcer._();

  static final _PosWindowEnforcer instance = _PosWindowEnforcer._();

  bool _running = false;

  Future<void> _enforceMaximized() async {
    if (_running) return;
    _running = true;
    try {
      await WindowService.ensureMaximized(force: true);
    } finally {
      _running = false;
    }
  }

  @override
  void onWindowRestore() {
    _enforceMaximized();
  }

  @override
  void onWindowUnmaximize() {
    _enforceMaximized();
  }
}
