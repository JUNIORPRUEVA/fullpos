import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_sizes.dart';
import '../theme/app_gradient_theme.dart';
import '../theme/color_utils.dart';
import '../../features/settings/providers/business_settings_provider.dart';

class BrandedLoadingView extends ConsumerWidget {
  final String message;
  final bool fullScreen;

  const BrandedLoadingView({
    super.key,
    this.message = 'Cargando...',
    this.fullScreen = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradientTheme = theme.extension<AppGradientTheme>();
    final fallbackGradient = LinearGradient(
      colors: [scheme.surface, scheme.primaryContainer],
      stops: const [0.0, 1.0],
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
    final business = ref.watch(businessSettingsProvider);
    final brandName = 'FULLPOS';
    final businessName = business.businessName.isNotEmpty
        ? business.businessName
        : brandName;
    final showBusinessTag =
        businessName.trim().isNotEmpty && businessName != brandName;

    final content = Center(
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
              child: Image.asset(
                'assets/imagen/lonchericon.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(
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
            brandName,
            style: theme.textTheme.headlineLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (showBusinessTag) ...[
            const SizedBox(height: AppSizes.spaceXS),
            Text(
              'para $businessName',
              style: TextStyle(
                color: onBackground.withOpacity(0.82),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSizes.spaceXL * 2),
          CircularProgressIndicator(color: accent),
          const SizedBox(height: AppSizes.spaceL),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onBackground.withOpacity(0.72),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );

    if (!fullScreen) {
      return Material(color: theme.scaffoldBackgroundColor, child: content);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: content,
      ),
    );
  }
}
