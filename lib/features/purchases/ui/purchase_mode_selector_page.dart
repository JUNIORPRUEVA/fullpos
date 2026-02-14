import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_gradient_theme.dart';

class PurchaseModeSelectorPage extends StatelessWidget {
  const PurchaseModeSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradientTheme = theme.extension<AppGradientTheme>();
    final headerGradient =
        gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [scheme.surface, scheme.surfaceVariant, scheme.primaryContainer],
          stops: const [0.0, 0.65, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    Widget card({
      required IconData icon,
      required String title,
      required String desc,
      required VoidCallback onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusXL),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingL),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.primary.withOpacity(0.25)),
                  ),
                  child: Icon(icon, color: scheme.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        desc,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withOpacity(0.72),
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurface.withOpacity(0.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Compras',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        toolbarHeight: 48,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.paddingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.paddingL),
              decoration: BoxDecoration(
                gradient: headerGradient,
                borderRadius: BorderRadius.circular(AppSizes.radiusXL),
                border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecciona un tipo de compra',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Manual (catálogo + ticket) o Automática (sugerencias + ticket).',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withOpacity(0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 980;
                final children = [
                  card(
                    icon: Icons.playlist_add,
                    title: 'Compra Manual',
                    desc:
                        'Elige productos del catálogo y arma tu orden con ticket fijo.',
                    onTap: () => context.go('/purchases/manual'),
                  ),
                  card(
                    icon: Icons.auto_awesome,
                    title: 'Compra Automática',
                    desc:
                        'Genera sugerencias por reposición y conviértelas en una orden.',
                    onTap: () => context.go('/purchases/auto'),
                  ),
                  card(
                    icon: Icons.history,
                    title: 'Registro de Órdenes',
                    desc:
                        'Consulta historial, abre PDF, recibe órdenes y duplica.',
                    onTap: () => context.go('/purchases/orders'),
                  ),
                ];

                if (!isWide) {
                  return Column(
                    children: [
                      for (final w in children) ...[w, const SizedBox(height: 12)],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: children[0]),
                    const SizedBox(width: 12),
                    Expanded(child: children[1]),
                    const SizedBox(width: 12),
                    Expanded(child: children[2]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
