import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/bootstrap/bootstrap_recovery_dialog.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../settings/providers/business_settings_provider.dart';

/// Pantalla de splash (carga inicial)
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootstrapProvider).snapshot;
    final businessSettings = ref.watch(businessSettingsProvider);
    final brandName = businessSettings.businessName.isNotEmpty
        ? businessSettings.businessName
        : 'FULLPOS';
    final logoPath = businessSettings.logoPath;
    final hasLogo = logoPath != null && File(logoPath).existsSync();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: ColoredBox(
        color: Colors.white,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withOpacity(0.12),
                          blurRadius: 28,
                          spreadRadius: 2,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: hasLogo
                          ? Image.file(File(logoPath!), fit: BoxFit.cover)
                          : Icon(
                              Icons.storefront,
                              size: 72,
                              color: scheme.primary,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceL),
                  Text(
                    brandName,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.spaceXS),
                  Text(
                    'Software punto de ventas',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withOpacity(0.72),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.spaceXL * 2),
                  if (boot.status == BootStatus.error) ...[
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 46,
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
                    CircularProgressIndicator(color: scheme.primary),
                    const SizedBox(height: AppSizes.spaceL),
                    Text(
                      boot.message.isNotEmpty ? boot.message : 'Iniciando...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withOpacity(0.72),
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
