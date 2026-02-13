import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../data/auth_repository.dart';
import '../services/first_run_auth_flags.dart';

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
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSaving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final current = _currentController.text;
      final next = _newController.text;

      await AuthRepository.changeCurrentUserPassword(
        currentPassword: current,
        newPassword: next,
      );

      await FirstRunAuthFlags.setMustChangePassword(false);
      await FirstRunAuthFlags.setFirstRunCompleted(true);
      FirstRunAuthFlags.log('password_changed ok');

      if (!mounted) return;
      // Refrescar snapshot/router para evitar estados “pegados”.
      unawaited(ref.read(appBootstrapProvider).refreshAuth());
      final rootCtx = ErrorHandler.navigatorKey.currentContext ?? context;
      GoRouter.of(rootCtx).refresh();
      GoRouter.of(rootCtx).go('/sales');
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
    if (v == 'admin123') return 'La nueva contraseña no puede ser admin123';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = FullposBrandTheme.backgroundGradient;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: FullposBrandTheme.background,
        body: Container(
          decoration: BoxDecoration(gradient: gradient),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Cambio de contraseña requerido',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Por seguridad, debes cambiar tu contraseña antes de continuar.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _currentController,
                        obscureText: _obscureCurrent,
                        enabled: !_isSaving,
                        decoration: InputDecoration(
                          labelText: 'Contraseña actual',
                          suffixIcon: IconButton(
                            onPressed: _isSaving
                                ? null
                                : () => setState(
                                    () => _obscureCurrent = !_obscureCurrent,
                                  ),
                            icon: Icon(
                              _obscureCurrent
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if ((v ?? '').isEmpty) {
                            return 'Ingrese su contraseña actual';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newController,
                        obscureText: _obscureNew,
                        enabled: !_isSaving,
                        decoration: InputDecoration(
                          labelText: 'Nueva contraseña',
                          helperText:
                              'Mínimo 8 caracteres. No puede ser admin123.',
                          suffixIcon: IconButton(
                            onPressed: _isSaving
                                ? null
                                : () => setState(
                                    () => _obscureNew = !_obscureNew,
                                  ),
                            icon: Icon(
                              _obscureNew
                                  ? Icons.visibility
                                  : Icons.visibility_off,
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
                        decoration: InputDecoration(
                          labelText: 'Confirmar nueva contraseña',
                          suffixIcon: IconButton(
                            onPressed: _isSaving
                                ? null
                                : () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility
                                  : Icons.visibility_off,
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
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Guardar y continuar'),
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
