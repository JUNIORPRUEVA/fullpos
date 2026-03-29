import 'dart:io';

import 'package:flutter/material.dart';

import '../../features/settings/data/business_settings_repository.dart';
import '../constants/app_sizes.dart';
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
    final backgroundColor = Colors.white;
    final accent = ColorUtils.ensureReadableColor(scheme.primary, backgroundColor);
    final onBackground = ColorUtils.ensureReadableColor(
      scheme.onSurface,
      backgroundColor,
    );
    return Scaffold(
      backgroundColor: backgroundColor,
      body: ColoredBox(
        color: backgroundColor,
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.12),
                          blurRadius: 24,
                          spreadRadius: 1,
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
