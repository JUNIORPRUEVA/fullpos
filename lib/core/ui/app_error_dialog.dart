import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/app_exception.dart';
import '../errors/error_handler.dart';
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

  String _buildDebugText(AppException ex) {
    return [
      ex.messageDev,
      if (ex.stackTrace != null) '\n\n${ex.stackTrace}',
    ].join();
  }

  Future<void> _copyDetails(AppException ex) async {
    final text = _buildDebugText(ex).trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    final feedbackContext =
        ErrorHandler.navigatorKey.currentState?.overlay?.context ??
        ErrorHandler.navigatorKey.currentContext;
    if (feedbackContext == null) {
      return;
    }

    ScaffoldMessenger.maybeOf(feedbackContext)?.showSnackBar(
      const SnackBar(
        content: Text('Detalles copiados al portapapeles'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exception;
    final maxContentHeight = MediaQuery.sizeOf(context).height * 0.35;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final errorColor = status?.error ?? scheme.error;
    final linkColor = scheme.primary;
    final hasDevDetails =
        ex.messageDev.trim().isNotEmpty || ex.stackTrace != null;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        key: const ValueKey('app-error-dialog-card'),
        constraints: BoxConstraints(maxWidth: 340, maxHeight: maxContentHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: errorColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ocurrió un problema',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).maybePop(),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                ex.messageUser,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              if (kDebugMode || hasDevDetails) ...[
                const SizedBox(height: 7),
                InkWell(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showDetails ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: linkColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showDetails ? 'Ocultar detalles' : 'Ver detalles',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: linkColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showDetails) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: hasDevDetails ? () => _copyDetails(ex) : null,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('Copiar detalles'),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: SelectableText(
                          _buildDebugText(ex),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (widget.onRetry != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      Navigator.of(context).maybePop();
                      widget.onRetry?.call();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text(
                      'Reintentar',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
