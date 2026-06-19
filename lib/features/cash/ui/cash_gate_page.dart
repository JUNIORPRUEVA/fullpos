import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/utils/accounting_amount_formatter.dart';
import '../providers/cash_providers.dart';

const _cashGatePageBackground = Color(0xFFF5F7FA);
const _cashGatePanelColor = Color(0xFFFFFFFF);
const _cashGatePrimaryBlue = Color(0xFF2563EB);
const _cashGatePanelBorder = Color(0xFFBFDBFE);
const _cashGateHeaderBorder = Color(0xFFD6E0EA);
const _cashGateInputBackground = Color(0xFFF8FAFC);
const _cashGateInputText = Color(0xFF111827);
const _cashGateInputHint = Color(0xFF94A3B8);
const _cashGateInputLabel = Color(0xFF0F172A);
const _cashGateInputSubtitle = Color(0xFF64748B);
const _cashGateInputBadgeBackground = Color(0xFFECF3FF);
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
      final amount = AccountingAmountFormatter.parse(_amountController.text);
      await ref
          .read(activeSessionControllerProvider.notifier)
          .startSession(openingAmount: amount, note: '')
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException(
              'La apertura de caja tardó demasiado. Intenta nuevamente.',
            ),
          );

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
    final screenSize = MediaQuery.of(context).size;
    final ultraCompact = screenSize.width < 420 || screenSize.height < 760;
    final shellHorizontalPadding = (screenSize.width * 0.06).clamp(16.0, 40.0);
    final shellVerticalPadding = (screenSize.height * 0.06).clamp(16.0, 40.0);
    final panelWidth = (screenSize.width - (shellHorizontalPadding * 2)).clamp(
      280.0,
      430.0,
    );
    final panelPadding = ultraCompact ? 20.0 : 28.0;
    final titleSize = ultraCompact ? 17.5 : 19.5;
    final subtitleSize = ultraCompact ? 12.4 : 13.4;
    final fieldLabelSize = ultraCompact ? 15.5 : 16.8;
    final amountTextSize = ultraCompact ? 16.8 : 18.6;
    final amountFieldWidth = ultraCompact ? 252.0 : 304.0;
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
                padding: EdgeInsets.symmetric(
                  horizontal: shellHorizontalPadding,
                  vertical: shellVerticalPadding,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: panelWidth.toDouble()),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _cashGatePanelColor,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _cashGatePanelBorder,
                        width: 1.25,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x160F172A),
                          blurRadius: 34,
                          offset: Offset(0, 18),
                        ),
                        BoxShadow(
                          color: Color(0x0C0F172A),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        panelPadding,
                        panelPadding,
                        panelPadding,
                        ultraCompact ? 20 : 24,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: EdgeInsets.only(
                                bottom: ultraCompact ? 14 : 18,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _cashGateHeaderBorder,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Abrir caja',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          color: _cashGateInputLabel,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                          fontSize: titleSize,
                                        ),
                                  ),
                                  SizedBox(height: ultraCompact ? 4 : 6),
                                  Text(
                                    'Registra el fondo inicial para comenzar a trabajar.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: _cashGateInputSubtitle,
                                      fontSize: subtitleSize,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 18 : 22),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Fondo inicial',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: _cashGateInputLabel,
                                  fontWeight: FontWeight.w600,
                                  fontSize: fieldLabelSize,
                                ),
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 10 : 12),
                            Align(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: amountFieldWidth,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: amountBorderColor,
                                      width: _amountHasFocus ? 1.5 : 1.0,
                                    ),
                                    boxShadow: _amountHasFocus
                                        ? [
                                            BoxShadow(
                                              color: _cashGatePrimaryBlue
                                                  .withOpacity(0.10),
                                              blurRadius: 18,
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
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 10,
                                            top: 8,
                                            bottom: 8,
                                            right: 8,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  _cashGateInputBadgeBackground,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              r'RD$',
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    color: _cashGatePrimaryBlue,
                                                    fontWeight: FontWeight.w700,
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
                                                  fontWeight: FontWeight.w600,
                                                  color: _cashGateInputText,
                                                  letterSpacing: -0.4,
                                                  fontSize: amountTextSize,
                                                  height: 1.0,
                                                ),
                                            cursorColor: _cashGatePrimaryBlue,
                                            textAlignVertical:
                                                TextAlignVertical.center,
                                            decoration: InputDecoration(
                                              hintText: '0.00',
                                              hintStyle: theme
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    color: _cashGateInputHint,
                                                    fontWeight: FontWeight.w500,
                                                    letterSpacing: -0.3,
                                                    fontSize: amountTextSize,
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
                                                    top: 20,
                                                    bottom: 20,
                                                    right: 16,
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
                                            onFieldSubmitted: (_) =>
                                                _openCash(),
                                            onTap: () {
                                              _amountController
                                                  .selection = TextSelection(
                                                baseOffset: 0,
                                                extentOffset: _amountController
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
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 18 : 22),
                            SizedBox(
                              height: 50,
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
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
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
        ],
      ),
    );
  }
}
