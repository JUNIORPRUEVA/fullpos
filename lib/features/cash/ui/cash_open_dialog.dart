import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/theme/app_gradient_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../data/operation_flow_service.dart';
import '../providers/cash_providers.dart';

/// Diálogo para abrir turno (compatibilidad con flujo legacy de caja).
class CashOpenDialog extends ConsumerStatefulWidget {
  const CashOpenDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CashOpenDialog(),
    );
  }

  @override
  ConsumerState<CashOpenDialog> createState() => _CashOpenDialogState();
}

class _CashOpenDialogState extends ConsumerState<CashOpenDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '0.00');
  final _noteController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _openCash() async {
    final formState = _formKey.currentState;
    if (formState == null) return;
    if (!formState.validate()) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.openShift,
      resourceType: 'cash_session',
      resourceId: 'new',
      reason: 'Abrir turno',
    );
    if (!authorized || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
      await OperationFlowService.openShiftForCurrentUser(openingAmount: amount);
      await ref.read(cashSessionControllerProvider.notifier).refresh();

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Turno abierto con \$${amount.toStringAsFixed(2)}'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _openCash,
          module: 'cash/open',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;

    const targetWidth = 500.0;
    const targetHeight = 460.0;
    final safeWidth = (screenSize.width - 48).clamp(320.0, 1200.0);
    final safeHeight = (screenSize.height - viewInsets.vertical - 48).clamp(
      320.0,
      1200.0,
    );
    final dialogWidth = targetWidth.clamp(320.0, safeWidth);
    final dialogHeight = targetHeight.clamp(320.0, safeHeight);

    final gradientTheme = theme.extension<AppGradientTheme>();
    final headerGradient =
        gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [scheme.primary, scheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    final headerMid = gradientTheme?.mid ?? scheme.primaryContainer;
    final headerText = ColorUtils.ensureReadableColor(
      scheme.onPrimary,
      headerMid,
    );

    final fieldFill = scheme.surfaceVariant.withOpacity(0.35);
    final fieldBorder = scheme.outlineVariant.withOpacity(0.55);
    Color readableOn(Color bg) => ColorUtils.readableTextColor(bg);

    return DialogKeyboardShortcuts(
      onSubmit: _isLoading ? null : _openCash,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: (screenSize.width * 0.06).clamp(16.0, 48.0),
          vertical: (screenSize.height * 0.06).clamp(16.0, 48.0),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: dialogHeight,
            minWidth: 320,
            minHeight: 320,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withOpacity(0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
                  decoration: BoxDecoration(gradient: headerGradient),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: headerText.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: headerText.withOpacity(0.18),
                          ),
                        ),
                        child: Icon(
                          Icons.lock_open_outlined,
                          color: headerText,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Abrir turno',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: headerText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Iniciar tu turno para registrar ventas y movimientos',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: headerText.withOpacity(0.82),
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: headerText),
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Monto inicial turno',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _amountController,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'),
                              ),
                            ],
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurface,
                              height: 1.0,
                            ),
                            decoration: InputDecoration(
                              prefixText: '\$ ',
                              prefixStyle: theme.textTheme.titleLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                              ),
                              filled: true,
                              fillColor: fieldFill,
                              helperText: 'Ejemplo: 1000.00',
                              helperStyle: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: fieldBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: fieldBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: scheme.primary,
                                  width: 1.4,
                                ),
                              ),
                            ),
                            validator: (value) {
                              final raw = value?.trim() ?? '';
                              // Permite abrir caja con monto vacío (se interpreta como 0).
                              if (raw.isEmpty) return null;

                              final amount = double.tryParse(raw);
                              if (amount == null || amount < 0) {
                                return 'Monto invalido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Nota (opcional)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Flexible(
                            child: TextFormField(
                              controller: _noteController,
                              maxLines: 3,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Ej: Apertura de turno manana',
                                hintStyle: TextStyle(
                                  color: scheme.onSurfaceVariant.withOpacity(
                                    0.8,
                                  ),
                                ),
                                filled: true,
                                fillColor: fieldFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: fieldBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: fieldBorder),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceVariant.withOpacity(0.25),
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withOpacity(0.55),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.onSurface,
                            side: BorderSide(color: scheme.outlineVariant),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _openCash,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: readableOn(scheme.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isLoading
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      readableOn(scheme.primary),
                                    ),
                                  ),
                                )
                              : const Icon(Icons.lock_open, size: 18),
                          label: const Text(
                            'Abrir caja',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
