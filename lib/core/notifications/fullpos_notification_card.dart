import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import 'app_notification.dart';
import 'fullpos_notification_controller.dart';

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  Timer? _copiedTimer;
  bool _closing = false;
  bool _actionRunning = false;
  bool _copied = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
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
    _copiedTimer?.cancel();
    _progressController
      ..removeStatusListener(_handleProgressStatus)
      ..dispose();
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
    if (!mounted) return;
    await widget.controller.dismiss(widget.notification.id);
  }

  Future<void> _runAction() async {
    final action = widget.notification.onAction;
    if (action == null || _actionRunning) return;
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    try {
      await action();
      if (widget.notification.dismissOnAction) {
        await _close();
      }
    } catch (_) {
      if (mounted && !_closing) {
        setState(() {
          _actionError = 'La acción no pudo completarse.';
        });
      }
    } finally {
      if (mounted && !_closing) {
        setState(() => _actionRunning = false);
      }
    }
  }

  Future<void> _copyDetails() async {
    final details = widget.notification.details?.trim();
    if (details == null || details.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: details));
    if (!mounted || _closing) return;

    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_closing) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(widget.notification.type);
    final notification = widget.notification;
    final details = notification.details?.trim();
    final hasDetails = details != null && details.isNotEmpty;
    final detailsExpanded = widget.controller.isDetailsExpanded(
      notification.id,
    );

    return MouseRegion(
      onEnter: (_) {
        if (mounted) _progressController.stop();
      },
      onExit: (_) {
        if (mounted && !_closing) _startProgress();
      },
      child: Semantics(
        liveRegion: true,
        label: '${notification.title}. ${notification.message}',
        child: Material(
          color: Colors.white,
          elevation: 8,
          shadowColor: const Color(0x3D030A17),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: style.borderColor),
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
                                  maxLines: 2,
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
                                    borderRadius: BorderRadius.circular(999),
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
                            maxLines: hasDetails ? 5 : 8,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDarkSecondary,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          if (_actionError != null) ...[
                            const SizedBox(height: 7),
                            Text(
                              _actionError!,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (hasDetails ||
                              (notification.actionLabel != null &&
                                  notification.onAction != null)) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (hasDetails)
                                  TextButton.icon(
                                    onPressed: () => widget.controller
                                        .toggleDetails(notification.id),
                                    style: _compactTextButtonStyle(style.color),
                                    icon: Icon(
                                      detailsExpanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      detailsExpanded
                                          ? 'Ocultar detalles'
                                          : 'Ver detalles',
                                    ),
                                  ),
                                if (hasDetails)
                                  TextButton.icon(
                                    onPressed: _copyDetails,
                                    style: _compactTextButtonStyle(style.color),
                                    icon: Icon(
                                      _copied
                                          ? Icons.check_rounded
                                          : Icons.copy_rounded,
                                      size: 15,
                                    ),
                                    label: Text(
                                      _copied
                                          ? 'Detalles copiados'
                                          : 'Copiar detalles',
                                    ),
                                  ),
                                if (notification.actionLabel != null &&
                                    notification.onAction != null)
                                  TextButton(
                                    onPressed: _actionRunning
                                        ? null
                                        : _runAction,
                                    style: _compactTextButtonStyle(style.color),
                                    child: Text(
                                      _actionRunning
                                          ? 'Procesando...'
                                          : notification.actionLabel!,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (hasDetails && detailsExpanded) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 220),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F8FB),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: const Color(0xFFDCE3EC),
                                ),
                              ),
                              child: SingleChildScrollView(
                                primary: false,
                                child: SelectableText(
                                  details,
                                  style: const TextStyle(
                                    color: AppColors.textDarkSecondary,
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (notification.isDismissible)
                      Semantics(
                        button: true,
                        label: 'Cerrar notificación',
                        child: IconButton(
                          onPressed: _closing ? null : _close,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
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
                        widthFactor: _progressController.value.clamp(0.0, 1.0),
                        child: Container(height: 3, color: style.color),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _compactTextButtonStyle(Color color) {
    return TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
