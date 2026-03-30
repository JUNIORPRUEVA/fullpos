import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import 'widgets/purchase_ui.dart';

class PurchaseModeSelectorPage extends StatelessWidget {
  const PurchaseModeSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        padding: kPurchasePagePadding,
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final contentWidth = viewportConstraints.maxWidth > 1080
                ? 1080.0
                : viewportConstraints.maxWidth;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      const PurchaseHeroCard(
                        eyebrow: 'Centro de compras',
                        title: 'Escoge el flujo de abastecimiento según la operación.',
                        subtitle:
                            'Compra manual para ejecución rápida, automática para reposición guiada y registro de órdenes para seguimiento y recepción.',
                        stats: [
                          PurchaseMetricTile(
                            label: 'Flujos',
                            value: '3 modos',
                            icon: Icons.grid_view_rounded,
                          ),
                          PurchaseMetricTile(
                            label: 'Objetivo',
                            value: 'Operación compacta',
                            icon: Icons.tune_rounded,
                          ),
                          PurchaseMetricTile(
                            label: 'Estilo',
                            value: 'CRM SaaS',
                            icon: Icons.auto_awesome_rounded,
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _PurchaseModeActionButton(
                          icon: Icons.playlist_add,
                          title: 'Compra Manual',
                          subtitle: 'Catálogo + ticket manual',
                          onTap: () => context.go('/purchases/manual'),
                        ),
                        _PurchaseModeActionButton(
                          icon: Icons.auto_awesome,
                          title: 'Compra Automática',
                          subtitle: 'Sugerencias por inventario',
                          onTap: () => context.go('/purchases/auto'),
                        ),
                        _PurchaseModeActionButton(
                          icon: Icons.history,
                          title: 'Registro de Órdenes',
                          subtitle: 'Listado y seguimiento',
                          onTap: () => context.go('/purchases/orders'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PurchaseModeActionButton extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PurchaseModeActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_PurchaseModeActionButton> createState() =>
      _PurchaseModeActionButtonState();
}

class _PurchaseModeActionButtonState extends State<_PurchaseModeActionButton> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (!mounted || _hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: 320,
        height: 148,
        decoration: BoxDecoration(
          color: _hovered
              ? Color.alphaBlend(
                  AppColors.brandBlue.withOpacity(0.03),
                  scheme.surface,
                )
              : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withOpacity(_hovered ? 0.72 : 0.52),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(_hovered ? 0.08 : 0.045),
              blurRadius: _hovered ? 18 : 10,
              offset: Offset(0, _hovered ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.brandBlue.withOpacity(
                                _hovered ? 0.16 : 0.09,
                              ),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              widget.icon,
                              color: AppColors.brandBlueDark,
                              size: 20,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textDarkSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Abrir flujo',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.brandBlue,
                      fontWeight: FontWeight.w800,
                    ),
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
