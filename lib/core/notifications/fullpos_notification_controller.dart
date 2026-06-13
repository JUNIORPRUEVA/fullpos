import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_notification.dart';

class FullPosNotificationController extends ChangeNotifier {
  FullPosNotificationController({
    this.maxVisible = 5,
    this.duplicateWindow = const Duration(seconds: 8),
  }) : assert(maxVisible > 0);

  final int maxVisible;
  final Duration duplicateWindow;
  final List<AppNotification> _visible = <AppNotification>[];
  final List<AppNotification> _queued = <AppNotification>[];
  final Set<String> _expandedDetails = <String>{};
  bool _disposed = false;

  List<AppNotification> get visibleNotifications =>
      List<AppNotification>.unmodifiable(_visible);
  List<AppNotification> get queuedNotifications =>
      List<AppNotification>.unmodifiable(_queued);
  bool isDetailsExpanded(String id) => _expandedDetails.contains(id);

  void show(AppNotification notification) {
    if (_disposed) {
      debugPrint(
        '[FullPosNotifications] Controller disposed. Notification skipped.',
      );
      return;
    }
    if (_mergeDuplicate(notification)) {
      _notifySafely();
      return;
    }

    if (_visible.length < maxVisible) {
      _visible.insert(0, notification);
    } else {
      _queued.add(notification);
      _sortQueue();
    }
    _notifySafely();
  }

  Future<void> dismiss(String id) async {
    if (_disposed) return;
    AppNotification? removed;
    final visibleIndex = _visible.indexWhere((item) => item.id == id);
    if (visibleIndex >= 0) {
      removed = _visible.removeAt(visibleIndex);
      _promoteNext();
    } else {
      final queuedIndex = _queued.indexWhere((item) => item.id == id);
      if (queuedIndex >= 0) {
        removed = _queued.removeAt(queuedIndex);
      }
    }

    if (removed == null) return;
    _expandedDetails.remove(id);
    _notifySafely();
    try {
      await removed.onDismiss?.call();
    } catch (error, stackTrace) {
      debugPrint(
        '[FullPosNotifications] onDismiss failed: $error\n$stackTrace',
      );
    }
  }

  void dismissAll() {
    if (_disposed) return;
    final removed = <AppNotification>[..._visible, ..._queued];
    _visible.clear();
    _queued.clear();
    _expandedDetails.clear();
    _notifySafely();
    for (final notification in removed) {
      unawaited(
        Future<void>.sync(() => notification.onDismiss?.call()).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint(
            '[FullPosNotifications] onDismiss failed: $error\n$stackTrace',
          );
        }),
      );
    }
  }

  void clear() => dismissAll();

  void toggleDetails(String id) {
    if (_disposed) return;
    final index = _visible.indexWhere((item) => item.id == id);
    if (index < 0 || (_visible[index].details?.trim().isEmpty ?? true)) return;

    if (!_expandedDetails.add(id)) {
      _expandedDetails.remove(id);
    }
    _notifySafely();
  }

  bool _mergeDuplicate(AppNotification incoming) {
    final now = incoming.createdAt;
    final visibleIndex = _visible.indexWhere(
      (item) =>
          item.effectiveDeduplicationKey ==
              incoming.effectiveDeduplicationKey &&
          now.difference(item.createdAt).abs() <= duplicateWindow,
    );
    if (visibleIndex >= 0) {
      final current = _visible[visibleIndex];
      final merged = current.copyWith(
        createdAt: now,
        duplicateCount: current.duplicateCount + 1,
        duration: incoming.duration,
        priority: incoming.priority,
      );
      _visible
        ..removeAt(visibleIndex)
        ..insert(0, merged);
      return true;
    }

    final queuedIndex = _queued.indexWhere(
      (item) =>
          item.effectiveDeduplicationKey ==
              incoming.effectiveDeduplicationKey &&
          now.difference(item.createdAt).abs() <= duplicateWindow,
    );
    if (queuedIndex < 0) return false;

    final current = _queued[queuedIndex];
    _queued[queuedIndex] = current.copyWith(
      createdAt: now,
      duplicateCount: current.duplicateCount + 1,
      duration: incoming.duration,
      priority: incoming.priority,
    );
    _sortQueue();
    return true;
  }

  void _promoteNext() {
    if (_queued.isEmpty || _visible.length >= maxVisible) return;
    _sortQueue();
    _visible.insert(0, _queued.removeAt(0));
  }

  void _sortQueue() {
    _queued.sort((a, b) {
      final priority = b.priority.index.compareTo(a.priority.index);
      if (priority != 0) return priority;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _visible.clear();
    _queued.clear();
    _expandedDetails.clear();
    super.dispose();
  }
}
