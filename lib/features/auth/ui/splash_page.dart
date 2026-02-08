import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

/// Pantalla de splash (carga inicial)
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootstrapProvider).snapshot;
    final brandName = FullposBrandTheme.appName;

    return Scaffold(
      backgroundColor: FullposBrandTheme.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: FullposBrandTheme.backgroundGradient,
        ),
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
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(0.35),
                          blurRadius: 36,
                          spreadRadius: 8,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        FullposBrandTheme.logoAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                              child: Icon(
                                Icons.storefront,
                                size: 72,
                                color: AppColors.gold,
                              ),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceL),
                  Text(
                    brandName,
                    style: const TextStyle(
                      color: AppColors.textLight,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.spaceXS),
                  Text(
                    'Software punto de ventas',
                    style: TextStyle(
                      color: AppColors.textLight.withOpacity(0.86),
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
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSizes.spaceL),
                    FilledButton.icon(
                      onPressed: () => ref.read(appBootstrapProvider).retry(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ] else ...[
                    const CircularProgressIndicator(color: AppColors.gold),
                    const SizedBox(height: AppSizes.spaceL),
                    Text(
                      boot.message.isNotEmpty ? boot.message : 'Iniciando...',
                      style: const TextStyle(
                        color: AppColors.textMuted,
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
