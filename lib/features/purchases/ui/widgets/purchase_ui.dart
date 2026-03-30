import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

const EdgeInsets kPurchasePagePadding = EdgeInsets.fromLTRB(12, 12, 12, 24);

BoxDecoration purchaseSectionDecoration(
  BuildContext context, {
  bool highlighted = false,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  return BoxDecoration(
    color: highlighted
        ? Color.alphaBlend(
            AppColors.brandBlue.withOpacity(0.035),
            scheme.surface,
          )
        : scheme.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: scheme.outlineVariant.withOpacity(0.52)),
    boxShadow: [
      BoxShadow(
        color: theme.shadowColor.withOpacity(highlighted ? 0.07 : 0.045),
        blurRadius: highlighted ? 18 : 12,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

class PurchaseSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlighted;

  const PurchaseSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: purchaseSectionDecoration(context, highlighted: highlighted),
      child: Padding(padding: padding, child: child),
    );
  }
}

class PurchaseHeroCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Widget> stats;

  const PurchaseHeroCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.stats = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.brandBlueDark,
            Color.alphaBlend(
              AppColors.brandBlue.withOpacity(0.9),
              AppColors.brandBlueDark,
            ),
            AppColors.brandBlue,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlueDark.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Text(
                    eyebrow.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withOpacity(0.92),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.78),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: stats),
            ],
          ],
        ),
      ),
    );
  }
}

class PurchaseMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const PurchaseMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withOpacity(0.86)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withOpacity(0.68),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PurchaseStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const PurchaseStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class PurchaseFactTile extends StatelessWidget {
  final String label;
  final String value;

  const PurchaseFactTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
