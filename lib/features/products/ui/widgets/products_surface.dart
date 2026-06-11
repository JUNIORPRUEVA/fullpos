import 'package:flutter/material.dart';

EdgeInsets productsResponsivePagePadding(
  BoxConstraints constraints, {
  double top = 14,
  double bottom = 18,
}) {
  final width = constraints.maxWidth;
  final fraction = width >= 1200 ? 0.80 : (width >= 760 ? 0.90 : 0.95);
  final contentWidth = (width * fraction).clamp(0.0, 1180.0);
  final horizontal = ((width - contentWidth) / 2).clamp(10.0, 96.0);
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}

class ProductsSurface extends StatelessWidget {
  const ProductsSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: scheme.outlineVariant.withOpacity(0.65),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class ProductsSectionHeader extends StatelessWidget {
  const ProductsSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'Inter',
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
  }
}

class ProductsStatChip extends StatelessWidget {
  const ProductsStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: effectiveColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: effectiveColor.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: effectiveColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                  color: scheme.onSurface,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProductsEmptyState extends StatelessWidget {
  const ProductsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 34, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFamily: 'Inter',
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
