import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_repository.dart';
import '../providers/cash_providers.dart';

/// Diálogo para registrar entrada/salida de efectivo
class CashMovementDialog extends ConsumerStatefulWidget {
  final String type; // 'IN' o 'OUT'
  final int sessionId;

  const CashMovementDialog({
    super.key,
    required this.type,
    required this.sessionId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String type,
    required int sessionId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          CashMovementDialog(type: type, sessionId: sessionId),
    );
  }

  @override
  ConsumerState<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends ConsumerState<CashMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isLoading = false;

  bool get isIncome => widget.type == CashMovementType.income;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _saveMovement() async {
    if (!_formKey.currentState!.validate()) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.cashMovement,
      resourceType: 'cash_session',
      resourceId: widget.sessionId.toString(),
      reason: isIncome ? 'Entrada de efectivo' : 'Retiro de efectivo',
    );
    if (!mounted) return;
    if (!authorized) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final amount = double.tryParse(_amountController.text) ?? 0.0;
      final reason = _reasonController.text.trim();
      final userId = await SessionManager.userId() ?? 1;

      if (!isIncome) {
        final summary = await CashRepository.buildSummary(
          sessionId: widget.sessionId,
        );
        final available = summary.expectedCash;

        if (amount > available + 0.009) {
          if (!mounted) return;
          setState(() => _isLoading = false);

          final decision = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Caja sin efectivo suficiente'),
              content: Text(
                'Disponible en caja: RD\$ ${available.toStringAsFixed(2)}\n'
                'Intentas retirar: RD\$ ${amount.toStringAsFixed(2)}\n\n'
                'Ingresa efectivo antes de registrar este retiro.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'add'),
                  child: const Text('Agregar efectivo'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          );

          if (!mounted) return;
          if (decision == 'add') {
            await CashMovementDialog.show(
              context,
              type: CashMovementType.income,
              sessionId: widget.sessionId,
            );
          }

          return;
        }
      }

      await ref
          .read(cashSessionControllerProvider.notifier)
          .addMovement(
            sessionId: widget.sessionId,
            type: widget.type,
            amount: amount,
            reason: reason.isEmpty
                ? (isIncome ? 'Entrada de efectivo' : 'Retiro de efectivo')
                : reason,
            userId: userId,
          );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isIncome
                  ? 'Entrada de \$${amount.toStringAsFixed(2)} registrada'
                  : 'Retiro de \$${amount.toStringAsFixed(2)} registrado',
            ),
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
          onRetry: _saveMovement,
          module: 'cash/movement',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    const targetWidth = 460.0;
    const targetHeight = 440.0;
    final safeWidth = (screenSize.width - 48).clamp(320.0, 1200.0);
    final safeHeight = (screenSize.height - viewInsets.vertical - 48).clamp(
      320.0,
      1200.0,
    );
    final dialogWidth = targetWidth.clamp(320.0, safeWidth);
    final dialogHeight = targetHeight.clamp(320.0, safeHeight);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final primaryColor = isIncome ? scheme.primary : scheme.error;
    final onPrimaryColor = isIncome ? scheme.onPrimary : scheme.onError;
    final title = isIncome ? 'REGISTRAR ENTRADA' : 'REGISTRAR RETIRO';
    final icon = isIncome
        ? Icons.add_circle_outline
        : Icons.remove_circle_outline;

    return DialogKeyboardShortcuts(
      onSubmit: _isLoading ? null : _saveMovement,
      child: Dialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
          minWidth: 320,
          minHeight: 320,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryColor.withAlpha(51),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: primaryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: scheme.onSurface),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Campo de monto
                Text(
                  'Monto',
                  style: TextStyle(
                    color: scheme.onSurface.withAlpha(179),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  autofocus: true,
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(
                      color: primaryColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: primaryColor, width: 1),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingrese el monto';
                    }
                    final amount = double.tryParse(value);
                    if (amount == null || amount <= 0) {
                      return 'Monto debe ser mayor a 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Campo de motivo
                Text(
                  'Motivo',
                  style: TextStyle(
                    color: scheme.onSurface.withAlpha(179),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextFormField(
                    controller: _reasonController,
                    maxLines: 2,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: isIncome
                          ? 'Ej: Cambio adicional, ajuste...'
                          : 'Ej: Pago de proveedor, gastos...',
                      hintStyle: TextStyle(
                        color: scheme.onSurface.withAlpha(128),
                      ),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingrese el motivo';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Botones
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          color: scheme.onSurface.withAlpha(179),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveMovement,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: onPrimaryColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  onPrimaryColor,
                                ),
                              ),
                            )
                          : Icon(icon, size: 18),
                      label: Text(
                        isIncome ? 'REGISTRAR ENTRADA' : 'REGISTRAR RETIRO',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
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
  }
}
