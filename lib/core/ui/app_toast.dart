import 'package:flutter/material.dart';

import '../notifications/fullpos_notifications.dart';

enum AppToastType { info, success, warning, error }

/// Backward-compatible facade for legacy toast callers.
///
/// Rendering is delegated to the single global FullPOS notification host.
class AppToast {
  AppToast._();

  static String? _activeId;

  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 3),
    String? title,
  }) {
    _activeId = FullPosNotifications.show(
      type: switch (type) {
        AppToastType.success => AppNotificationType.success,
        AppToastType.warning => AppNotificationType.warning,
        AppToastType.error => AppNotificationType.error,
        AppToastType.info => AppNotificationType.information,
      },
      title: title ?? _resolveTitle(type),
      message: message,
      duration: duration,
      priority: type == AppToastType.error
          ? AppNotificationPriority.high
          : AppNotificationPriority.normal,
    );
  }

  static void showSnackBar(
    BuildContext context,
    SnackBar snackBar, {
    AppToastType? type,
  }) {
    final message = _extractMessage(snackBar.content);
    if (message == null || snackBar.action != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
      return;
    }

    show(
      context,
      message,
      duration: snackBar.duration,
      type: type ?? AppToastType.info,
    );
  }

  static void dismissCurrent() {
    final id = _activeId;
    _activeId = null;
    if (id != null) {
      FullPosNotifications.dismiss(id);
    }
  }

  static String? _extractMessage(Widget content) {
    if (content is Text) {
      return content.data ?? content.textSpan?.toPlainText();
    }
    return null;
  }

  static String _resolveTitle(AppToastType type) {
    return switch (type) {
      AppToastType.success => 'Operación completada',
      AppToastType.warning => 'Atención',
      AppToastType.error => 'Revisa esto',
      AppToastType.info => 'Notificación',
    };
  }
}
