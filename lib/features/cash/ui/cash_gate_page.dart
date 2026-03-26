import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/window/window_service.dart';
import '../../auth/services/logout_flow_service.dart';
import '../providers/cash_providers.dart';

class CashGatePage extends ConsumerStatefulWidget {
  const CashGatePage({super.key});

  @override
  ConsumerState<CashGatePage> createState() => _CashGatePageState();
}

class _CashGatePageState extends ConsumerState<CashGatePage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '0.00');
  final _noteController = TextEditingController();
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
    _noteController.dispose();
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
      await ref.read(activeSessionControllerProvider.notifier).startSession(
            openingAmount: amount,
            note: _noteController.text.trim(),
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
          content: const Text(
            '¿Estás seguro que deseas cerrar la aplicación?',
          ),
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
    final scheme = theme.colorScheme;
    final gradient = FullposBrandTheme.backgroundGradient;
    final onSurface = scheme.onSurface;
    final cardBorder = scheme.primary.withOpacity(0.18);
    final inputFill = scheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.35 : 0.60,
    );
    final focusedAmountFill = Color.alphaBlend(
      scheme.primary.withOpacity(theme.brightness == Brightness.dark ? 0.20 : 0.12),
      scheme.surface,
    );
    InputDecoration decoration({
      required String label,
      required String hint,
      required IconData icon,
      Color? fillColor,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: scheme.primary),
        filled: true,
        fillColor: fillColor ?? inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.background,
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  color: scheme.surface,
                  elevation: 14,
                  shadowColor: Colors.black.withOpacity(0.24),
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
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
                                  child: Text(
                                    'Apertura de caja',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      color: onSurface,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
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
                                      foregroundColor: scheme.onSurface.withOpacity(0.58),
                                      backgroundColor: scheme.surfaceVariant.withOpacity(0.32),
                                    ),
                                    const SizedBox(width: 6),
                                    _TopActionIcon(
                                      icon: Icons.close_rounded,
                                      onPressed: _isLoading ? null : _closeApp,
                                      foregroundColor: scheme.onSurface.withOpacity(0.52),
                                      backgroundColor: scheme.surfaceVariant.withOpacity(0.24),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: _amountHasFocus
                                  ? [
                                      BoxShadow(
                                        color: scheme.primary.withOpacity(0.16),
                                        blurRadius: 22,
                                        spreadRadius: 1,
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
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              decoration: decoration(
                                label: 'Monto inicial',
                                hint: '0.00',
                                icon: Icons.attach_money_rounded,
                                fillColor: _amountHasFocus
                                    ? focusedAmountFill
                                    : inputFill,
                              ),
                              validator: (value) {
                                final parsed =
                                    double.tryParse((value ?? '').trim());
                                if (parsed == null) {
                                  return 'Ingresa un monto válido';
                                }
                                if (parsed < 0) {
                                  return 'El monto no puede ser negativo';
                                }
                                return null;
                              },
                              textInputAction: TextInputAction.next,
                              onTap: () {
                                _amountController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: _amountController.text.length,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _noteController,
                            enabled: !_isLoading,
                            maxLines: 2,
                            decoration: decoration(
                              label: 'Nota inicial',
                              hint: 'Ej: Apertura turno mañana',
                              icon: Icons.edit_note_rounded,
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _openCash(),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _isLoading ? null : _openCash,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_rounded),
                            label: Text(
                              _isLoading ? 'Abriendo caja...' : 'Abrir caja',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
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
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: foregroundColor,
        iconSize: 18,
        splashRadius: 18,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        tooltip: null,
      ),
    );
  }
}