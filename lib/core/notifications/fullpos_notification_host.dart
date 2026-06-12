import 'package:flutter/material.dart';

import 'fullpos_notification_card.dart';
import 'fullpos_notification_controller.dart';
import 'fullpos_notifications.dart';

class FullPosNotificationHost extends StatelessWidget {
  const FullPosNotificationHost({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final FullPosNotificationController? controller;

  @override
  Widget build(BuildContext context) {
    final effectiveController = controller ?? FullPosNotifications.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final cardWidth = narrow
            ? (constraints.maxWidth - 24).clamp(280.0, 380.0).toDouble()
            : 370.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            AnimatedBuilder(
              animation: effectiveController,
              builder: (context, _) {
                final notifications = effectiveController.visibleNotifications;
                if (notifications.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: narrow ? 12 : 68,
                  right: narrow ? 12 : 20,
                  width: cardWidth,
                  child: SafeArea(
                    bottom: false,
                    left: false,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final notification in notifications)
                            Padding(
                              key: ValueKey(notification.id),
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FullPosNotificationCard(
                                notification: notification,
                                controller: effectiveController,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
