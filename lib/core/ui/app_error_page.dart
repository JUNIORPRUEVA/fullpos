import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../errors/app_exception.dart';
import '../theme/app_status_theme.dart';
import '../theme/color_utils.dart';

class AppErrorPage extends StatefulWidget {
  const AppErrorPage({super.key, required this.exception, this.onRetry});

  final AppException exception;
  final VoidCallback? onRetry;

  @override
  State<AppErrorPage> createState() => _AppErrorPageState();
}

class _AppErrorPageState extends State<AppErrorPage> {
  @override
  Widget build(BuildContext context) {
    final ex = widget.exception;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final cardBg = scheme.surface;
    final cardFg = ColorUtils.ensureReadableColor(scheme.onSurface, cardBg);
    final errorColor = status?.error ?? scheme.error;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingXL),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Container(
                    padding: const EdgeInsets.all(AppSizes.paddingXL),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(AppSizes.radiusL),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withOpacity(0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: errorColor, size: 52),
                        const SizedBox(height: AppSizes.spaceM),
                        Text(
                          'No pudimos completar la acción',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cardFg,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSizes.spaceS),
                        Text(
                          ex.messageUser,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.25,
                            color: cardFg.withOpacity(0.85),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSizes.spaceL),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Volver'),
                            ),
                            const SizedBox(width: AppSizes.spaceM),
                            if (widget.onRetry != null)
                              FilledButton.icon(
                                onPressed: widget.onRetry,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
