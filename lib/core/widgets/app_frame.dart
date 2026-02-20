import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../debug/render_diagnostics.dart';
import '../theme/app_gradient_theme.dart';

class AppFrame extends ConsumerStatefulWidget {
  const AppFrame({
    super.key,
    required this.child,
    this.watchdogTimeout = const Duration(seconds: 3),
  });

  final Widget child;
  final Duration watchdogTimeout;

  @override
  ConsumerState<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends ConsumerState<AppFrame>
    with WidgetsBindingObserver, WindowListener {
  late final RenderDiagnostics _diagnostics;
  late final RenderWatchdog _watchdog;
  bool _firstFrameSeen = false;
  bool _repaintToggle = false;
  int _attempts = 0;
  DateTime? _lastResumeRecoveryAt;
  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _diagnostics = RenderDiagnostics.instance;
    unawaited(_diagnostics.ensureInitialized());
    _watchdog = _diagnostics.createWatchdog(timeout: widget.watchdogTimeout);
    WidgetsBinding.instance.addObserver(this);
    if (_isDesktop) {
      try {
        windowManager.addListener(this);
      } catch (_) {}
    }
    _startWatchdog();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFramePainted());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isDesktop) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    }
    _watchdog.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_diagnostics.logLifecycle(state.name));
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverAfterResume());
    }
  }

  @override
  void onWindowRestore() {
    unawaited(_recoverAfterResume());
  }

  @override
  void onWindowFocus() {
    unawaited(_recoverAfterResume());
  }

  @override
  void onWindowResized() {
    unawaited(_recoverAfterResume());
  }

  Future<void> _recoverAfterResume() async {
    final now = DateTime.now();
    final last = _lastResumeRecoveryAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastResumeRecoveryAt = now;

    _startWatchdog(timeout: const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _repaintToggle = !_repaintToggle;
      });
    }

    if (_isDesktop) {
      try {
        final isMin = await windowManager.isMinimized();
        if (isMin) {
          await windowManager.restore();
        }
        await windowManager.focus();
      } catch (_) {}
    }

    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (!mounted) return;
      _onFirstFramePainted();
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((nextTimeStamp) {
        if (!mounted) return;
        _onFirstFramePainted();
      });
    });
  }

  void _startWatchdog({Duration? timeout}) {
    _watchdog.restart(
      _handleWatchdogTimeout,
      timeout: timeout ?? widget.watchdogTimeout,
    );
  }

  void _onFirstFramePainted() {
    if (!_firstFrameSeen) {
      _firstFrameSeen = true;
      _diagnostics.markFirstFramePainted(source: 'AppFrame');
    }
    _attempts = 0;
    _watchdog.markFramePainted();
  }

  bool _hasSurface() {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.hasSize &&
          renderObject.size.longestSide > 0 &&
          renderObject.attached;
    }
    return renderObject?.attached ?? false;
  }

  void _handleWatchdogTimeout() {
    final hasSurface = _hasSurface();
    _attempts += 1;
    unawaited(
      _diagnostics.logBlackScreenDetected(
        attempt: _attempts,
        reason: _firstFrameSeen ? 'surface_not_ready' : 'first_frame_timeout',
        hasSurface: hasSurface,
      ),
    );

    _diagnostics.logRecoveryAction('repaint_toggle', attempt: _attempts);
    setState(() {
      _repaintToggle = !_repaintToggle;
    });

    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFramePainted());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasSurface) {
        _onFirstFramePainted();
        return;
      }

      if (_attempts >= 2) {
        unawaited(_forceWindowRefresh());
      }

      _startWatchdog(timeout: const Duration(seconds: 2));
    });
  }

  Future<void> _forceWindowRefresh() async {
    if (!_isDesktop) return;
    try {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await windowManager.show();
      }
      final isMin = await windowManager.isMinimized();
      if (isMin) {
        await windowManager.restore();
      }
      await windowManager.focus();
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onFirstFramePainted(),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final repaintable = RepaintBoundary(
      child: KeyedSubtree(
        key: ValueKey<bool>(_repaintToggle),
        child: widget.child,
      ),
    );

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradientTheme = theme.extension<AppGradientTheme>();
    final fallbackGradient = LinearGradient(
      colors: [scheme.surface, scheme.primaryContainer],
      stops: const [0.0, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final backgroundGradient =
        gradientTheme?.backgroundGradient ?? fallbackGradient;

    final framedChild = Theme(
      data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
      child: repaintable,
    );
    return DecoratedBox(
      decoration: BoxDecoration(gradient: backgroundGradient),
      child: Stack(children: [Positioned.fill(child: framedChild)]),
    );
  }
}
