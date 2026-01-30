import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../errors/app_exception.dart';
import '../theme/app_status_theme.dart';
import '../theme/color_utils.dart';

class AppErrorPage extends StatefulWidget {
  const AppErrorPage({
    super.key,
    required this.exception,
    this.onRetry,
  });

  final AppException exception;
  final VoidCallback? onRetry;

  @override
  State<AppErrorPage> createState() => _AppErrorPageState();
}

class _AppErrorPageState extends State<AppErrorPage> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final ex = widget.exception;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final cardBg = scheme.surface;
    final cardFg = ColorUtils.ensureReadableColor(scheme.onSurface, cardBg);
    final errorColor = status?.error ?? scheme.error;
    final linkColor = scheme.primary;

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
                          'Ups… ocurrió un problema',
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
                        if (kDebugMode) ...[
                          const SizedBox(height: AppSizes.spaceM),
                          InkWell(
                            onTap: () =>
                                setState(() => _showDetails = !_showDetails),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _showDetails
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                  color: linkColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _showDetails
                                      ? 'Ocultar detalles'
                                      : 'Ver detalles',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: linkColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_showDetails) ...[
                            const SizedBox(height: AppSizes.spaceS),
                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.all(AppSizes.paddingM),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius:
                                    BorderRadius.circular(AppSizes.radiusM),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: SelectableText(
                                [
                                  ex.messageDev,
                                  if (ex.stackTrace != null)
                                    '\n\n${ex.stackTrace}',
                                ].join(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: scheme.onSurface.withOpacity(0.85),
                                ),
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: AppSizes.spaceL),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  Navigator.of(context).maybePop(),
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
