import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../settings/ui/training/training_page.dart';
import 'authorizations_page.dart';
import 'cash_drawer_settings_page.dart';
import 'scanner_settings_page.dart';

/// Página de Herramientas
class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final tools = <_ToolItem>[
      _ToolItem(
        icon: Icons.menu_book,
        title: 'Manual y entrenamiento',
        subtitle: 'Guías completas, estreno y respaldo',
        color: scheme.secondary,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TrainingPage())),
      ),
      _ToolItem(
        icon: Icons.verified_user_outlined,
        title: 'Autorizaciones',
        subtitle: 'Auditoria de permisos',
        color: scheme.primary,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AuthorizationsPage())),
      ),
      _ToolItem(
        icon: Icons.description_outlined,
        title: 'NCF',
        subtitle: 'Comprobantes fiscales',
        color: scheme.tertiary,
        onTap: () => context.go('/ncf'),
      ),
      _ToolItem(
        icon: Icons.qr_code_scanner_rounded,
        title: 'Lector',
        subtitle: 'Configurar escáner',
        color: scheme.primary,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ScannerSettingsPage())),
      ),
      _ToolItem(
        icon: Icons.point_of_sale,
        title: 'Caja registradora',
        subtitle: 'Apertura automática al cobrar',
        color: scheme.tertiary,
        onTap: () => Navigator.of(
          context,
        ).push(
          MaterialPageRoute(builder: (_) => const CashDrawerSettingsPage()),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Herramientas',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        surfaceTintColor: scheme.surface,
        elevation: 0,
        toolbarHeight: 48,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = (width * 0.04).clamp(12.0, 28.0);
          final verticalPadding = (width * 0.02).clamp(10.0, 20.0);
          final gridSpacing = (width * 0.012).clamp(10.0, 16.0);

          int crossAxisCount;
          if (width < 520) {
            crossAxisCount = 1;
          } else if (width < 760) {
            crossAxisCount = 2;
          } else if (width < 980) {
            crossAxisCount = 3;
          } else if (width < 1240) {
            crossAxisCount = 4;
          } else {
            crossAxisCount = 5;
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  verticalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: gridSpacing,
                        crossAxisSpacing: gridSpacing,
                        childAspectRatio: 1.6,
                        children: [
                          for (final tool in tools) _ToolCard(tool: tool),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ToolItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _ToolCard extends StatefulWidget {
  final _ToolItem tool;

  const _ToolCard({required this.tool});

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = scheme.surface;
    final borderColor = scheme.outlineVariant.withOpacity(isDark ? 0.42 : 0.28);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
        transformAlignment: Alignment.center,
        child: Card(
          color: cardBg,
          elevation: 0,
          shadowColor: scheme.shadow.withOpacity(isDark ? 0.20 : 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _isHovered
                  ? widget.tool.color.withOpacity(isDark ? 0.45 : 0.35)
                  : borderColor,
              width: _isHovered ? 1.4 : 1.0,
            ),
          ),
          child: InkWell(
            onTap: widget.tool.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceVariant.withOpacity(
                        isDark ? 0.28 : 0.55,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor.withOpacity(0.9)),
                    ),
                    child: Icon(
                      widget.tool.icon,
                      size: 22,
                      color: widget.tool.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.tool.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.tool.subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
