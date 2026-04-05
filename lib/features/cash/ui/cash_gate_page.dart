import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/utils/accounting_amount_formatter.dart';
import '../providers/cash_providers.dart';

const _cashGatePageBackground = Color(0xFFF5F7FA);
const _cashGatePanelColor = Color(0xFF374151);
const _cashGatePrimaryBlue = Color(0xFF2563EB);
const _cashGatePanelText = Color(0xFFF9FAFB);
const _cashGatePanelMutedText = Color(0xFFD1D5DB);
const _cashGateInputBackground = Color(0xFFFFFFFF);
const _cashGateInputText = Color(0xFF111827);
const _cashGateInputHint = Color(0xFF94A3B8);

class CashGatePage extends ConsumerStatefulWidget {
  const CashGatePage({super.key});

  @override
  ConsumerState<CashGatePage> createState() => _CashGatePageState();
}

class _CashGatePageState extends ConsumerState<CashGatePage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '0');
  final _amountFocusNode = FocusNode();

  bool _isLoading = false;
  bool _amountHasFocus = false;

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(_handleAmountFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _amountFocusNode.requestFocus();
      _amountController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _amountController.text.length,
      );
    });
  }

  void _handleAmountFocusChange() {
    if (!mounted) return;
    setState(() => _amountHasFocus = _amountFocusNode.hasFocus);
  }

  @override
  void dispose() {
    _amountFocusNode.removeListener(_handleAmountFocusChange);
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openCash() async {
    if (_isLoading) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

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
      await ref
          .read(activeSessionControllerProvider.notifier)
          .startSession(openingAmount: amount, note: '');

      if (!mounted) return;
      context.go('/sales');
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _openCash,
        module: 'cash/gate',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBorder = Colors.white.withOpacity(0.08);
    final dividerColor = Colors.white.withOpacity(0.10);
    final inputFill = _cashGateInputBackground;
    final focusedAmountFill = _cashGateInputBackground;

    InputDecoration decoration({
      required String hint,
      Color? fillColor,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _cashGateInputHint, fontSize: 13),
        filled: true,
        fillColor: fillColor ?? inputFill,
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
          borderSide: const BorderSide(color: _cashGatePrimaryBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.4),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _cashGatePageBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF8FAFD),
                    _cashGatePageBackground,
                    Color(0xFFF1F5F9),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -100,
            left: -30,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cashGatePrimaryBlue.withOpacity(0.055),
              ),
            ),
          ),
          Positioned(
            right: -60,
            bottom: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0F172A).withOpacity(0.025),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 404),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x260F172A),
                          blurRadius: 44,
                          offset: Offset(0, 24),
                        ),
                        BoxShadow(
                          color: Color(0x120F172A),
                          blurRadius: 20,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: _cashGatePanelColor,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: cardBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Image.asset(
                                  FullposBrandTheme.logoAsset,
                                  height: 54,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 18),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: _amountHasFocus
                                      ? [
                                          BoxShadow(
                                            color: _cashGatePrimaryBlue.withOpacity(
                                              0.18,
                                            ),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                        ]
                                      : const [],
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _amountHasFocus
                                        ? focusedAmountFill
                                        : inputFill,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16,
                                          right: 10,
                                        ),
                                        child: Text(
                                          'RD\$',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: _cashGatePrimaryBlue,
                                                fontWeight: FontWeight.w900,
                                                height: 1.0,
                                              ),
                                        ),
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _amountController,
                                          focusNode: _amountFocusNode,
                                          enabled: !_isLoading,
                                          autofocus: true,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            AccountingAmountFormatter(),
                                          ],
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: _cashGateInputText,
                                                height: 1.0,
                                              ),
                                          cursorColor: _cashGatePrimaryBlue,
                                          decoration: InputDecoration(
                                            hintText: '0',
                                            hintStyle: const TextStyle(
                                              color: _cashGateInputHint,
                                              fontSize: 13,
                                            ),
                                            filled: false,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            errorBorder: InputBorder.none,
                                            focusedErrorBorder:
                                                InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 0,
                                                  vertical: 16,
                                                ),
                                          ),
                                          validator: (value) {
                                            final parsed =
                                                AccountingAmountFormatter.parse(
                                                  (value ?? '').trim(),
                                                );
                                            if (parsed < 0) {
                                              return 'El monto no puede ser negativo';
                                            }
                                            return null;
                                          },
                                          textInputAction:
                                              TextInputAction.done,
                                          onFieldSubmitted: (_) => _openCash(),
                                          onTap: () {
                                            _amountController.selection =
                                                TextSelection(
                                                  baseOffset: 0,
                                                  extentOffset:
                                                      _amountController
                                                          .text
                                                          .length,
                                                );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed: _isLoading ? null : _openCash,
                                  icon: _isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.lock_open_rounded),
                                  label: Text(
                                    _isLoading ? 'Abriendo caja...' : 'Abrir caja',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _cashGatePrimaryBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }
}
