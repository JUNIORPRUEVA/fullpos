import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/notifications/app_notification.dart';
import 'package:fullpos/core/notifications/fullpos_notification_card.dart';
import 'package:fullpos/core/notifications/fullpos_notification_controller.dart';
import 'package:fullpos/core/notifications/fullpos_notification_host.dart';

void main() {
  AppNotification notification(
    String id, {
    Duration duration = const Duration(seconds: 2),
    bool persistent = false,
    String? actionLabel,
    AppNotificationCallback? onAction,
  }) {
    return AppNotification(
      id: id,
      deduplicationKey: id,
      type: AppNotificationType.success,
      title: 'Venta completada',
      message: 'La venta fue registrada correctamente.',
      duration: duration,
      isPersistent: persistent,
      createdAt: DateTime(2026, 6, 12, 12),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  Future<void> pumpHost(
    WidgetTester tester,
    FullPosNotificationController controller, {
    Size size = const Size(1200, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        home: FullPosNotificationHost(
          controller: controller,
          child: const Scaffold(body: Text('Contenido POS')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('renders notifications above application content', (
    tester,
  ) async {
    final controller = FullPosNotificationController();
    controller.show(notification('one'));

    await pumpHost(tester, controller);

    expect(find.text('Contenido POS'), findsOneWidget);
    expect(find.text('Venta completada'), findsOneWidget);
    expect(find.byType(FullPosNotificationCard), findsOneWidget);
  });

  testWidgets('renders a stack of visible notifications', (tester) async {
    final controller = FullPosNotificationController();
    controller.show(notification('one'));
    controller.show(notification('two'));
    controller.show(notification('three'));

    await pumpHost(tester, controller);

    expect(find.byType(FullPosNotificationCard), findsNWidgets(3));
  });

  testWidgets('automatically dismisses a timed notification', (tester) async {
    final controller = FullPosNotificationController();
    controller.show(
      notification('one', duration: const Duration(milliseconds: 500)),
    );

    await pumpHost(tester, controller);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.visibleNotifications, isEmpty);
  });

  testWidgets('persistent notification remains visible', (tester) async {
    final controller = FullPosNotificationController();
    controller.show(
      notification(
        'one',
        duration: const Duration(milliseconds: 200),
        persistent: true,
      ),
    );

    await pumpHost(tester, controller);
    await tester.pump(const Duration(seconds: 2));

    expect(controller.visibleNotifications, hasLength(1));
  });

  testWidgets('hover pauses and resumes the countdown', (tester) async {
    final controller = FullPosNotificationController();
    controller.show(
      notification('one', duration: const Duration(milliseconds: 700)),
    );
    await pumpHost(tester, controller);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(
      tester.getCenter(find.byType(FullPosNotificationCard)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.visibleNotifications, hasLength(1));

    await gesture.removePointer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.visibleNotifications, isEmpty);
  });

  testWidgets('action callback cannot run twice concurrently', (tester) async {
    var actionCount = 0;
    final controller = FullPosNotificationController();
    controller.show(
      notification(
        'one',
        persistent: true,
        actionLabel: 'Reintentar',
        onAction: () async {
          actionCount++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        },
      ),
    );
    await pumpHost(tester, controller);

    await tester.tap(find.text('Reintentar'));
    await tester.tap(find.text('Reintentar'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 200));

    expect(actionCount, 1);
    expect(controller.visibleNotifications, isEmpty);
  });

  testWidgets('uses the available width on narrow screens', (tester) async {
    final controller = FullPosNotificationController();
    controller.show(notification('one', persistent: true));

    await pumpHost(tester, controller, size: const Size(360, 700));

    final size = tester.getSize(find.byType(FullPosNotificationCard));
    expect(size.width, closeTo(336, 0.1));
  });
}
