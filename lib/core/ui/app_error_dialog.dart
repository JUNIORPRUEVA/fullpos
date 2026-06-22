import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      barrierDismissible: true,
      builder: (_) => AppErrorDialog(exception: exception, onRetry: onRetry),
    );
  }

  @override
  State<AppErrorDialog> createState() => _AppErrorDialogState();
}

class _AppErrorDialogState extends State<AppErrorDialog> {
  bool _showDetails = false;
  bool _copied = false;

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
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exception;
    final maxContentHeight = MediaQuery.sizeOf(context).height * 0.30;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final errorColor = status?.error ?? scheme.error;
    final linkColor = scheme.primary;
    final hasDevDetails =
        ex.messageDev.trim().isNotEmpty || ex.stackTrace != null;

    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          key: const ValueKey('app-error-dialog-card'),
          constraints: BoxConstraints(
            maxWidth: 320,
            maxHeight: maxContentHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
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
                    fontSize: 11.8,
                    height: 1.32,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (kDebugMode || hasDevDetails) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showDetails = !_showDetails),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showDetails
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: linkColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showDetails
                                  ? 'Ocultar detalles'
                                  : 'Ver detalles',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: linkColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_showDetails) ...[
                    const SizedBox(height: 6),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: hasDevDetails
                            ? () => _copyDetails(ex)
                            : null,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        icon: Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 14,
                        ),
                        label: Text(_copied ? 'Copiado' : 'Copiar soporte'),
                      ),
                    ),
                    const SizedBox(width: 7),
                    if (widget.onRetry != null) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).maybePop();
                          widget.onRetry?.call();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Reintentar'),
                      ),
                      const SizedBox(width: 7),
                    ],
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Ignorar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
