import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/window/window_service.dart';
import '../../settings/data/user_model.dart';
import '../../settings/data/users_repository.dart';
import '../data/auth_repository.dart';
import '../services/password_reset_service.dart';
import '../services/first_run_auth_flags.dart';

/// Pantalla de inicio de sesión con soporte de contraseña o PIN.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

enum _LoginMode { password, pin }

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();

  bool _firstRunPrefillChecked = false;

  bool _isLoading = false;
  bool _obscurePassword = true;
  _LoginMode _mode = _LoginMode.password;
  String? _errorMessage;

  bool get _usingPin => _mode == _LoginMode.pin;

  @override
  void initState() {
    super.initState();
    unawaited(_maybePrefillFirstRunCredentials());
  }

  Future<void> _maybePrefillFirstRunCredentials() async {
    if (_firstRunPrefillChecked) return;
    _firstRunPrefillChecked = true;

    try {
      final firstRunCompleted = await FirstRunAuthFlags.isFirstRunCompleted();
      if (firstRunCompleted) return;

      // Only prefill if user hasn't typed yet.
      if (_usernameController.text.isNotEmpty ||
          _passwordController.text.isNotEmpty ||
          _pinController.text.isNotEmpty) {
        return;
      }

      FirstRunAuthFlags.log('first_run=true prefilling_login');
      if (!mounted) return;
      setState(() {
        _usernameController.text = 'admin';
        // Credencial inicial real del sistema (ver seed/migraciones y UI demo).
        _passwordController.text = 'admin123';
      });
    } catch (_) {
      // Never block login on diagnostics.
    }
  }

  void _setMode(_LoginMode next) {
    if (_mode == next) return;
    setState(() {
      _mode = next;
      _errorMessage = null;
      if (_usingPin) {
        _passwordController.clear();
      } else {
        _pinController.clear();
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      final pin = _pinController.text.trim();

      UserModel? user;
      if (_usingPin) {
        user = await AuthRepository.loginWithPin(username, pin);
      } else {
        user = await AuthRepository.login(username, password);
      }

      if (!mounted) return;

      if (user != null) {
        // Source-of-truth en memoria: evita estado pegado hasta reiniciar.
        ref.read(appBootstrapProvider).forceLoggedIn();
        unawaited(ref.read(appBootstrapProvider).refreshAuth());
        if (!mounted) return;

        // Primer acceso: si se usaron credenciales iniciales, forzar cambio.
        if (!_usingPin) {
          final normalized = username.trim().toLowerCase();
          final firstRunCompleted =
              await FirstRunAuthFlags.isFirstRunCompleted();
          final usingInitialCreds =
              normalized == 'admin' && password == 'admin123';
          if (!firstRunCompleted) {
            if (usingInitialCreds) {
              await FirstRunAuthFlags.setMustChangePassword(true);
              final rootCtx =
                  ErrorHandler.navigatorKey.currentContext ?? context;
              GoRouter.of(rootCtx).refresh();
              GoRouter.of(rootCtx).go('/force-change-password');
              return;
            }

            // Si el equipo ya tenía la app instalada (o el admin cambió su clave),
            // no queremos seguir precargando credenciales erróneas.
            await FirstRunAuthFlags.setMustChangePassword(false);
            await FirstRunAuthFlags.setFirstRunCompleted(true);
            FirstRunAuthFlags.log(
              'first_run: login ok with non-initial credentials; marking completed',
            );
          }
        }

        final rootCtx = ErrorHandler.navigatorKey.currentContext ?? context;
        GoRouter.of(rootCtx).refresh();
        GoRouter.of(rootCtx).go('/operation-start');
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = _usingPin
              ? 'PIN o usuario incorrecto'
              : 'Usuario o contraseña incorrectos';
        });
      }
    } catch (e, st) {
      final ex = await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _handleLogin,
        module: 'auth/login',
      );
      if (mounted) setState(() => _errorMessage = ex.messageUser);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openForgotPasswordDialog() async {
    final tokenController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final service = PasswordResetService();
    const recoveryUsername = 'admin';

    bool loading = false;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? error;
    String? info;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !loading,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> requestSupport() async {
                if (loading) return;
                if (!dialogContext.mounted) return;

                setDialogState(() {
                  loading = true;
                  error = null;
                  info = null;
                });

                try {
                  final supportMessage = await service.requestSupportMessage(
                    username: recoveryUsername,
                    message:
                        'Cliente solicita token para recuperación de contraseña de administrador.',
                  );

                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    info = supportMessage;
                  });
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    error = e.toString().replaceFirst('Exception: ', '');
                  });
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      loading = false;
                    });
                  }
                }
              }

              Future<void> resetPassword() async {
                var canUpdateDialogState = true;
                final token = tokenController.text.trim();
                final newPassword = newPasswordController.text;
                final confirmPassword = confirmPasswordController.text;

                if (token.isEmpty) {
                  setDialogState(() {
                    error = 'Ingresa el token temporal de soporte';
                  });
                  return;
                }
                if (newPassword.length < 6) {
                  setDialogState(() {
                    error = 'La nueva contraseña debe tener al menos 6 caracteres';
                  });
                  return;
                }
                if (newPassword != confirmPassword) {
                  setDialogState(() {
                    error = 'Las contraseñas no coinciden';
                  });
                  return;
                }

                setDialogState(() {
                  loading = true;
                  error = null;
                  info = null;
                });

                try {
                  await service.confirmSupportToken(
                    username: recoveryUsername,
                    token: token,
                  );

                  var user = await UsersRepository.getByUsername(
                    recoveryUsername,
                  );

                  if (user == null || user.id == null || !user.isAdmin) {
                    final allUsers = await UsersRepository.getAll();
                    for (final candidate in allUsers) {
                      if (candidate.isAdmin && candidate.id != null) {
                        user = candidate;
                        break;
                      }
                    }
                  }

                  if (user == null || user.id == null || !user.isAdmin) {
                    throw Exception('No se encontró una cuenta administrador en esta computadora.');
                  }

                  await UsersRepository.changePassword(user.id!, newPassword);

                  if (!mounted) {
                    canUpdateDialogState = false;
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    return;
                  }

                  _mode = _LoginMode.password;
                  _passwordController.text = newPassword;

                  if (dialogContext.mounted) {
                    canUpdateDialogState = false;
                    Navigator.of(dialogContext).pop();
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Contraseña restablecida. Ya puedes iniciar sesión.'),
                      ),
                    );
                  }
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    error = e.toString().replaceFirst('Exception: ', '');
                  });
                } finally {
                  if (canUpdateDialogState && dialogContext.mounted) {
                    setDialogState(() {
                      loading = false;
                    });
                  }
                }
              }

              return AlertDialog(
                title: const Text('Recuperar contraseña'),
                content: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Cuenta de recuperación: administrador local',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Solicita el token a soporte. Es válido por 15 minutos y de un solo uso.',
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: tokenController,
                        enabled: !loading,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Token de soporte',
                          hintText: 'ABCD-EF12-3456-7890',
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: loading ? null : requestSupport,
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Solicitar soporte'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: newPasswordController,
                        enabled: !loading,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          labelText: 'Nueva contraseña',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureNew
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: loading
                                ? null
                                : () {
                                    setDialogState(() {
                                      obscureNew = !obscureNew;
                                    });
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmPasswordController,
                        enabled: !loading,
                        obscureText: obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirmar nueva contraseña',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: loading
                                ? null
                                : () {
                                    setDialogState(() {
                                      obscureConfirm = !obscureConfirm;
                                    });
                                  },
                          ),
                        ),
                      ),
                      if (info != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          info!,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: loading ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cerrar'),
                  ),
                  FilledButton(
                    onPressed: loading ? null : resetPassword,
                    child: loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Validar token y restablecer'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      tokenController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final brandName = FullposBrandTheme.appName;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = FullposBrandTheme.backgroundGradient;

    final onSurface = scheme.onSurface;
    final mutedText = onSurface.withOpacity(0.72);
    final cardBorder = scheme.primary.withOpacity(0.18);
    final dividerColor = scheme.onSurface.withOpacity(0.10);
    final inputFill = scheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.35 : 0.60,
    );

    InputDecoration decoration({
      required String label,
      required String hint,
      required IconData icon,
      Widget? suffix,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: scheme.primary),
        suffixIcon: suffix,
        filled: true,
        fillColor: inputFill,
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
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
                    horizontal: 32,
                    vertical: 28,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: scheme.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: cardBorder),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.asset(
                                FullposBrandTheme.logoAsset,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Center(
                                      child: Icon(
                                        Icons.storefront,
                                        size: 36,
                                        color: scheme.primary,
                                      ),
                                    ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    brandName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: onSurface,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Inicia sesión para continuar',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: mutedText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceVariant.withOpacity(0.40),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: dividerColor),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Contraseña',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: _usingPin ? mutedText : onSurface,
                                  fontWeight: _usingPin
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Switch.adaptive(
                                value: _usingPin,
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        FocusScope.of(context).unfocus();
                                        _setMode(
                                          value
                                              ? _LoginMode.pin
                                              : _LoginMode.password,
                                        );
                                      },
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'PIN',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: _usingPin ? onSurface : mutedText,
                                  fontWeight: _usingPin
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _usingPin
                                    ? Icons.password_rounded
                                    : Icons.lock_outline_rounded,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: scheme.error.withOpacity(0.30),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: scheme.error,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _usernameController,
                          decoration: decoration(
                            label: 'Usuario',
                            hint: 'Ingresa tu usuario',
                            icon: Icons.person_outline,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingrese un usuario';
                            }
                            return null;
                          },
                          enabled: !_isLoading,
                          textInputAction: TextInputAction.next,
                          autofocus: true,
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _usingPin
                              ? TextFormField(
                                  key: const ValueKey('pinField'),
                                  controller: _pinController,
                                  enabled: !_isLoading,
                                  decoration: decoration(
                                    label: 'PIN',
                                    hint: '4-6 dígitos',
                                    icon: Icons.dialpad,
                                  ),
                                  keyboardType: TextInputType.number,
                                  obscureText: true,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  validator: (_) {
                                    final value = _pinController.text.trim();
                                    if (value.length < 4) {
                                      return 'PIN mínimo de 4 dígitos';
                                    }
                                    return null;
                                  },
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _handleLogin(),
                                )
                              : TextFormField(
                                  key: const ValueKey('passwordField'),
                                  controller: _passwordController,
                                  decoration: decoration(
                                    label: 'Contraseña',
                                    hint: 'Ingresa tu contraseña',
                                    icon: Icons.lock_outline,
                                    suffix: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Mostrar contraseña'
                                          : 'Ocultar contraseña',
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: mutedText,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                  obscureText: _obscurePassword,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Ingrese una contraseña';
                                    }
                                    return null;
                                  },
                                  enabled: !_isLoading,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _handleLogin(),
                                ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _handleLogin,
                          icon: const Icon(Icons.login_rounded),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : const Text('Iniciar sesión'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading ? null : _openForgotPasswordDialog,
                            child: const Text('Olvidé mi contraseña'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () => WindowService.minimize(),
                                icon: const Icon(Icons.minimize_rounded),
                                label: const Text('Minimizar'),
                                style: TextButton.styleFrom(
                                  foregroundColor: mutedText,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () => WindowService.close(),
                                icon: const Icon(Icons.exit_to_app_rounded),
                                label: const Text('Salir'),
                                style: TextButton.styleFrom(
                                  foregroundColor: mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: scheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Demo: admin / admin123',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: mutedText,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
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
