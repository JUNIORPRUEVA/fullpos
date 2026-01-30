import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../db/app_db.dart';
import '../errors/error_handler.dart';
import '../session/session_manager.dart';

/// Watchdog ligero para detectar "loaders" que tardan demasiado.
///
/// - No cancela operaciones: solo imprime diagnósticos si exceden el umbral.
/// - Está pensado para evitar que un spinner quede "en silencio" indefinidamente.
class LoaderWatchdog {
  LoaderWatchdog._({
    required this.stage,
    required Duration timeout,
    this.origin,
    bool enabled = true,
  }) : _timeout = timeout {
    _startedAt = DateTime.now();
    _lastStep = stage;
    _enabled = enabled;
    if (_enabled) {
      _timer = Timer(_timeout, _onTimeout);
    }
  }

  final String stage;
  final Duration _timeout;
  final StackTrace? origin;

  late final bool _enabled;

  late final DateTime _startedAt;
  late String _lastStep;
  Timer? _timer;
  bool _fired = false;

  static final Map<String, _StageStartWindow> _startWindows =
      <String, _StageStartWindow>{};
  static final Map<String, DateTime> _disabledUntil = <String, DateTime>{};

  static LoaderWatchdog start({
    required String stage,
    Duration timeout = const Duration(seconds: 8),
    bool captureOrigin = kDebugMode,
  }) {
    final now = DateTime.now();

    // Circuit breaker: if a stage is being started in a tight loop, stop
    // creating timers for a short cooldown window. This prevents watchdog
    // storms from amplifying performance issues.
    final disabled = _disabledUntil[stage];
    if (disabled != null && now.isBefore(disabled)) {
      return LoaderWatchdog._(
        stage: stage,
        timeout: timeout,
        origin: captureOrigin ? StackTrace.current : null,
        enabled: false,
      );
    }

    final window = _startWindows.putIfAbsent(
      stage,
      () => _StageStartWindow(startedAt: now, count: 0),
    );

    const windowSize = Duration(seconds: 5);
    if (now.difference(window.startedAt) > windowSize) {
      window.startedAt = now;
      window.count = 0;
    }

    window.count++;

    // Very high threshold: this should never trigger during normal UX.
    // If it does, it indicates a true infinite retry/rebuild loop.
    if (window.count >= 30) {
      _disabledUntil[stage] = now.add(const Duration(seconds: 30));
      debugPrint(
        '[WATCHDOG] circuit_breaker tripped stage="$stage" '
        'starts_in_${windowSize.inSeconds}s=${window.count}',
      );
      return LoaderWatchdog._(
        stage: stage,
        timeout: timeout,
        origin: captureOrigin ? StackTrace.current : null,
        enabled: false,
      );
    }

    return LoaderWatchdog._(
      stage: stage,
      timeout: timeout,
      origin: captureOrigin ? StackTrace.current : null,
    );
  }

  void step(String step) {
    _lastStep = step;
  }

  void dispose() {
    if (!_enabled) return;
    _timer?.cancel();
    _timer = null;
  }

  void _onTimeout() {
    if (!_enabled) return;
    if (_fired) return;
    _fired = true;
    unawaited(_logDiagnostics());
  }

  Future<void> _logDiagnostics() async {
    if (!_enabled) return;
    final elapsedMs = DateTime.now().difference(_startedAt).inMilliseconds;

    String? route;
    try {
      final ctx = ErrorHandler.navigatorKey.currentContext;
      if (ctx != null) {
        try {
          route = GoRouter.of(ctx).state.uri.toString();
        } catch (_) {
          route = ModalRoute.of(ctx)?.settings.name;
        }
      }
    } catch (_) {}

    String? role;
    try {
      role = await SessionManager.role();
    } catch (_) {}

    final db = AppDb.diagnosticsSnapshot();

    String? originFrame;
    final origin = this.origin;
    if (origin != null) {
      originFrame = _firstRelevantFrame(origin);
    }

    debugPrint(
      '[WATCHDOG] timeout>${_timeout.inSeconds}s '
      'stage="$stage" step="$_lastStep" elapsed_ms=$elapsedMs '
      'route="${route ?? 'unknown'}" role="${role ?? 'unknown'}" '
      'db=$db'
      '${originFrame != null ? ' origin="$originFrame"' : ''}',
    );
  }

  static String? _firstRelevantFrame(StackTrace trace) {
    final lines = trace.toString().split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Prefer "package:" frames since they are stable across machines.
      if (trimmed.contains('package:fullpos/')) return trimmed;
      // Fallback to file paths when running from source.
      if (trimmed.contains('/lib/') || trimmed.contains('\\lib\\')) {
        return trimmed;
      }
    }
    return null;
  }
}

class _StageStartWindow {
  _StageStartWindow({required this.startedAt, required this.count});

  DateTime startedAt;
  int count;
}
