import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../data/auth_repository.dart';
import '../services/first_run_auth_flags.dart';

const _forcePasswordPrimary = Color(0xFF2563EB);
const _forcePasswordCard = Color(0xFFFFFFFF);
const _forcePasswordTitle = Color(0xFF111827);
const _forcePasswordBody = Color(0xFF4B5563);
const _forcePasswordInputBackground = Color(0xFFF3F4F6);
const _forcePasswordInputText = Color(0xFF111827);
const _forcePasswordInputHint = Color(0xFF6B7280);
const _forcePasswordBorder = Color(0xFFE5E7EB);

/// Pantalla obligatoria de cambio de contraseña al primer acceso.
///
/// Pruebas manuales rápidas:
/// - Caso A (instalación nueva): Login precarga admin/admin123 -> login -> redirige aquí -> cambiar pass -> no vuelve a pedir.
/// - Cerrar y abrir: login NO precarga, y NO redirige.
/// - Caso B (ya usada): firstRunCompleted=true -> login normal.
class ForceChangePasswordPage extends ConsumerStatefulWidget {
  const ForceChangePasswordPage({super.key});

  @override
  ConsumerState<ForceChangePasswordPage> createState() =>
      _ForceChangePasswordPageState();
}

class _ForceChangePasswordPageState
    extends ConsumerState<ForceChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSaving = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final next = _newController.text.trim();

      await AuthRepository.changeCurrentUserPassword(
        currentPassword: '',
        newPassword: next,
        allowInitialPassword: true,
      );

      await FirstRunAuthFlags.setMustChangePassword(false);
      await FirstRunAuthFlags.setFirstRunCompleted(true);
      FirstRunAuthFlags.log('password_changed ok');

      if (!mounted) return;
      // Refrescar snapshot/router para evitar estados “pegados”.
      unawaited(ref.read(appBootstrapProvider).refreshAuth());
      final rootCtx = ErrorHandler.navigatorKey.currentContext ?? context;
      GoRouter.of(rootCtx).refresh();
      GoRouter.of(rootCtx).go('/cash-gate');
    } catch (e, st) {
      final ex = await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _save,
        module: 'auth/force_change_password',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ex.messageUser)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _validateNewPassword(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingrese una nueva contraseña';
    if (v.length < 8) return 'La contraseña debe tener al menos 8 caracteres';
    if (v == AuthRepository.initialAdminPassword) {
      return 'La nueva contraseña no puede ser ${AuthRepository.initialAdminPassword}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final safeWidth = (screenSize.width - 48).clamp(320.0, 420.0);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: FullposBrandTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: viewInsets),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: safeWidth, minWidth: 320),
                child: Container(
                  decoration: BoxDecoration(
                    color: _forcePasswordCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _forcePasswordBorder.withOpacity(0.75),
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
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: _forcePasswordPrimary.withOpacity(0.10),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock_reset_rounded,
                              color: _forcePasswordPrimary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Cambia tu contraseña para continuar',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _forcePasswordTitle,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Este es tu primer acceso. Solo define una nueva contraseña segura y entra al sistema.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _forcePasswordBody,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _newController,
                            obscureText: _obscureNew,
                            enabled: !_isSaving,
                            autofocus: true,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: _forcePasswordInputText,
                              fontWeight: FontWeight.w600,
                            ),
                            cursorColor: _forcePasswordPrimary,
                            decoration: InputDecoration(
                              labelText: 'Nueva contraseña',
                              hintText: 'Mínimo 8 caracteres',
                              hintStyle: const TextStyle(
                                color: _forcePasswordInputHint,
                              ),
                              helperText:
                                  'No puede ser ${AuthRepository.initialAdminPassword}.',
                              filled: true,
                              fillColor: _forcePasswordInputBackground,
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
                                  color: _forcePasswordPrimary,
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
                                  color: _forcePasswordPrimary,
                                  width: 1.6,
                                ),
                              ),
                              errorStyle: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 12,
                                height: 1.2,
                              ),
                              suffixIcon: IconButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => setState(
                                        () => _obscureNew = !_obscureNew,
                                      ),
                                icon: Icon(
                                  _obscureNew
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  color: _forcePasswordInputHint,
                                ),
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: _validateNewPassword,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: _obscureConfirm,
                            enabled: !_isSaving,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: _forcePasswordInputText,
                              fontWeight: FontWeight.w600,
                            ),
                            cursorColor: _forcePasswordPrimary,
                            decoration: InputDecoration(
                              labelText: 'Confirmar contraseña',
                              hintText: 'Repite la nueva contraseña',
                              hintStyle: const TextStyle(
                                color: _forcePasswordInputHint,
                              ),
                              filled: true,
                              fillColor: _forcePasswordInputBackground,
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
                                  color: _forcePasswordPrimary,
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
                                  color: _forcePasswordPrimary,
                                  width: 1.6,
                                ),
                              ),
                              errorStyle: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 12,
                                height: 1.2,
                              ),
                              suffixIcon: IconButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => setState(
                                        () =>
                                            _obscureConfirm = !_obscureConfirm,
                                      ),
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  color: _forcePasswordInputHint,
                                ),
                              ),
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => unawaited(_save()),
                            validator: (v) {
                              final nv = _newController.text.trim();
                              final cv = (v ?? '').trim();
                              if (cv.isEmpty) {
                                return 'Confirme la nueva contraseña';
                              }
                              if (cv != nv) {
                                return 'La confirmación no coincide';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _isSaving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: _forcePasswordPrimary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Guardar y continuar'),
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
