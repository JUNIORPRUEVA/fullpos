import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../errors/error_handler.dart';
import '../errors/error_mapper.dart';
import '../ui/app_error_page.dart';
import 'app_logger.dart';

class RenderDiagnostics {
  RenderDiagnostics._();

  static final RenderDiagnostics instance = RenderDiagnostics._();

  final DebugAppLogger _logger = DebugAppLogger.instance;

  DateTime? _runAppAt;
  DateTime? _firstFrameAt;
  bool _handlersInstalled = false;

  Duration? get timeToFirstFrame => (_runAppAt != null && _firstFrameAt != null)
      ? _firstFrameAt!.difference(_runAppAt!)
      : null;

  Future<void> ensureInitialized() async {
    await _logger.init();
    _runAppAt ??= DateTime.now();
    unawaited(
      _logger.info(
        'render_diagnostics_initialized',
        data: {
          'platform': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
        },
      ),
    );
  }

  void installGlobalErrorHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    FlutterError.onError = (details) {
      final message = details.exceptionAsString();

      // Windows/Flutter (debug) can occasionally throw this assertion for AltRight/AltGr
      // due to inconsistent modifier flags coming from the OS/embedder.
      // It is non-fatal in release, but in debug it can spam logs and appear as a freeze.
      // We treat it as a recoverable event and clear pressed keys defensively.
      if (message.contains(
        'Attempted to send a key down event when no keys are in keysPressed',
      )) {
        unawaited(
          _logger.warn(
            'flutter_keyboard_state_desync',
            module: 'flutter',
            data: {
              'exception': message,
              if (details.stack != null) 'stackTrace': '${details.stack}',
            },
          ),
        );
        return;
      }

      if (kDebugMode) {
        FlutterError.presentError(details);
      }
      unawaited(
        _logger.error(
          'flutter_error',
          module: 'flutter',
          data: {'exception': message},
          stackTrace: details.stack,
        ),
      );
      ErrorHandler.instance.reportFlutterError(details, module: 'flutter');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        _logger.error(
          'platform_error',
          module: 'platform',
          data: {'exception': '$error'},
          stackTrace: stack,
        ),
      );
      return ErrorHandler.instance.reportPlatformError(
        error,
        stack,
        module: 'platform',
      );
    };

    ErrorWidget.builder = (details) {
      final ex = ErrorMapper.map(details, details.stack, 'error_widget');
      unawaited(
        _logger.error(
          'error_widget',
          module: 'render',
          data: {'exception': details.exceptionAsString()},
          stackTrace: details.stack,
        ),
      );
      return Material(
        color: Colors.white,
        child: SafeArea(child: AppErrorPage(exception: ex)),
      );
    };
  }

  void markRunAppStart() {
    _runAppAt = DateTime.now();
    unawaited(_logger.info('runApp_called'));
  }

  void markFirstFramePainted({String? source}) {
    if (_firstFrameAt != null) return;
    _firstFrameAt = DateTime.now();
    final ttffMs = _runAppAt != null
        ? _firstFrameAt!.difference(_runAppAt!).inMilliseconds
        : null;
    unawaited(
      _logger.info(
        'first_frame_painted',
        data: {'source': source, if (ttffMs != null) 'ttff_ms': ttffMs},
      ),
    );
  }

  Future<void> logLifecycle(String state) {
    return _logger.info('lifecycle', data: {'state': state});
  }

  Future<void> logOverlay(String event, {Map<String, Object?>? data}) {
    return _logger.info(
      'overlay_event',
      data: {'event': event, if (data != null) ...data},
    );
  }

  Future<void> logBlackScreenDetected({
    required int attempt,
    required String reason,
    bool? hasSurface,
  }) {
    return _logger.warn(
      'BLACK_SCREEN_DETECTED',
      data: {
        'attempt': attempt,
        'reason': reason,
        if (hasSurface != null) 'hasSurface': hasSurface,
      },
    );
  }

  Future<void> logRecoveryAction(String action, {int? attempt}) {
    return _logger.info(
      'render_recovery',
      data: {'action': action, if (attempt != null) 'attempt': attempt},
    );
  }

  Future<void> logSafeMode(bool enabled, {int? attempts}) {
    return _logger.warn(
      enabled ? 'safe_mode_enabled' : 'safe_mode_exit',
      data: {if (attempts != null) 'attempts': attempts},
    );
  }

  RenderWatchdog createWatchdog({
    Duration timeout = const Duration(seconds: 3),
  }) {
    return RenderWatchdog(timeout: timeout, logger: _logger);
  }

  @visibleForTesting
  void resetTimings() {
    _runAppAt = null;
    _firstFrameAt = null;
  }
}

class RenderWatchdog {
  RenderWatchdog({required Duration timeout, required DebugAppLogger logger})
    : _timeout = timeout,
      _logger = logger;

  final DebugAppLogger _logger;
  Duration _timeout;
  Timer? _timer;

  void start(VoidCallback onTimeout) {
    _timer?.cancel();
    _timer = Timer(_timeout, () {
      _logger.warn(
        'watchdog_timeout',
        data: {'timeout_ms': _timeout.inMilliseconds},
      );
      onTimeout();
    });
  }

  void restart(VoidCallback onTimeout, {Duration? timeout}) {
    if (timeout != null) _timeout = timeout;
    start(onTimeout);
  }

  void markFramePainted() {
    _timer?.cancel();
    _logger.info('watchdog_cleared');
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
