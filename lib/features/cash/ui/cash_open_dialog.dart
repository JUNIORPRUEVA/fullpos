import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../data/operation_flow_service.dart';
import '../providers/cash_providers.dart';

const _cashOpenDialogPanel = Color(0xFF7A7C7D);
const _cashOpenDialogPrimary = Color(0xFF2563EB);
const _cashOpenDialogText = Color(0xFFFFFFFF);
const _cashOpenDialogMutedText = Color(0xCCFFFFFF);
const _cashOpenDialogInputBackground = Color(0xFFFFFFFF);
const _cashOpenDialogInputText = Color(0xFF000000);
const _cashOpenDialogInputHint = Color(0xFF6B7280);

/// Diálogo para abrir caja y crear la sesión activa.
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
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _openCash() async {
    if (_isLoading) return;
    final formState = _formKey.currentState;
    if (formState == null) return;
    if (!formState.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authorized = await requireAuthorizationIfNeeded(
        context: context,
        action: AppActions.startSession,
        resourceType: 'cashbox_daily',
        resourceId: 'new',
        reason: 'Iniciar sesión',
      );
      if (!authorized || !mounted) return;

      final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
      await OperationFlowService.startActiveSession(
        openingAmount: amount,
        note: '',
      );
      await ref.read(activeSessionControllerProvider.notifier).refresh();

      if (mounted) {
        final rootContext = Navigator.of(context, rootNavigator: true).context;
        Navigator.of(context).pop(true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            SnackBar(
              content: Text(
                'Sesión iniciada con \$${amount.toStringAsFixed(2)}',
              ),
              backgroundColor: Theme.of(rootContext).colorScheme.primary,
            ),
          );
        });
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

    final fieldFill = _cashOpenDialogInputBackground;
    final panelBorder = Colors.white.withOpacity(0.18);
    final sectionBorder = Colors.white.withOpacity(0.14);

    return DialogKeyboardShortcuts(
      enableSubmitShortcuts: !_isLoading,
      onSubmit: _isLoading ? null : _openCash,
      onCancel: _isLoading ? null : () => Navigator.pop(context),
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
              color: _cashOpenDialogPanel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: panelBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
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
                  color: _cashOpenDialogPanel,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: panelBorder),
                        ),
                        child: Icon(
                          Icons.lock_open_outlined,
                          color: _cashOpenDialogText,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Abrir caja',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: _cashOpenDialogText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Iniciar la caja y entrar directo al POS',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _cashOpenDialogMutedText,
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
                        style: IconButton.styleFrom(
                          foregroundColor: _cashOpenDialogText,
                          backgroundColor: Colors.white.withOpacity(0.08),
                          hoverColor: Colors.white.withOpacity(0.14),
                        ),
                        icon: const Icon(Icons.close),
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
                            'Monto inicial',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _cashOpenDialogText,
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
                              color: _cashOpenDialogInputText,
                              height: 1.0,
                            ),
                            cursorColor: _cashOpenDialogPrimary,
                            decoration: InputDecoration(
                              prefixText: '\$ ',
                              prefixStyle: theme.textTheme.titleLarge?.copyWith(
                                color: _cashOpenDialogPrimary,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                              ),
                              labelText: 'Monto inicial',
                              labelStyle: const TextStyle(
                                color: _cashOpenDialogInputHint,
                              ),
                              floatingLabelStyle: const TextStyle(
                                color: _cashOpenDialogPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                              hintText: '0.00',
                              hintStyle: const TextStyle(
                                color: _cashOpenDialogInputHint,
                              ),
                              prefixIcon: const Icon(
                                Icons.attach_money_rounded,
                                color: _cashOpenDialogPrimary,
                              ),
                              filled: true,
                              fillColor: fieldFill,
                              helperText: 'Ejemplo: 1000.00',
                              helperStyle: theme.textTheme.bodySmall?.copyWith(
                                color: _cashOpenDialogMutedText,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: _cashOpenDialogPrimary,
                                  width: 1.6,
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
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _openCash(),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: sectionBorder),
                            ),
                            child: Text(
                              'Solo necesitas indicar el monto inicial para abrir la caja.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _cashOpenDialogMutedText,
                                height: 1.35,
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
                    color: Colors.white.withOpacity(0.08),
                    border: Border(top: BorderSide(color: sectionBorder)),
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
                            foregroundColor: _cashOpenDialogText,
                            backgroundColor: Colors.white.withOpacity(0.08),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.24),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
                            backgroundColor: _cashOpenDialogPrimary,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor: const Color(0x33000000),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: _isLoading
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Colors.white,
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
