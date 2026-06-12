import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'fullpos_notification_controller.dart';
import 'fullpos_notifications.dart';

class FullPosNotificationCard extends StatefulWidget {
  const FullPosNotificationCard({
    super.key,
    required this.notification,
    required this.controller,
  });

  final AppNotification notification;
  final FullPosNotificationController controller;

  @override
  State<FullPosNotificationCard> createState() =>
      _FullPosNotificationCardState();
}

class _FullPosNotificationCardState extends State<FullPosNotificationCard>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _progressController;
  bool _closing = false;
  bool _actionRunning = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    )..forward();
    _progressController = AnimationController(
      vsync: this,
      duration: widget.notification.duration,
      value: 1,
    )..addStatusListener(_handleProgressStatus);
    _startProgress();
  }

  @override
  void didUpdateWidget(covariant FullPosNotificationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notification.createdAt != widget.notification.createdAt ||
        oldWidget.notification.duplicateCount !=
            widget.notification.duplicateCount ||
        oldWidget.notification.duration != widget.notification.duration) {
      _progressController
        ..duration = widget.notification.duration
        ..value = 1;
      _startProgress();
    }
  }

  @override
  void dispose() {
    _progressController
      ..removeStatusListener(_handleProgressStatus)
      ..dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _startProgress() {
    if (!widget.notification.isPersistent) {
      _progressController.reverse(from: _progressController.value);
    }
  }

  void _handleProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_closing) {
      unawaited(_close());
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _progressController.stop();
    await _entryController.reverse();
    if (!mounted) return;
    await widget.controller.dismiss(widget.notification.id);
  }

  Future<void> _runAction() async {
    final action = widget.notification.onAction;
    if (action == null || _actionRunning) return;
    setState(() => _actionRunning = true);
    try {
      await action();
      if (widget.notification.dismissOnAction) {
        await _close();
      }
    } catch (error) {
      FullPosNotifications.error(
        'La acción del aviso no pudo completarse.',
        deduplicationKey: 'notification-action-error',
      );
    } finally {
      if (mounted && !_closing) {
        setState(() => _actionRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(widget.notification.type);
    final notification = widget.notification;
    final animation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return MouseRegion(
      onEnter: (_) => _progressController.stop(),
      onExit: (_) => _startProgress(),
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.12, -0.04),
            end: Offset.zero,
          ).animate(animation),
          child: Semantics(
            liveRegion: true,
            label: '${notification.title}. ${notification.message}',
            child: Material(
              color: Colors.transparent,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: style.borderColor),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x24030A17),
                      blurRadius: 22,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: style.softColor,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              notification.icon ?? style.icon,
                              size: 21,
                              color: style.color,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        notification.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textDark,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                    if (notification.duplicateCount > 1)
                                      Container(
                                        margin: const EdgeInsets.only(left: 7),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: style.softColor,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          'x${notification.duplicateCount}',
                                          style: TextStyle(
                                            color: style.color,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  notification.message,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textDarkSecondary,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                                if (notification.actionLabel != null &&
                                    notification.onAction != null) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _actionRunning
                                        ? null
                                        : _runAction,
                                    style: TextButton.styleFrom(
                                      foregroundColor: style.color,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      _actionRunning
                                          ? 'Procesando...'
                                          : notification.actionLabel!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Tooltip(
                            message: 'Cerrar notificación',
                            child: IconButton(
                              onPressed: _close,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              color: AppColors.textDarkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!notification.isPersistent && notification.showProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _progressController.value,
                              child: Container(height: 3, color: style.color),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationStyle {
  const _NotificationStyle({
    required this.color,
    required this.softColor,
    required this.borderColor,
    required this.icon,
  });

  final Color color;
  final Color softColor;
  final Color borderColor;
  final IconData icon;
}

_NotificationStyle _styleFor(AppNotificationType type) {
  return switch (type) {
    AppNotificationType.success => const _NotificationStyle(
      color: AppColors.success,
      softColor: AppColors.successLight,
      borderColor: Color(0xFFB7EBD8),
      icon: Icons.check_circle_outline_rounded,
    ),
    AppNotificationType.error => const _NotificationStyle(
      color: AppColors.error,
      softColor: AppColors.errorLight,
      borderColor: Color(0xFFF8C1C1),
      icon: Icons.error_outline_rounded,
    ),
    AppNotificationType.warning ||
    AppNotificationType.inventory => const _NotificationStyle(
      color: AppColors.warning,
      softColor: AppColors.warningLight,
      borderColor: Color(0xFFF4D997),
      icon: Icons.warning_amber_rounded,
    ),
    AppNotificationType.payment => const _NotificationStyle(
      color: AppColors.success,
      softColor: AppColors.successLight,
      borderColor: Color(0xFFB7EBD8),
      icon: Icons.payments_outlined,
    ),
    AppNotificationType.printer => const _NotificationStyle(
      color: AppColors.brandBlue,
      softColor: AppColors.infoLight,
      borderColor: Color(0xFFBFD5FA),
      icon: Icons.print_outlined,
    ),
    AppNotificationType.shift => const _NotificationStyle(
      color: Color(0xFF7C3AED),
      softColor: Color(0xFFEDE9FE),
      borderColor: Color(0xFFD8CCFA),
      icon: Icons.point_of_sale_outlined,
    ),
    AppNotificationType.information ||
    AppNotificationType.system => const _NotificationStyle(
      color: AppColors.info,
      softColor: AppColors.infoLight,
      borderColor: Color(0xFFBFD5FA),
      icon: Icons.info_outline_rounded,
    ),
  };
}
