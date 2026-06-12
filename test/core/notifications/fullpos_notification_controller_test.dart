import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/notifications/app_notification.dart';
import 'package:fullpos/core/notifications/fullpos_notification_controller.dart';

void main() {
  AppNotification notification(
    String id, {
    String? key,
    DateTime? createdAt,
    AppNotificationPriority priority = AppNotificationPriority.normal,
    AppNotificationCallback? onDismiss,
  }) {
    return AppNotification(
      id: id,
      deduplicationKey: key,
      type: AppNotificationType.information,
      title: 'Aviso $id',
      message: 'Mensaje $id',
      createdAt: createdAt ?? DateTime(2026, 6, 12, 12),
      priority: priority,
      onDismiss: onDismiss,
    );
  }

  test('shows newest notification first', () {
    final controller = FullPosNotificationController();

    controller.show(notification('one'));
    controller.show(notification('two'));

    expect(controller.visibleNotifications.map((item) => item.id), [
      'two',
      'one',
    ]);
  });

  test('keeps at most the configured visible count', () {
    final controller = FullPosNotificationController(maxVisible: 2);

    controller.show(notification('one'));
    controller.show(notification('two'));
    controller.show(notification('three'));

    expect(controller.visibleNotifications, hasLength(2));
    expect(controller.queuedNotifications, hasLength(1));
    expect(controller.queuedNotifications.single.id, 'three');
  });

  test('dismiss promotes the next queued notification', () async {
    final controller = FullPosNotificationController(maxVisible: 1);
    controller.show(notification('one'));
    controller.show(notification('two'));

    await controller.dismiss('one');

    expect(controller.visibleNotifications.single.id, 'two');
    expect(controller.queuedNotifications, isEmpty);
  });

  test(
    'critical queued notification is promoted before normal priority',
    () async {
      final controller = FullPosNotificationController(maxVisible: 1);
      controller.show(notification('visible'));
      controller.show(notification('normal'));
      controller.show(
        notification('critical', priority: AppNotificationPriority.critical),
      );

      await controller.dismiss('visible');

      expect(controller.visibleNotifications.single.id, 'critical');
      expect(controller.queuedNotifications.single.id, 'normal');
    },
  );

  test('duplicates merge and increment their counter', () {
    final controller = FullPosNotificationController();
    final now = DateTime(2026, 6, 12, 12);

    controller.show(notification('one', key: 'stock-1', createdAt: now));
    controller.show(
      notification(
        'two',
        key: 'stock-1',
        createdAt: now.add(const Duration(seconds: 2)),
      ),
    );

    expect(controller.visibleNotifications, hasLength(1));
    expect(controller.visibleNotifications.single.id, 'one');
    expect(controller.visibleNotifications.single.duplicateCount, 2);
  });

  test('same key outside duplicate window creates a new notification', () {
    final controller = FullPosNotificationController(
      duplicateWindow: const Duration(seconds: 3),
    );
    final now = DateTime(2026, 6, 12, 12);

    controller.show(notification('one', key: 'stock-1', createdAt: now));
    controller.show(
      notification(
        'two',
        key: 'stock-1',
        createdAt: now.add(const Duration(seconds: 4)),
      ),
    );

    expect(controller.visibleNotifications, hasLength(2));
  });

  test('dismiss callback runs once', () async {
    var dismissCount = 0;
    final controller = FullPosNotificationController();
    controller.show(notification('one', onDismiss: () => dismissCount++));

    await controller.dismiss('one');
    await controller.dismiss('one');

    expect(dismissCount, 1);
  });
}
