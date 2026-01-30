import 'package:flutter/material.dart';

import '../../../../core/security/security_config.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/theme/color_utils.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

class BarcodeInfoDialog extends StatelessWidget {
  final SecurityConfig? config;
  final String? terminalId;

  const BarcodeInfoDialog({
    super.key,
    this.config,
    this.terminalId,
  });

  String _escapeSuffix(String value) {
    if (value.isEmpty) return '(vacio)';
    return value
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );
    final headerColor = scheme.primary;
    final headerForeground = ColorUtils.readableTextColor(headerColor);
    final effectiveConfig = config;
    final isEnabled = effectiveConfig?.scannerEnabled ?? false;
    final prefix = (effectiveConfig?.scannerPrefix ?? '').trim();
    final suffix = _escapeSuffix(effectiveConfig?.scannerSuffix ?? '\n');
    final timeout = effectiveConfig?.scannerTimeoutMs;
    final terminal = terminalId?.trim().isNotEmpty == true
        ? terminalId!
        : 'No asignada';

    return DialogKeyboardShortcuts(
      onSubmit: () => Navigator.of(context).pop(),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.barcode_reader, color: headerForeground, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lector de codigo de barras',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: headerForeground,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: headerForeground),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: status.info.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: status.info.withOpacity(0.4),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: status.info,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Conecta el lector y escanea el codigo en la pantalla de ventas. '
                              'El lector debe funcionar como teclado y enviar Enter al final. '
                              'Configura esto en Ajustes > Seguridad y Overrides > Scanner.',
                              style: TextStyle(
                                fontSize: 16,
                                color: scheme.onSurface,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estado y configuracion',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Terminal: $terminal'),
                          Text('Scanner: ${isEnabled ? 'Habilitado' : 'Deshabilitado'}'),
                          Text('Prefijo: ${prefix.isEmpty ? 'Ninguno' : prefix}'),
                          Text('Sufijo: $suffix'),
                          if (timeout != null) Text('Timeout: ${timeout}ms'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: const Text(
                      'Cerrar',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
