import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/business_settings_provider.dart';
import '../constants/app_sizes.dart';
import '../theme/color_utils.dart';
import '../theme/app_gradient_theme.dart';

class BootstrapLoadingScreen extends ConsumerStatefulWidget {
  final String message;

  const BootstrapLoadingScreen({super.key, this.message = 'Iniciando...'});

  @override
  ConsumerState<BootstrapLoadingScreen> createState() =>
      _BootstrapLoadingScreenState();
}

class _BootstrapLoadingScreenState
    extends ConsumerState<BootstrapLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<double> _scaleIn;
  late Animation<double> _logoFloat;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _scaleIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    );
    _logoFloat = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOutSine),
    );
    _animController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(businessSettingsProvider);
    final businessName = settings.businessName.isNotEmpty
        ? settings.businessName
        : 'FULLPOS';
    final logoPath = settings.logoPath;
    final hasLogo = logoPath != null && File(logoPath).existsSync();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = theme.extension<AppGradientTheme>()?.backgroundGradient;
    final accent = ColorUtils.ensureReadableColor(
      scheme.primary,
      Colors.white,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: gradient ??
              LinearGradient(
                colors: [
                  Colors.white,
                  accent.withOpacity(0.04),
                  accent.withOpacity(0.08),
                ],
                stops: const [0.0, 0.6, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- Logo animado ---
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  final floatOffset = Tween<double>(
                    begin: 0.0,
                    end: -6.0,
                  ).transform(_logoFloat.value);
                  return Transform.translate(
                    offset: Offset(0, floatOffset),
                    child: Opacity(
                      opacity: _fadeIn.value,
                      child: Transform.scale(
                        scale: 0.6 + (0.4 * _scaleIn.value),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.15),
                        blurRadius: 32,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: hasLogo
                        ? Image.file(File(logoPath), fit: BoxFit.cover)
                        : Center(
                            child: Icon(
                              Icons.storefront_rounded,
                              size: 64,
                              color: accent,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.spaceL + 4),

              // --- Nombre del negocio ---
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeIn.value,
                    child: child,
                  );
                },
                child: Text(
                  businessName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 4.0,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'POS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: accent.withOpacity(0.5),
                  letterSpacing: 6.0,
                ),
              ),
              const SizedBox(height: AppSizes.spaceXL + 16),

              // --- Loading dots animados ---
              _LoadingDots(color: accent),
              const SizedBox(height: AppSizes.spaceL + 4),

              // --- Mensaje de estado ---
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.6 + (0.4 * _logoFloat.value),
                    child: child,
                  );
                },
                child: Text(
                  widget.message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: accent.withOpacity(0.7),
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tres puntos con animación de rebote estilo "cargando..."
class _LoadingDots extends StatefulWidget {
  final Color color;
  const _LoadingDots({required this.color});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<Animation<double>> _dots;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _dots = List.generate(3, (i) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(i * 0.18, 0.5 + i * 0.18, curve: Curves.easeInOut),
        ),
      );
    });
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final scale = 0.4 + (0.6 * _dots[i].value);
            final opacity = 0.3 + (0.7 * _dots[i].value);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
