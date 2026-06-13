import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'fullpos_notification_card.dart';
import 'fullpos_notification_controller.dart';
import 'fullpos_notifications.dart';

class FullPosNotificationHost extends StatefulWidget {
  const FullPosNotificationHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.controller,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final FullPosNotificationController? controller;

  @override
  State<FullPosNotificationHost> createState() =>
      _FullPosNotificationHostState();
}

class _FullPosNotificationHostState extends State<FullPosNotificationHost> {
  static int _mountedHosts = 0;

  OverlayEntry? _entry;
  OverlayState? _overlay;
  bool _syncScheduled = false;
  int _overlayRetryCount = 0;

  FullPosNotificationController get _controller =>
      widget.controller ?? FullPosNotifications.controller;

  @override
  void initState() {
    super.initState();
    _mountedHosts++;
    assert(
      _mountedHosts == 1,
      'Only one FullPosNotificationHost may be mounted at a time.',
    );
    _controller.addListener(_handleControllerChanged);
    _scheduleOverlaySync();
  }

  @override
  void didUpdateWidget(covariant FullPosNotificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController =
        oldWidget.controller ?? FullPosNotifications.controller;
    if (oldController != _controller) {
      oldController.removeListener(_handleControllerChanged);
      _controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.navigatorKey != widget.navigatorKey) {
      _removeEntry();
    }
    _scheduleOverlaySync();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _removeEntry();
    _mountedHosts--;
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    if (_entry?.mounted == true) {
      _entry!.markNeedsBuild();
    } else {
      _scheduleOverlaySync();
    }
  }

  void _scheduleOverlaySync() {
    if (_syncScheduled || !mounted) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _syncOverlay();
    });
  }

  void _syncOverlay() {
    final nextOverlay = widget.navigatorKey.currentState?.overlay;
    if (nextOverlay == null || !nextOverlay.mounted) {
      if (kDebugMode && _controller.visibleNotifications.isNotEmpty) {
        debugPrint(
          '[FullPosNotifications] Root overlay unavailable; rendering deferred.',
        );
      }
      if (_controller.visibleNotifications.isNotEmpty &&
          _overlayRetryCount < 8) {
        _overlayRetryCount++;
        _scheduleOverlaySync();
      }
      return;
    }

    _overlayRetryCount = 0;
    if (_overlay == nextOverlay && _entry?.mounted == true) {
      _entry!.markNeedsBuild();
      return;
    }

    _removeEntry();
    _overlay = nextOverlay;
    _entry = OverlayEntry(
      builder: (context) =>
          _FullPosNotificationViewport(controller: _controller),
    );

    try {
      nextOverlay.insert(_entry!);
    } catch (error, stackTrace) {
      debugPrint(
        '[FullPosNotifications] Could not attach to root overlay: '
        '$error\n$stackTrace',
      );
      _entry = null;
      _overlay = null;
    }
  }

  void _removeEntry() {
    final entry = _entry;
    _entry = null;
    _overlay = null;
    if (entry?.mounted == true) {
      entry!.remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOverlaySync();
    return widget.child;
  }
}

class _FullPosNotificationViewport extends StatelessWidget {
  const _FullPosNotificationViewport({required this.controller});

  final FullPosNotificationController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;
          if (!availableWidth.isFinite ||
              !availableHeight.isFinite ||
              availableWidth <= 0 ||
              availableHeight <= 0) {
            return const SizedBox.shrink();
          }

          final horizontalMargin = availableWidth < 600 ? 12.0 : 20.0;
          final topMargin = availableWidth < 600 ? 12.0 : 20.0;
          final cardWidth = math.min(
            420.0,
            math.max(0.0, availableWidth - (horizontalMargin * 2)),
          );
          if (cardWidth <= 0) return const SizedBox.shrink();

          final mediaQuery = MediaQuery.maybeOf(context);
          final safeTop = mediaQuery?.padding.top ?? 0;
          final safeRight = mediaQuery?.padding.right ?? 0;
          final safeBottom = mediaQuery?.padding.bottom ?? 0;
          final maxListHeight = math.max(
            0.0,
            availableHeight - safeTop - safeBottom - (topMargin * 2),
          );
          if (maxListHeight <= 0) return const SizedBox.shrink();

          final notifications = controller.visibleNotifications;
          if (notifications.isEmpty) return const SizedBox.shrink();

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: safeTop + topMargin,
                right: safeRight + horizontalMargin,
                width: cardWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxListHeight),
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final notification in notifications)
                          Padding(
                            key: ValueKey(notification.id),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RepaintBoundary(
                              child: FullPosNotificationCard(
                                notification: notification,
                                controller: controller,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
