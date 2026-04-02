import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/window/window_service.dart';
import '../../auth/services/logout_flow_service.dart';
import '../providers/cash_providers.dart';

const _cashGatePageBackground = Color(0xFFFFFFFF);
const _cashGatePanelColor = Color(0xFF7A7C7D);
const _cashGatePrimaryBlue = Color(0xFF2563EB);
const _cashGatePanelText = Color(0xFFFFFFFF);
const _cashGatePanelMutedText = Color(0xCCFFFFFF);
const _cashGateInputBackground = Color(0xFFFFFFFF);
const _cashGateInputText = Color(0xFF000000);
const _cashGateInputHint = Color(0xFF6B7280);

class CashGatePage extends ConsumerStatefulWidget {
  const CashGatePage({super.key});

  @override
  ConsumerState<CashGatePage> createState() => _CashGatePageState();
}

class _CashGatePageState extends ConsumerState<CashGatePage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '0.00');
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

      final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
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

  Future<void> _logout() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await LogoutFlowService.requestLogout(
        context,
        performLogout: () => LogoutFlowService.defaultPerformLogout(context),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _closeApp() async {
    if (_isLoading) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Cerrar aplicación'),
          content: const Text('¿Estás seguro que deseas cerrar la aplicación?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await WindowService.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBorder = Colors.white.withOpacity(0.18);
    final dividerColor = Colors.white.withOpacity(0.14);
    final inputFill = _cashGateInputBackground;
    final focusedAmountFill = _cashGateInputBackground;

    InputDecoration decoration({
      required String label,
      required String hint,
      required IconData icon,
      Color? fillColor,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _cashGateInputHint),
        floatingLabelStyle: const TextStyle(
          color: _cashGatePrimaryBlue,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: _cashGateInputHint),
        prefixIcon: Icon(icon, color: _cashGatePrimaryBlue),
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
      body: Container(
        color: _cashGatePageBackground,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
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
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: cardBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 74),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Apertura de caja',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                color: _cashGatePanelText,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.2,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Ingresa el monto inicial para comenzar.',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: _cashGatePanelMutedText,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _TopActionIcon(
                                        icon: Icons.logout_rounded,
                                        onPressed: _isLoading ? null : _logout,
                                        foregroundColor: _cashGatePanelText,
                                        backgroundColor: Colors.white
                                            .withOpacity(0.10),
                                      ),
                                      const SizedBox(width: 6),
                                      _TopActionIcon(
                                        icon: Icons.close_rounded,
                                        onPressed: _isLoading
                                            ? null
                                            : _closeApp,
                                        foregroundColor: _cashGatePanelText,
                                        backgroundColor: Colors.white
                                            .withOpacity(0.10),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Monto inicial',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _cashGatePanelText,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: _amountHasFocus
                                    ? [
                                        BoxShadow(
                                          color: _cashGatePrimaryBlue
                                              .withOpacity(0.18),
                                          blurRadius: 20,
                                          offset: const Offset(0, 8),
                                        ),
                                      ]
                                    : const [],
                              ),
                              child: TextFormField(
                                controller: _amountController,
                                focusNode: _amountFocusNode,
                                enabled: !_isLoading,
                                autofocus: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}'),
                                  ),
                                ],
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: _cashGateInputText,
                                  height: 1.0,
                                ),
                                cursorColor: _cashGatePrimaryBlue,
                                decoration:
                                    decoration(
                                      label: 'Monto inicial',
                                      hint: '0.00',
                                      icon: Icons.attach_money_rounded,
                                      fillColor: _amountHasFocus
                                          ? focusedAmountFill
                                          : inputFill,
                                    ).copyWith(
                                      prefixText: '4 ',
                                      prefixStyle: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: _cashGatePrimaryBlue,
                                            fontWeight: FontWeight.w900,
                                            height: 1.0,
                                          ),
                                      helperText: 'Ejemplo: 1000.00',
                                      helperStyle: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: _cashGatePanelMutedText,
                                          ),
                                    ),
                                validator: (value) {
                                  final parsed = double.tryParse(
                                    (value ?? '').trim(),
                                  );
                                  if (parsed == null) {
                                    return 'Ingresa un monto válido';
                                  }
                                  if (parsed < 0) {
                                    return 'El monto no puede ser negativo';
                                  }
                                  return null;
                                },
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _openCash(),
                                onTap: () {
                                  _amountController.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: _amountController.text.length,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 22),
                            FilledButton.icon(
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
                                elevation: 2,
                                shadowColor: const Color(0x33000000),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: dividerColor),
                              ),
                              child: Text(
                                'Solo necesitas indicar el monto inicial para abrir la caja.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _cashGatePanelMutedText,
                                  height: 1.35,
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
      ),
    );
  }
}

class _TopActionIcon extends StatelessWidget {
  const _TopActionIcon({
    required this.icon,
    required this.onPressed,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: foregroundColor,
        iconSize: 18,
        splashRadius: 18,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        tooltip: null,
      ),
    );
  }
}
