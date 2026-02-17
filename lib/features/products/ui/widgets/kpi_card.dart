import 'package:flutter/material.dart';
import 'package:fullpos/theme/app_colors.dart';

/// Widget reutilizable para mostrar tarjetas de KPIs - Diseño Corporativo
class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color? bgColor;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.bgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.65);

    return Card(
      elevation: 1,
      shadowColor: scheme.shadow.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderSoft, width: 1),
      ),
      color: scheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: AppColors.lightBlueHover.withOpacity(0.6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 112;
            final horizontalPadding = compact ? 12.0 : 14.0;
            final verticalPadding = compact ? 8.0 : 12.0;
            final iconSize = compact ? 16.0 : 18.0;
            final iconPadding = compact ? 6.0 : 8.0;
            final valueFont = compact ? 20.0 : 22.0;
            final titleFont = compact ? 10.0 : 11.0;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.all(iconPadding),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: iconSize),
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.arrow_forward_ios,
                          size: compact ? 10 : 12,
                          color: mutedText,
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? 4 : 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: compact ? 24 : 28,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: valueFont,
                              fontWeight: FontWeight.w700,
                              color: color,
                              fontFamily: 'Inter',
                              letterSpacing: -0.4,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 1 : 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleFont,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                      fontFamily: 'Inter',
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
