import 'dart:async';

import 'package:flutter/material.dart';

import '../logging/app_logger.dart';
import '../ui/app_error_dialog.dart';
import '../ui/app_error_page.dart';
import 'app_exception.dart';
import 'error_mapper.dart';

class ErrorHandler {
  ErrorHandler._();

  static final ErrorHandler instance = ErrorHandler._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  bool _presenting = false;
  DateTime? _lastShownAt;
  String? _lastSignature;

  BuildContext? get _fallbackContext =>
      navigatorKey.currentState?.overlay?.context ??
      navigatorKey.currentContext;

  static bool isTransientFlutterLayoutError(String message) {
    return message.contains('!_debugDuringDeviceUpdate') ||
        message.contains('mouse_tracker.dart') ||
        message.contains('No Overlay widget found') ||
        message.contains('RawTooltip widgets require an Overlay widget') ||
        message.contains('debugCheckHasOverlay') ||
        message.contains('referenceBox.attached') ||
        message.contains('InkFeature._paint') ||
        message.contains('!_skipMarkNeedsLayout') ||
        message.contains('_RenderTheater._addDeferredChild') ||
        message.contains('_OverlayPortalElement') ||
        message.contains('_elements.contains(element)') ||
        message.contains('InactiveElements.remove') ||
        (message.contains('package:flutter/src/widgets/framework.dart') &&
            message.contains('Failed assertion') &&
            message.contains('elements.contains')) ||
        message.contains(
          "Looking up a deactivated widget's ancestor is unsafe",
        );
  }

  static bool _isNonBlockingFlutterFrameworkAssertion(
    String message,
    StackTrace stackTrace,
  ) {
    if (!message.contains('Failed assertion') &&
        !message.contains('_AssertionError')) {
      return false;
    }

    final stack = stackTrace.toString();
    return stack.contains('package:flutter/src/widgets/overlay.dart') ||
        stack.contains('package:flutter/src/material/material.dart') ||
        stack.contains('package:flutter/src/widgets/framework.dart') ||
        stack.contains('package:flutter/src/rendering/object.dart');
  }

  bool _shouldSuppressPresentation(AppException ex) {
    // El usuario pidió no mostrar notificaciones de conectividad.
    if (ex.type == AppErrorType.network || ex.type == AppErrorType.timeout) {
      return true;
    }

    final dev = ex.messageDev;
    // Errores típicos de debug/noise que no deben mostrarse al usuario.
    if (dev.contains('Zone mismatch')) return true;
    if (dev.contains('A RenderFlex overflowed')) return true;
    if (isTransientFlutterLayoutError(dev)) {
      return true;
    }
    // Puede ocurrir si intentamos mostrar UI en medio de una transición.
    if (dev.contains('!navigator._debugLocked')) return true;
    if (dev.contains('A KeyDownEvent is dispatched')) return true;
    return false;
  }

  Future<AppException> handle(
    Object error, {
    StackTrace? stackTrace,
    BuildContext? context,
    VoidCallback? onRetry,
    String? module,
  }) async {
    final ex = ErrorMapper.map(error, stackTrace, module);
    unawaited(AppLogger.instance.logError(ex, module: module));

    final ctx = context ?? _fallbackContext;
    if (ctx == null) return ex;

    if (_shouldSuppressPresentation(ex)) {
      return ex;
    }

    final signature = '${ex.type}|${ex.code}|${ex.messageUser}';
    final now = DateTime.now();
    final recentlyShown =
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 2);

    if (_presenting && recentlyShown && _lastSignature == signature) {
      return ex;
    }

    _presenting = true;
    _lastShownAt = now;
    _lastSignature = signature;

    try {
      // Evita asserts de navegación (ej. Navigator bloqueado) y mostrar UI
      // dentro del mismo frame/transición.
      await WidgetsBinding.instance.endOfFrame;
      final safeContext = _fallbackContext ?? ctx;
      await AppErrorDialog.show(safeContext, exception: ex, onRetry: onRetry);
    } catch (_) {
      // Fallback: si mostrar dialog falla, empuja una página de error.
      try {
        final nav = navigatorKey.currentState;
        if (nav == null) return ex;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!nav.mounted) return;
          try {
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => AppErrorPage(exception: ex, onRetry: onRetry),
              ),
            );
          } catch (_) {}
        });
      } catch (_) {}
    } finally {
      _presenting = false;
    }

    return ex;
  }

  Future<T?> runSafe<T>(
    Future<T> Function() action, {
    BuildContext? context,
    VoidCallback? onRetry,
    String? module,
  }) async {
    try {
      return await action();
    } catch (e, st) {
      await handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: onRetry,
        module: module,
      );
      return null;
    }
  }

  T? guard<T>(
    T Function() action, {
    BuildContext? context,
    VoidCallback? onRetry,
    String? module,
  }) {
    try {
      return action();
    } catch (e, st) {
      unawaited(
        handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: onRetry,
          module: module,
        ),
      );
      return null;
    }
  }

  void reportFlutterError(FlutterErrorDetails details, {String? module}) {
    final error = details.exception;
    final st = details.stack ?? StackTrace.current;
    // Overflows y otros asserts de debug no deben interrumpir la UX.
    final msg = details.exceptionAsString();
    if (msg.contains('A KeyDownEvent is dispatched')) {
      return;
    }
    if (msg.contains('A RenderFlex overflowed')) {
      final ex = ErrorMapper.map(details, details.stack, module ?? 'flutter');
      unawaited(AppLogger.instance.logError(ex, module: module ?? 'flutter'));
      return;
    }
    if (isTransientFlutterLayoutError(msg)) {
      return;
    }
    if (_isNonBlockingFlutterFrameworkAssertion(msg, st)) {
      final ex = ErrorMapper.map(details, details.stack, module ?? 'flutter');
      unawaited(AppLogger.instance.logError(ex, module: module ?? 'flutter'));
      return;
    }
    unawaited(handle(error, stackTrace: st, module: module ?? 'flutter'));
  }

  bool reportPlatformError(Object error, StackTrace stack, {String? module}) {
    final message = '$error\n$stack';
    if (isTransientFlutterLayoutError(message) ||
        _isNonBlockingFlutterFrameworkAssertion(message, stack)) {
      final ex = ErrorMapper.map(error, stack, module ?? 'platform');
      unawaited(AppLogger.instance.logError(ex, module: module ?? 'platform'));
      return true;
    }

    unawaited(handle(error, stackTrace: stack, module: module ?? 'platform'));
    return true;
  }
}

Future<T?> runSafe<T>(
  Future<T> Function() action, {
  BuildContext? context,
  VoidCallback? onRetry,
  String? module,
}) {
  return ErrorHandler.instance.runSafe<T>(
    action,
    context: context,
    onRetry: onRetry,
    module: module,
  );
}

T? guard<T>(
  T Function() action, {
  BuildContext? context,
  VoidCallback? onRetry,
  String? module,
}) {
  return ErrorHandler.instance.guard<T>(
    action,
    context: context,
    onRetry: onRetry,
    module: module,
  );
}
