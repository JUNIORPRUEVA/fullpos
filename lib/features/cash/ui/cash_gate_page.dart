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
const _cashGateInputBackground = Color(0xFFFFFFFF);
const _cashGateInputText = Color(0xFF111827);
const _cashGateInputHint = Color(0xFF94A3B8);
const _cashGateInputLabel = Color(0xFFD1D5DB);
const _cashGateInputBadgeBackground = Color(0xFFEFF4FF);
const _cashGateInputIdleBorder = Color(0xFFE2E8F0);

class CashGatePage extends ConsumerStatefulWidget {
  const CashGatePage({super.key});

  @override
  ConsumerState<CashGatePage> createState() => _CashGatePageState();
}

class _CashGatePageState extends ConsumerState<CashGatePage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
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
    final inputFill = _cashGateInputBackground;
    final focusedAmountFill = _cashGateInputBackground;
    final amountBorderColor = _amountHasFocus
        ? _cashGatePrimaryBlue
        : _cashGateInputIdleBorder.withOpacity(0.92);

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
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Fondo inicial',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: _cashGateInputLabel,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: amountBorderColor,
                                    width: _amountHasFocus ? 1.8 : 1.0,
                                  ),
                                  boxShadow: _amountHasFocus
                                      ? [
                                          BoxShadow(
                                            color: _cashGatePrimaryBlue
                                                .withOpacity(0.16),
                                            blurRadius: 22,
                                            offset: const Offset(0, 10),
                                          ),
                                        ]
                                      : const [],
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _amountHasFocus
                                        ? focusedAmountFill
                                        : inputFill,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 14,
                                          top: 12,
                                          bottom: 12,
                                          right: 12,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                _cashGateInputBadgeBackground,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            r'RD$',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  color: _cashGatePrimaryBlue,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -0.2,
                                                ),
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
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: _cashGateInputText,
                                                letterSpacing: -0.6,
                                                height: 1.0,
                                              ),
                                          cursorColor: _cashGatePrimaryBlue,
                                          textAlignVertical:
                                              TextAlignVertical.center,
                                          decoration: InputDecoration(
                                            hintText: '0',
                                            hintStyle: theme
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(
                                                  color: _cashGateInputHint,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: -0.5,
                                                  height: 1.0,
                                                ),
                                            filled: false,
                                            isCollapsed: true,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            errorBorder: InputBorder.none,
                                            focusedErrorBorder:
                                                InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.only(
                                                  top: 22,
                                                  bottom: 22,
                                                  right: 18,
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
                                          textInputAction: TextInputAction.done,
                                          onFieldSubmitted: (_) => _openCash(),
                                          onTap: () {
                                            _amountController
                                                .selection = TextSelection(
                                              baseOffset: 0,
                                              extentOffset:
                                                  _amountController.text.length,
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
                                    _isLoading
                                        ? 'Abriendo caja...'
                                        : 'Abrir caja',
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
