import 'package:flutter/material.dart';

import 'app_notification.dart';
import 'fullpos_notification_controller.dart';

export 'app_notification.dart';

class FullPosNotifications {
  FullPosNotifications._();

  static final FullPosNotificationController controller =
      FullPosNotificationController();
  static int _sequence = 0;

  static String show({
    required AppNotificationType type,
    required String title,
    required String message,
    String? deduplicationKey,
    IconData? icon,
    Duration duration = const Duration(seconds: 5),
    bool isPersistent = false,
    String? actionLabel,
    AppNotificationCallback? onAction,
    AppNotificationCallback? onDismiss,
    String? relatedEntityId,
    AppNotificationPriority priority = AppNotificationPriority.normal,
    bool dismissOnAction = true,
    bool showProgress = true,
  }) {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}-${_sequence++}';
    controller.show(
      AppNotification(
        id: id,
        deduplicationKey: deduplicationKey,
        type: type,
        title: title,
        message: message,
        icon: icon,
        duration: duration,
        isPersistent: isPersistent,
        createdAt: now,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: onDismiss,
        relatedEntityId: relatedEntityId,
        priority: priority,
        dismissOnAction: dismissOnAction,
        showProgress: showProgress,
      ),
    );
    return id;
  }

  static String success(
    String message, {
    String title = 'Operación completada',
    String? deduplicationKey,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    AppNotificationCallback? onAction,
  }) {
    return show(
      type: AppNotificationType.success,
      title: title,
      message: message,
      deduplicationKey: deduplicationKey,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static String error(
    String message, {
    String title = 'No se pudo completar',
    String? deduplicationKey,
    bool isPersistent = false,
    String? actionLabel,
    AppNotificationCallback? onAction,
  }) {
    return show(
      type: AppNotificationType.error,
      title: title,
      message: message,
      deduplicationKey: deduplicationKey,
      duration: const Duration(seconds: 7),
      isPersistent: isPersistent,
      actionLabel: actionLabel,
      onAction: onAction,
      priority: AppNotificationPriority.high,
    );
  }

  static String warning(
    String message, {
    String title = 'Atención',
    String? deduplicationKey,
    Duration duration = const Duration(seconds: 6),
    String? actionLabel,
    AppNotificationCallback? onAction,
  }) {
    return show(
      type: AppNotificationType.warning,
      title: title,
      message: message,
      deduplicationKey: deduplicationKey,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      priority: AppNotificationPriority.high,
    );
  }

  static String information(
    String message, {
    String title = 'Información',
    String? deduplicationKey,
    Duration duration = const Duration(seconds: 5),
  }) {
    return show(
      type: AppNotificationType.information,
      title: title,
      message: message,
      deduplicationKey: deduplicationKey,
      duration: duration,
    );
  }

  static String inventory(
    String message, {
    String title = 'Inventario',
    String? deduplicationKey,
    String? actionLabel,
    AppNotificationCallback? onAction,
  }) {
    return show(
      type: AppNotificationType.inventory,
      title: title,
      message: message,
      deduplicationKey: deduplicationKey,
      duration: const Duration(seconds: 6),
      actionLabel: actionLabel,
      onAction: onAction,
      priority: AppNotificationPriority.high,
    );
  }

  static String printer(
    String message, {
    String title = 'Impresión',
    bool success = true,
    String? deduplicationKey,
    String? actionLabel,
    AppNotificationCallback? onAction,
  }) {
    return show(
      type: success ? AppNotificationType.printer : AppNotificationType.error,
      title: title,
      message: message,
      deduplicationKey: deduplicationKey,
      duration: Duration(seconds: success ? 4 : 7),
      actionLabel: actionLabel,
      onAction: onAction,
      priority: success
          ? AppNotificationPriority.normal
          : AppNotificationPriority.high,
    );
  }
}
