import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/bootstrap/bootstrap_recovery_dialog.dart';
import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFloat;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    _logoFloat = Tween<double>(begin: -4, end: 6).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(appBootstrapProvider).snapshot;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF7FAFF),
              Color(0xFFEEF4FF),
            ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -110,
              right: -70,
              child: _SplashGlow(size: 280, color: Color(0x261A56DB)),
            ),
            const Positioned(
              bottom: -140,
              left: -90,
              child: _SplashGlow(size: 320, color: Color(0x1438BDF8)),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _AnimatedLogo(
                        controller: _controller,
                        logoFade: _logoFade,
                        logoScale: _logoScale,
                        logoFloat: _logoFloat,
                      ),
                      const SizedBox(height: 28),
                      if (boot.status == BootStatus.error) ...[
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 44,
                        ),
                        const SizedBox(height: AppSizes.spaceM),
                        Text(
                          boot.errorMessage ?? 'No se pudo iniciar la aplicación.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withOpacity(0.78),
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSizes.spaceL),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: () =>
                                  ref.read(appBootstrapProvider).retry(),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                final msg =
                                    boot.errorMessage ??
                                    'No se pudo iniciar la aplicación.';
                                BootstrapRecoveryDialog.show(
                                  context,
                                  errorMessage: msg,
                                  onRetry: () =>
                                      ref.read(appBootstrapProvider).retry(),
                                );
                              },
                              icon: const Icon(Icons.tune),
                              label: const Text('Opciones'),
                            ),
                          ],
                        ),
                      ] else ...[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          boot.message.isNotEmpty ? boot.message : 'Iniciando...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF64748B),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedLogo extends StatelessWidget {
  const _AnimatedLogo({
    required this.controller,
    required this.logoFade,
    required this.logoScale,
    required this.logoFloat,
  });

  final AnimationController controller;
  final Animation<double> logoFade;
  final Animation<double> logoScale;
  final Animation<double> logoFloat;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final logoSize = width < 560 ? 110.0 : 135.0;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return FadeTransition(
          opacity: logoFade,
          child: Transform.translate(
            offset: Offset(0, logoFloat.value),
            child: ScaleTransition(
              scale: logoScale,
              child: SizedBox(
                width: logoSize,
                height: logoSize,
                child: Image.asset(
                  FullposBrandTheme.logoAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SplashGlow extends StatelessWidget {
  const _SplashGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withOpacity(0.26),
              Colors.transparent,
            ],
            stops: const [0.0, 0.38, 1.0],
          ),
        ),
      ),
    );
  }
}
