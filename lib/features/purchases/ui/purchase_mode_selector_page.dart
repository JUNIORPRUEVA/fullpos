import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_gradient_theme.dart';

class PurchaseModeSelectorPage extends StatelessWidget {
  const PurchaseModeSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradientTheme = theme.extension<AppGradientTheme>();

    final headerGradient =
        gradientTheme?.backgroundGradient ??
        const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF3F7FF), Color(0xFFEAF2FF)],
          stops: [0.0, 0.62, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    const cardGradient = LinearGradient(
      colors: [AppColors.brandBlueDark, AppColors.brandBlue],
      stops: [0.0, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          'Compras',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        toolbarHeight: 48,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final contentWidth = viewportConstraints.maxWidth > 1160
                ? 1160.0
                : viewportConstraints.maxWidth;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        gradient: headerGradient,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.surfaceLightBorder.withOpacity(0.75),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withOpacity(0.10),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
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
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Manual (catálogo + ticket), Automática (sugerencias) o Registro de órdenes.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textDarkSecondary.withOpacity(
                                0.86,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 980;

                        final cards = [
                          _PurchaseModeActionCard(
                            icon: Icons.playlist_add,
                            title: 'Compra Manual',
                            desc:
                                'Elige productos del catálogo y arma tu orden con ticket fijo.',
                            gradient: cardGradient,
                            onTap: () => context.go('/purchases/manual'),
                          ),
                          _PurchaseModeActionCard(
                            icon: Icons.auto_awesome,
                            title: 'Compra Automática',
                            desc:
                                'Genera sugerencias por reposición y conviértelas en una orden.',
                            gradient: cardGradient,
                            onTap: () => context.go('/purchases/auto'),
                          ),
                          _PurchaseModeActionCard(
                            icon: Icons.history,
                            title: 'Registro de Órdenes',
                            desc:
                                'Consulta historial, abre PDF, recibe órdenes y duplica.',
                            gradient: cardGradient,
                            onTap: () => context.go('/purchases/orders'),
                          ),
                        ];

                        if (!isWide) {
                          return Column(
                            children: [
                              cards[0],
                              const SizedBox(height: 14),
                              cards[1],
                              const SizedBox(height: 14),
                              cards[2],
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 14),
                            Expanded(child: cards[1]),
                            const SizedBox(width: 14),
                            Expanded(child: cards[2]),
                          ],
                        );
                      },
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

class _PurchaseModeActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Gradient gradient;
  final VoidCallback onTap;

  const _PurchaseModeActionCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_PurchaseModeActionCard> createState() =>
      _PurchaseModeActionCardState();
}

class _PurchaseModeActionCardState extends State<_PurchaseModeActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 178),
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlueDark.withOpacity(
                _hovered ? 0.28 : 0.20,
              ),
              blurRadius: _hovered ? 22 : 16,
              offset: Offset(0, _hovered ? 10 : 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(_hovered ? 0.24 : 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.desc,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.82),
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 17,
                    color: Colors.white.withOpacity(0.72),
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
