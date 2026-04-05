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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.98),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSoft.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        hoverColor: AppColors.lightBlueHover.withOpacity(0.6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boundedHeight =
                constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
            final h = boundedHeight ? constraints.maxHeight : 120.0;

            // Ajustes para evitar overflow vertical por redondeo de pixels
            // cuando el Grid asigna alturas "justas".
            final compact = h < 112;
            final horizontalPadding = compact ? 12.0 : 14.0;
            final verticalPadding = compact ? 8.0 : 12.0;
            final iconSize = compact ? 16.0 : 18.0;
            final iconPadding = compact ? 6.0 : 8.0;
            final valueFont = compact ? 20.0 : 21.0;
            final titleFont = compact ? 10.0 : 11.0;
            final gap1 = compact ? 4.0 : 7.0;
            final gap2 = compact ? 2.0 : 3.0;

            final valueText = Align(
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
            );

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
                          color: color.withOpacity(0.11),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: iconSize),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: titleFont,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            fontFamily: 'Inter',
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.arrow_forward_ios,
                          size: compact ? 10 : 12,
                          color: mutedText,
                        ),
                    ],
                  ),
                  SizedBox(height: gap1),

                  // En Grid (altura acotada) dejamos que el valor se adapte al
                  // espacio restante para evitar overflow vertical.
                  if (boundedHeight)
                    Flexible(child: valueText)
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: compact ? 24 : 28),
                      child: valueText,
                    ),
                  SizedBox(height: gap2),
                  Container(
                    width: double.infinity,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.42,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
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
