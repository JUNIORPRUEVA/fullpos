import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../ui/dialog_keyboard_shortcuts.dart';

class AppSideSheet extends StatelessWidget {
  const AppSideSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.width = 460,
    this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final double width;
  final VoidCallback? onClose;

  static Future<T?> show<T>(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? footer,
    double width = 460,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Cerrar panel',
      barrierColor: Colors.black.withOpacity(0.07),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (dialogContext, _, _) {
        return _AppSideSheetOverlay(
          icon: icon,
          title: title,
          subtitle: subtitle,
          width: width,
          footer: footer,
          child: child,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(curved),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.14, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E3EE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.10),
            blurRadius: 28,
            spreadRadius: -16,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.primary.withOpacity(0.14)),
                  ),
                  child: Icon(icon, color: scheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cerrar',
                  splashRadius: 18,
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE7EEF5)),
          Expanded(child: child),
          if (footer != null) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFFE7EEF5)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}

class _AppSideSheetOverlay extends StatelessWidget {
  const _AppSideSheetOverlay({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.width,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topOffset = mediaQuery.padding.top + AppSizes.topbarHeight + 8;

    return Material(
      type: MaterialType.transparency,
      child: DialogKeyboardShortcuts(
        enableSubmitShortcuts: false,
        onCancel: () => Navigator.of(context).maybePop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: topOffset,
              bottom: 12,
              left: 12,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = mediaQuery.size.width - 24;
                  final resolvedWidth = math.min(
                    width.clamp(430.0, 520.0),
                    math.max(360.0, availableWidth * 0.52),
                  );

                  return AppSideSheet(
                    icon: icon,
                    title: title,
                    subtitle: subtitle,
                    width: resolvedWidth,
                    footer: footer,
                    child: child,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
