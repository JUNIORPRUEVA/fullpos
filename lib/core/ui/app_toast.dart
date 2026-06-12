import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/color_utils.dart';

enum AppToastType { info, success, warning, error }

class AppToast {
  AppToast._();

  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 3),
    String? title,
  }) {
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final accent = backgroundColor ?? _resolveAccentColor(type, scheme);

    if (overlay == null) {
      _showFallbackSnackBar(
        context,
        message,
        backgroundColor: accent,
        duration: duration,
      );
      return;
    }

    final surface = _resolveToastSurface(accent, scheme);
    final fg = ColorUtils.readableTextColor(surface);
    final resolvedTitle = title ?? _resolveTitle(type);
    final resolvedIcon = _resolveIcon(type);

    _dismissTimer?.cancel();
    _activeEntry?.remove();

    _activeEntry = OverlayEntry(
      builder: (overlayContext) {
        final mediaQuery = MediaQuery.of(overlayContext);
        final width = mediaQuery.size.width;
        final safeTop = math.max(12.0, mediaQuery.viewPadding.top + 12);
        final safeRight = math.max(12.0, mediaQuery.viewPadding.right + 12);
        final availableWidth = math.max(120.0, width - safeRight - 12);
        final maxWidth = math.min(
          availableWidth,
          width >= 1200 ? 396.0 : 344.0,
        );

        return Positioned(
          top: safeTop,
          right: safeRight,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.min(280.0, maxWidth),
                maxWidth: maxWidth,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withOpacity(0.28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(resolvedIcon, size: 18, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              resolvedTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              message,
                              style: TextStyle(
                                color: fg.withOpacity(0.92),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: dismissCurrent,
                        splashRadius: 16,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: fg.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_activeEntry!);
    _dismissTimer = Timer(duration, dismissCurrent);
  }

  static void showSnackBar(
    BuildContext context,
    SnackBar snackBar, {
    AppToastType? type,
  }) {
    final message = _extractMessage(snackBar.content);
    if (message == null || snackBar.action != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    final inferredType =
        type ??
        _inferType(snackBar.backgroundColor, Theme.of(context).colorScheme);
    show(
      context,
      message,
      backgroundColor: snackBar.backgroundColor,
      duration: snackBar.duration,
      title: _resolveTitle(inferredType),
      type: inferredType,
    );
  }

  static void dismissCurrent() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }

  static void _showFallbackSnackBar(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    required Duration duration,
  }) {
    final fg = ColorUtils.readableTextColor(backgroundColor);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: fg)),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  static String? _extractMessage(Widget content) {
    if (content is Text) {
      return content.data ?? content.textSpan?.toPlainText();
    }
    return null;
  }

  static AppToastType _inferType(Color? color, ColorScheme scheme) {
    if (color == null) return AppToastType.info;
    if (color.value == scheme.error.value) return AppToastType.error;
    if (color.value == scheme.tertiary.value) return AppToastType.success;
    if (color.value == scheme.secondary.value) return AppToastType.warning;
    return AppToastType.info;
  }

  static Color _resolveAccentColor(AppToastType type, ColorScheme scheme) {
    return switch (type) {
      AppToastType.success => scheme.tertiary,
      AppToastType.warning => scheme.secondary,
      AppToastType.error => scheme.error,
      AppToastType.info => scheme.primary,
    };
  }

  static Color _resolveToastSurface(Color accent, ColorScheme scheme) {
    final base = Color.alphaBlend(
      accent.withOpacity(ColorUtils.isLight(scheme.surface) ? 0.14 : 0.22),
      scheme.surface,
    );

    if (ColorUtils.isLight(base)) {
      return Color.alphaBlend(Colors.white.withOpacity(0.18), base);
    }

    return Color.alphaBlend(Colors.white.withOpacity(0.10), base);
  }

  static String _resolveTitle(AppToastType type) {
    return switch (type) {
      AppToastType.success => 'Operacion completada',
      AppToastType.warning => 'Atencion',
      AppToastType.error => 'Revisa esto',
      AppToastType.info => 'Notificacion',
    };
  }

  static IconData _resolveIcon(AppToastType type) {
    return switch (type) {
      AppToastType.success => Icons.check_circle_rounded,
      AppToastType.warning => Icons.warning_amber_rounded,
      AppToastType.error => Icons.error_outline_rounded,
      AppToastType.info => Icons.notifications_active_rounded,
    };
  }
}
