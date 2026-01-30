import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../errors/app_exception.dart';
import '../theme/app_status_theme.dart';

class AppErrorDialog extends StatefulWidget {
  const AppErrorDialog({super.key, required this.exception, this.onRetry});

  final AppException exception;
  final VoidCallback? onRetry;

  static Future<void> show(
    BuildContext context, {
    required AppException exception,
    VoidCallback? onRetry,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppErrorDialog(exception: exception, onRetry: onRetry),
    );
  }

  @override
  State<AppErrorDialog> createState() => _AppErrorDialogState();
}

class _AppErrorDialogState extends State<AppErrorDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final ex = widget.exception;
    final maxContentHeight = MediaQuery.sizeOf(context).height * 0.6;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final errorColor = status?.error ?? scheme.error;
    final linkColor = scheme.primary;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
      ),
      title: Row(
        children: [
          Icon(Icons.error_outline, color: errorColor),
          const SizedBox(width: AppSizes.spaceM),
          Expanded(
            child: Text(
              'Ups… ocurrió un problema',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxContentHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ex.messageUser,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: AppSizes.spaceM),
                InkWell(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  child: Row(
                    children: [
                      Icon(
                        _showDetails ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: linkColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showDetails ? 'Ocultar detalles' : 'Ver detalles',
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
                    padding: const EdgeInsets.all(AppSizes.paddingM),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: SelectableText(
                      [
                        ex.messageDev,
                        if (ex.stackTrace != null) '\n\n${ex.stackTrace}',
                      ].join(),
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Cerrar'),
        ),
        if (widget.onRetry != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).maybePop();
              widget.onRetry?.call();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
      ],
    );
  }
}
