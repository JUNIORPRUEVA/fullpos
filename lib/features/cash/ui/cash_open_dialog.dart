import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../core/utils/accounting_amount_formatter.dart';
import '../data/operation_flow_service.dart';
import '../providers/cash_providers.dart';

const _cashOpenDialogPrimary = Color(0xFF2563EB);
const _cashOpenDialogCard = Color(0xFFFFFFFF);
const _cashOpenDialogTitle = Color(0xFF111827);
const _cashOpenDialogInputBackground = Color(0xFFF3F4F6);
const _cashOpenDialogInputText = Color(0xFF111827);
const _cashOpenDialogInputHint = Color(0xFF6B7280);
const _cashOpenDialogBorder = Color(0xFFE5E7EB);

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
  final _amountController = TextEditingController();
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

      final amount = AccountingAmountFormatter.parse(_amountController.text);
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
                'Sesión iniciada con ${AccountingAmountFormatter.formatWithSymbol(amount, symbol: r'$')}',
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
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final safeWidth = (screenSize.width - 48).clamp(320.0, 396.0);

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
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: viewInsets),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: safeWidth,
              minWidth: 320,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: _cashOpenDialogCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _cashOpenDialogBorder.withOpacity(0.75),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 42,
                    offset: Offset(0, 24),
                  ),
                  BoxShadow(
                    color: Color(0x080F172A),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 30, 30, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Monto inicial',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _cashOpenDialogTitle,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [AccountingAmountFormatter()],
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _cashOpenDialogInputText,
                          fontWeight: FontWeight.w600,
                        ),
                        cursorColor: _cashOpenDialogPrimary,
                        decoration: InputDecoration(
                          prefixText: 'RD\$ ',
                          prefixStyle: theme.textTheme.titleMedium?.copyWith(
                            color: _cashOpenDialogPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          hintText: '0.00',
                          hintStyle: const TextStyle(
                            color: _cashOpenDialogInputHint,
                          ),
                          filled: true,
                          fillColor: _cashOpenDialogInputBackground,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 15,
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
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _cashOpenDialogPrimary,
                              width: 1.6,
                            ),
                          ),
                          errorStyle: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                        validator: (value) {
                          final raw = value?.trim() ?? '';
                          if (raw.isEmpty) return null;

                          final amount = AccountingAmountFormatter.parse(raw);
                          if (amount < 0) {
                            return 'Monto invalido';
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _openCash(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _openCash,
                          style: FilledButton.styleFrom(
                            backgroundColor: _cashOpenDialogPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Abrir caja'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
