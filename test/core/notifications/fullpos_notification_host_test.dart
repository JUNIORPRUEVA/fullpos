import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    String? details,
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
      details: details,
    );
  }

  Future<void> pumpHost(
    WidgetTester tester,
    FullPosNotificationController controller, {
    Size size = const Size(1200, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: FullPosNotificationHost(
          navigatorKey: navigatorKey,
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

  testWidgets('can dismiss a notification while the mouse is over it', (
    tester,
  ) async {
    final controller = FullPosNotificationController();
    controller.show(notification('one', persistent: true));
    await pumpHost(tester, controller);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(
      tester.getCenter(find.byType(FullPosNotificationCard)),
    );
    await tester.pump();

    await controller.dismiss('one');
    await tester.pump();
    await gesture.removePointer();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.visibleNotifications, isEmpty);
  });

  testWidgets('can show a notification immediately after closing a dialog', (
    tester,
  ) async {
    final controller = FullPosNotificationController();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: FullPosNotificationHost(
          navigatorKey: navigatorKey,
          controller: controller,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: const Text('Procesando devolución'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Confirmar'),
                        ),
                      ],
                    ),
                  );
                  controller.show(notification('refund-success'));
                },
                child: const Text('Abrir devolución'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir devolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Venta completada'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FullPosNotificationCard),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
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

  testWidgets('notification cards contain no Tooltip widgets', (tester) async {
    final controller = FullPosNotificationController();
    controller.show(notification('one', persistent: true));

    await pumpHost(tester, controller);

    expect(
      find.descendant(
        of: find.byType(FullPosNotificationCard),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
  });

  testWidgets('long technical details expand within a bounded height', (
    tester,
  ) async {
    final controller = FullPosNotificationController();
    controller.show(
      notification(
        'one',
        persistent: true,
        details: List<String>.filled(80, 'stack frame').join('\n'),
      ),
    );

    await pumpHost(tester, controller, size: const Size(800, 500));
    await tester.tap(find.text('Ver detalles'));
    await tester.pump();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FullPosNotificationCard)).height,
      lessThanOrEqualTo(480),
    );
  });

  testWidgets('copies technical details without creating another notice', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = FullPosNotificationController();
    controller.show(
      notification('one', persistent: true, details: 'technical details'),
    );

    await pumpHost(tester, controller);
    await tester.tap(find.text('Copiar detalles'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Detalles copiados'), findsOneWidget);
    expect(controller.visibleNotifications, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives root route replacement while visible', (tester) async {
    final controller = FullPosNotificationController();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Login')),
        builder: (context, child) => FullPosNotificationHost(
          navigatorKey: navigatorKey,
          controller: controller,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    controller.show(notification('one', persistent: true));
    await tester.pump();
    navigatorKey.currentState!.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Ventas')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ventas'), findsOneWidget);
    expect(find.byType(FullPosNotificationCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not render cards with a zero-sized surface', (
    tester,
  ) async {
    final controller = FullPosNotificationController();
    controller.show(notification('one', persistent: true));

    await pumpHost(tester, controller, size: Size.zero);

    expect(find.byType(FullPosNotificationCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
