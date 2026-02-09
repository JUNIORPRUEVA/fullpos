import 'dart:io';

import 'package:flutter/material.dart';

import '../../features/settings/data/business_settings_repository.dart';
import '../constants/app_sizes.dart';
import '../theme/app_gradient_theme.dart';
import '../theme/color_utils.dart';

class BootstrapLoadingScreen extends StatefulWidget {
  final String message;

  const BootstrapLoadingScreen({super.key, this.message = 'Iniciando...'});

  @override
  State<BootstrapLoadingScreen> createState() => _BootstrapLoadingScreenState();
}

class _BootstrapLoadingScreenState extends State<BootstrapLoadingScreen> {
  late final Future<_BootstrapBranding> _future;

  @override
  void initState() {
    super.initState();
    // Nunca bloquear el arranque por I/O de BD en el splash.
    // Si la BD está en recuperación/locked, este timeout evita que la UI se congele.
    _future = _load().timeout(
      const Duration(seconds: 1),
      onTimeout: () => const _BootstrapBranding(
        businessName: 'FULLPOS',
        logoPath: null,
      ),
    );
  }

  Future<_BootstrapBranding> _load() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      final name = settings.businessName.isNotEmpty
          ? settings.businessName
          : 'FULLPOS';
      final logoPath = settings.logoPath;
      final hasLogo = logoPath != null && File(logoPath).existsSync();
      return _BootstrapBranding(
        businessName: name,
        logoPath: hasLogo ? logoPath : null,
      );
    } catch (_) {
      return const _BootstrapBranding(businessName: 'FULLPOS', logoPath: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradientTheme = theme.extension<AppGradientTheme>();
    // Fallback azul degradado de la marca
    final fallbackGradient = LinearGradient(
      colors: [
        const Color(0xFF1565C0), // Azul Marca inicio
        const Color(0xFF1976D2), // Azul Marca medio
        const Color(0xFF2196F3), // Azul Marca final
      ],
      stops: const [0.0, 0.5, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final backgroundGradient =
        gradientTheme?.backgroundGradient ?? fallbackGradient;
    final gradientMid = gradientTheme?.mid ?? scheme.surface;
    final accent = ColorUtils.ensureReadableColor(scheme.primary, gradientMid);
    final onBackground = ColorUtils.ensureReadableColor(
      scheme.onSurface,
      gradientMid,
    );
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: FutureBuilder<_BootstrapBranding>(
          future: _future,
          builder: (context, snapshot) {
            final branding =
                snapshot.data ??
                const _BootstrapBranding(
                  businessName: 'FULLPOS',
                  logoPath: null,
                );
            final hasLogo = branding.logoPath != null;

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: hasLogo
                          ? Image.file(
                              File(branding.logoPath!),
                              fit: BoxFit.cover,
                            )
                          : Image.asset(
                              'assets/imagen/lonchericon.png',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                    child: Icon(
                                      Icons.storefront,
                                      size: 72,
                                      color: accent,
                                    ),
                                  ),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceL),
                  Text(
                    '${branding.businessName} POS',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.spaceXL * 2),
                  CircularProgressIndicator(color: accent),
                  const SizedBox(height: AppSizes.spaceL),
                  Text(
                    widget.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onBackground.withOpacity(0.75),
                      fontSize: 16,
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

class _BootstrapBranding {
  final String businessName;
  final String? logoPath;

  const _BootstrapBranding({
    required this.businessName,
    required this.logoPath,
  });
}
