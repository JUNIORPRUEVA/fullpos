import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/dialog_keyboard_shortcuts.dart';

class AppSideSheet extends StatelessWidget {
  const AppSideSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.width = 620,
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
    double width = 620,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Cerrar panel',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, _) {
        return _AppSideSheetOverlay(
          icon: icon,
          title: title,
          subtitle: subtitle,
          width: width,
          footer: footer,
          barrierDismissible: barrierDismissible,
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
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
          child: SlideTransition(
            // Ahora entra desde la derecha hacia la izquierda.
            position: Tween<Offset>(
              begin: const Offset(0.10, 0),
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
    final size = MediaQuery.sizeOf(context);
    final compact = size.width <= 1366 || size.height <= 900;
    final footerPadding = compact
        ? const EdgeInsets.fromLTRB(16, 10, 16, 12)
        : const EdgeInsets.fromLTRB(22, 16, 22, 18);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,

        // Como ahora está pegado a la derecha,
        // el borde va del lado izquierdo del panel.
        border: const Border(
          left: BorderSide(color: Color(0xFFD8E2EE), width: 1),
        ),

        // Sombra hacia la izquierda para dar profundidad.
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.18),
            blurRadius: 36,
            spreadRadius: -18,
            offset: const Offset(-20, 0),
          ),
          BoxShadow(
            color: const Color(0xFF1A56DB).withOpacity(0.055),
            blurRadius: 42,
            spreadRadius: -20,
            offset: const Offset(-12, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SideSheetHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            onClose: onClose ?? () => Navigator.of(context).maybePop(),
            primaryColor: scheme.primary,
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE7EEF5)),
          Expanded(
            child: ColoredBox(color: Colors.white, child: child),
          ),
          if (footer != null) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFFE7EEF5)),
            Container(
              padding: footerPadding,
              decoration: const BoxDecoration(color: Color(0xFFFBFCFE)),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}

class _SideSheetHeader extends StatelessWidget {
  const _SideSheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.primaryColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact = size.width <= 1366 || size.height <= 900;
    final headerPadding = compact
        ? const EdgeInsets.fromLTRB(16, 12, 12, 12)
        : const EdgeInsets.fromLTRB(22, 18, 16, 17);
    final iconSize = compact ? 38.0 : 46.0;
    final iconSymbolSize = compact ? 20.0 : 23.0;
    final closeSize = compact ? 34.0 : 38.0;

    return Container(
      padding: headerPadding,
      decoration: const BoxDecoration(color: Color(0xFFFBFCFE)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: primaryColor.withOpacity(0.18),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.08),
                  blurRadius: 18,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: primaryColor, size: iconSymbolSize),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.25,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: closeSize,
                height: closeSize,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ),
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
    required this.barrierDismissible,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final double width;
  final bool barrierDismissible;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final compact = screenWidth <= 1366 || screenHeight <= 900;

    // Pegado completamente a la derecha, arriba y abajo.
    const double topOffset = 0.0;
    const double bottomOffset = 0.0;
    const double rightOffset = 0.0;

    final availableWidth = math.max(320.0, screenWidth - rightOffset);

    final maxPanelWidth = compact ? 520.0 : 680.0;
    final minPanelWidth = compact ? 360.0 : 460.0;
    final widthRatio = compact ? 0.40 : 0.42;
    final resolvedWidth = math.min(
      width.clamp(minPanelWidth, maxPanelWidth),
      math.min(
        availableWidth - 8,
        math.max(minPanelWidth, availableWidth * widthRatio),
      ),
    );

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
                onTap: barrierDismissible
                    ? () => Navigator.of(context).maybePop()
                    : null,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 3.8, sigmaY: 3.8),
                    child: Container(
                      color: const Color(0xFF0F172A).withOpacity(0.105),
                    ),
                  ),
                ),
              ),
            ),

            // Clave:
            // right: 0, top: 0, bottom: 0.
            // El panel queda en la derecha, donde está el detalle de ventas.
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              right: rightOffset,
              width: resolvedWidth,
              child: AppSideSheet(
                icon: icon,
                title: title,
                subtitle: subtitle,
                width: resolvedWidth,
                footer: footer,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
