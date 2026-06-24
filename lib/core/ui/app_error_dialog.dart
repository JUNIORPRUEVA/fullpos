import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/app_exception.dart';
import '../theme/app_status_theme.dart';

/// Tipo de error representado con icono y color para el cliente.
const _errorTypeConfig = <AppErrorType, _ErrorConfig>{
  AppErrorType.network: _ErrorConfig(
    icon: Icons.wifi_off_rounded,
    title: 'Sin conexión',
  ),
  AppErrorType.timeout: _ErrorConfig(
    icon: Icons.timer_off_rounded,
    title: 'Tiempo de espera agotado',
  ),
  AppErrorType.database: _ErrorConfig(
    icon: Icons.storage_rounded,
    title: 'Error en la base de datos',
  ),
  AppErrorType.validation: _ErrorConfig(
    icon: Icons.warning_amber_rounded,
    title: 'Datos inválidos',
  ),
  AppErrorType.unauthorized: _ErrorConfig(
    icon: Icons.lock_outline_rounded,
    title: 'Sin autorización',
  ),
  AppErrorType.forbidden: _ErrorConfig(
    icon: Icons.block_rounded,
    title: 'Acceso denegado',
  ),
  AppErrorType.notFound: _ErrorConfig(
    icon: Icons.search_off_rounded,
    title: 'No encontrado',
  ),
  AppErrorType.conflict: _ErrorConfig(
    icon: Icons.swap_horiz_rounded,
    title: 'Conflicto de datos',
  ),
  AppErrorType.server: _ErrorConfig(
    icon: Icons.cloud_off_rounded,
    title: 'Error del servidor',
  ),
  AppErrorType.unknown: _ErrorConfig(
    icon: Icons.error_outline_rounded,
    title: 'No pudimos completar la acción',
  ),
};

class _ErrorConfig {
  final IconData icon;
  final String title;
  const _ErrorConfig({required this.icon, required this.title});
}

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
  bool _copied = false;

  String _buildSupportText(AppException ex) {
    final buf = StringBuffer();
    buf.writeln('=== REPORTE DE ERROR ===');
    buf.writeln('Tipo: ${ex.type.name}');
    if (ex.code != null) buf.writeln('Código: ${ex.code}');
    buf.writeln('');
    buf.writeln('Mensaje: ${ex.messageDev}');
    if (ex.stackTrace != null) {
      buf.writeln('');
      buf.writeln('--- Stack Trace ---');
      buf.writeln(ex.stackTrace.toString());
    }
    return buf.toString();
  }

  Future<void> _copySupportText(AppException ex) async {
    final text = _buildSupportText(ex).trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exception;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final errorColor = status?.error ?? scheme.error;
    final config =
        _errorTypeConfig[ex.type] ?? _errorTypeConfig[AppErrorType.unknown]!;
    final hasDevDetails =
        ex.messageDev.trim().isNotEmpty || ex.stackTrace != null;
    final supportCode = ex.code?.trim();

    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          key: const ValueKey('app-error-dialog-card'),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Icono + Título ──
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: errorColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(config.icon, color: errorColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        config.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
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
                        width: 32,
                        height: 32,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Mensaje para el cliente ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: errorColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: errorColor.withOpacity(0.15)),
                  ),
                  child: Text(
                    ex.messageUser.isNotEmpty
                        ? ex.messageUser
                        : 'No se pudo completar la acción. Intenta nuevamente. Si continúa, contacta a soporte.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                // ── Código de soporte (solo si existe uno útil para soporte) ──
                if (supportCode != null && supportCode.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.tag,
                        size: 13,
                        color: scheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Código de soporte: $supportCode',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // ── Botones ──
                Row(
                  children: [
                    // Copiar para soporte
                    Expanded(
                      child: TextButton.icon(
                        onPressed: hasDevDetails
                            ? () => _copySupportText(ex)
                            : null,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: scheme.onSurface.withOpacity(0.6),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        icon: Icon(
                          _copied
                              ? Icons.check_circle_rounded
                              : Icons.copy_rounded,
                          size: 16,
                        ),
                        label: Text(_copied ? 'Copiado' : 'Copiar soporte'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.onRetry != null) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).maybePop();
                          widget.onRetry?.call();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Reintentar'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Cerrar'),
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
