import 'dart:async';

import 'package:flutter/material.dart';

enum AppNotificationType {
  success,
  error,
  warning,
  information,
  inventory,
  payment,
  printer,
  shift,
  system,
}

enum AppNotificationPriority { low, normal, high, critical }

typedef AppNotificationCallback = FutureOr<void> Function();

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.deduplicationKey,
    this.icon,
    this.duration = const Duration(seconds: 5),
    this.isPersistent = false,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.duplicateCount = 1,
    this.relatedEntityId,
    this.priority = AppNotificationPriority.normal,
    this.dismissOnAction = true,
    this.showProgress = true,
  });

  final String id;
  final String? deduplicationKey;
  final AppNotificationType type;
  final String title;
  final String message;
  final IconData? icon;
  final Duration duration;
  final bool isPersistent;
  final DateTime createdAt;
  final String? actionLabel;
  final AppNotificationCallback? onAction;
  final AppNotificationCallback? onDismiss;
  final int duplicateCount;
  final String? relatedEntityId;
  final AppNotificationPriority priority;
  final bool dismissOnAction;
  final bool showProgress;

  String get effectiveDeduplicationKey {
    final explicit = deduplicationKey?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return '${type.name}|$title|$message|${relatedEntityId ?? ''}';
  }

  AppNotification copyWith({
    DateTime? createdAt,
    int? duplicateCount,
    Duration? duration,
    AppNotificationPriority? priority,
  }) {
    return AppNotification(
      id: id,
      deduplicationKey: deduplicationKey,
      type: type,
      title: title,
      message: message,
      icon: icon,
      duration: duration ?? this.duration,
      isPersistent: isPersistent,
      createdAt: createdAt ?? this.createdAt,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismiss: onDismiss,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      relatedEntityId: relatedEntityId,
      priority: priority ?? this.priority,
      dismissOnAction: dismissOnAction,
      showProgress: showProgress,
    );
  }
}
