import 'dart:async';

import 'package:flutter/material.dart';

import '../debug/render_diagnostics.dart';
import '../theme/color_utils.dart';
import '../theme/app_gradient_theme.dart';

class AppFrame extends StatefulWidget {
  const AppFrame({
    super.key,
    required this.child,
    this.watchdogTimeout = const Duration(seconds: 3),
  });

  final Widget child;
  final Duration watchdogTimeout;

  @override
  State<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends State<AppFrame> with WidgetsBindingObserver {
  late final RenderDiagnostics _diagnostics;
  late final RenderWatchdog _watchdog;
  bool _firstFrameSeen = false;
  bool _repaintToggle = false;
  bool _showRecoveryBanner = false;
  bool _safeMode = false;
  int _attempts = 0;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _diagnostics = RenderDiagnostics.instance;
    unawaited(_diagnostics.ensureInitialized());
    _watchdog = _diagnostics.createWatchdog(
      timeout: widget.watchdogTimeout,
    );
    WidgetsBinding.instance.addObserver(this);
    _startWatchdog();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFramePainted());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchdog.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_diagnostics.logLifecycle(state.name));
  }

  void _startWatchdog({Duration? timeout}) {
    _watchdog.restart(
      _handleWatchdogTimeout,
      timeout: timeout ?? widget.watchdogTimeout,
    );
  }

  void _onFirstFramePainted() {
    if (_firstFrameSeen) return;
    _firstFrameSeen = true;
    _diagnostics.markFirstFramePainted(source: 'AppFrame');
    _watchdog.markFramePainted();
    _hideBannerSoon();
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
      _showRecoveryBanner = true;
      _repaintToggle = !_repaintToggle;
    });

    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFramePainted());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_firstFrameSeen || hasSurface) {
        _hideBannerSoon();
        return;
      }

      if (_attempts >= 2) {
        _enterSafeMode();
        return;
      }

      _startWatchdog(timeout: const Duration(seconds: 2));
    });
  }

  void _enterSafeMode() {
    unawaited(_diagnostics.logSafeMode(true, attempts: _attempts));
    setState(() {
      _safeMode = true;
      _showRecoveryBanner = true;
    });
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || !_safeMode) return;
      _exitSafeModeAndRetry();
    });
  }

  void _exitSafeModeAndRetry() {
    unawaited(_diagnostics.logSafeMode(false, attempts: _attempts));
    setState(() {
      _safeMode = false;
      _attempts = 0;
      _repaintToggle = !_repaintToggle;
      _showRecoveryBanner = false;
    });
    _startWatchdog();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFramePainted());
  }

  void _hideBannerSoon() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showRecoveryBanner = false;
      });
    });
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
    return DecoratedBox(
      decoration: BoxDecoration(gradient: backgroundGradient),
      child: Stack(
        children: [
          Positioned.fill(child: repaintable),
          if (_showRecoveryBanner)
            const _RecoveryBanner(message: 'Reiniciando vista...'),
          if (_safeMode)
            Positioned.fill(
              child: _SafeModeScreen(onRetry: _exitSafeModeAndRetry),
            ),
        ],
      ),
    );
  }
}

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bannerBg = scheme.surface.withOpacity(0.9);
    final bannerFg = ColorUtils.ensureReadableColor(
      scheme.onSurface,
      bannerBg,
    );
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        color: bannerBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(bannerFg),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                message,
                style: TextStyle(
                  color: bannerFg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafeModeScreen extends StatelessWidget {
  const _SafeModeScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    size: 36,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reiniciando vista segura',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Si ves esta pantalla, el renderer no entregó el primer frame a tiempo. '
                    'Reintentaremos con un repintado seguro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.replay),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
