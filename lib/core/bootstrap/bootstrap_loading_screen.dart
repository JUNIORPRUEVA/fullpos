import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/business_settings_provider.dart';
import '../constants/app_sizes.dart';
import '../theme/color_utils.dart';

class BootstrapLoadingScreen extends ConsumerWidget {
  final String message;

  const BootstrapLoadingScreen({super.key, this.message = 'Iniciando...'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(businessSettingsProvider);
    final businessName = settings.businessName.isNotEmpty
        ? settings.businessName
        : 'FULLPOS';
    final logoPath = settings.logoPath;
    final hasLogo = logoPath != null && File(logoPath).existsSync();
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
        child: Center(
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
                      ? Image.file(File(logoPath!), fit: BoxFit.cover)
                      : Center(
                          child: Icon(
                            Icons.storefront,
                            size: 72,
                            color: accent,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppSizes.spaceL),
              Text(
                '$businessName POS',
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
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onBackground.withOpacity(0.75),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
