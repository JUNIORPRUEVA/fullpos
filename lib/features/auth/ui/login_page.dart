import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/bootstrap/app_bootstrap_controller.dart';
import '../../../core/errors/error_handler.dart';
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
  final _usernameFocusNode = FocusNode();

  bool _firstRunPrefillChecked = false;
  List<UserModel> _availableUsers = const [];

  bool _isLoading = false;
  bool _obscurePassword = true;
  _LoginMode _mode = _LoginMode.password;
  String? _errorMessage;
  bool _showDemoHint = false;
  bool _showDemoCredentials = false;

  bool get _usingPin => _mode == _LoginMode.pin;

  @override
  void initState() {
    super.initState();
    unawaited(_maybePrefillFirstRunCredentials());
    unawaited(_registerDemoHintVisibility());
    unawaited(_loadAvailableUsers());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _usernameFocusNode.requestFocus();
    });
  }

  Future<void> _loadAvailableUsers() async {
    try {
      final users = await UsersRepository.getActiveUsers();
      if (!mounted) return;
      setState(() {
        _availableUsers = users;
      });
    } catch (_) {
      // Nunca bloquear el login por no poder cargar el selector.
    }
  }

  Future<void> _registerDemoHintVisibility() async {
    final launchCount = await FirstRunAuthFlags.registerLoginDemoLaunch();
    if (!mounted) return;
    setState(() {
      _showDemoHint = launchCount <= 2;
    });
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
    _usernameFocusNode.dispose();
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
        GoRouter.of(rootCtx).go('/cash-gate');
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
                    error =
                        'La nueva contraseña debe tener al menos 6 caracteres';
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
                    throw Exception(
                      'No se encontró una cuenta administrador en esta computadora.',
                    );
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
                        content: Text(
                          'Contraseña restablecida. Ya puedes iniciar sesión.',
                        ),
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
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
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
      // `showDialog` completa cuando se llama `Navigator.pop`, pero el diálogo
      // puede seguir en transición (animación). Si se hace dispose inmediato,
      // el `TextField` puede tocar el controller durante el cierre.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      tokenController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const pageBackground = Color(0xFFF5F7FA);
    const cardColor = Color(0xFF374151);
    const cardTitle = Color(0xFFF9FAFB);
    const cardText = Color(0xFFD1D5DB);
    const cardMutedText = Color(0xFFCBD5E1);
    const primaryBlue = Color(0xFF2563EB);
    const inputBackground = Color(0xFFFFFFFF);
    const inputText = Color(0xFF111827);
    const inputHint = Color(0xFF94A3B8);
    const borderColor = Color(0xFF4B5563);
    final subtleBlue = primaryBlue.withOpacity(0.06);
    final dividerColor = Colors.white.withOpacity(0.10);

    final forgotPasswordStyle = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(Colors.white.withOpacity(0.82)),
      overlayColor: WidgetStatePropertyAll(Colors.white.withOpacity(0.06)),
      textStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        return TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          decoration: states.contains(WidgetState.hovered)
              ? TextDecoration.underline
              : TextDecoration.none,
        );
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    InputDecoration decoration({
      required String hint,
      Widget? suffix,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: inputHint, fontSize: 13),
        suffixIcon: suffix,
        filled: true,
        fillColor: inputBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
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
          borderSide: const BorderSide(color: primaryBlue, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 1.6),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFB91C1C),
          fontSize: 12,
          height: 1.2,
        ),
      );
    }

    Widget buildUsernameSuffix() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_usernameController.text.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar usuario',
              onPressed: _isLoading
                  ? null
                  : () {
                      _usernameController.clear();
                      setState(() {
                        _errorMessage = null;
                      });
                      _usernameFocusNode.requestFocus();
                    },
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: inputHint,
              ),
            ),
          PopupMenuButton<String>(
            enabled: !_isLoading && _availableUsers.isNotEmpty,
            tooltip: 'Elegir usuario',
            position: PopupMenuPosition.under,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: inputHint,
            ),
            onSelected: (username) {
              _usernameController.text = username;
              setState(() {
                _errorMessage = null;
              });
              FocusScope.of(context).nextFocus();
            },
            itemBuilder: (context) => _availableUsers
                .map(
                  (user) {
                    final displayName = user.displayName?.trim() ?? '';
                    return PopupMenuItem<String>(
                      value: user.username,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName.isEmpty ? user.username : displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (displayName.isNotEmpty)
                            Text(
                              user.username,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                )
                .toList(),
          ),
          const SizedBox(width: 6),
        ],
      );
    }

    return Scaffold(
      backgroundColor: pageBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFF8FAFD),
                    pageBackground,
                    const Color(0xFFF1F5F9),
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
                color: primaryBlue.withOpacity(0.055),
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4B1D1D),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFFCA5A5),
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _usernameController,
                              focusNode: _usernameFocusNode,
                              style: const TextStyle(color: inputText),
                              cursorColor: primaryBlue,
                              decoration: decoration(
                                hint: 'Ingresa tu usuario',
                                suffix: buildUsernameSuffix(),
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
                              onChanged: (_) {
                                if (_errorMessage != null) {
                                  setState(() {
                                    _errorMessage = null;
                                  });
                                } else {
                                  setState(() {});
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: _usingPin
                                  ? TextFormField(
                                      key: const ValueKey('pinField'),
                                      controller: _pinController,
                                      enabled: !_isLoading,
                                      style: const TextStyle(color: inputText),
                                      cursorColor: primaryBlue,
                                      decoration: decoration(
                                        hint: '4-6 dígitos',
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
                                      onChanged: (_) {
                                        if (_errorMessage != null) {
                                          setState(() {
                                            _errorMessage = null;
                                          });
                                        }
                                      },
                                      onFieldSubmitted: (_) => _handleLogin(),
                                    )
                                  : TextFormField(
                                      key: const ValueKey('passwordField'),
                                      controller: _passwordController,
                                      style: const TextStyle(color: inputText),
                                      cursorColor: primaryBlue,
                                      decoration: decoration(
                                        hint: 'Ingresa tu contraseña',
                                        suffix: IconButton(
                                          tooltip: _obscurePassword
                                              ? 'Mostrar contraseña'
                                              : 'Ocultar contraseña',
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            color: inputHint,
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : () {
                                                  setState(() {
                                                    _obscurePassword =
                                                        !_obscurePassword;
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
                                      onChanged: (_) {
                                        if (_errorMessage != null) {
                                          setState(() {
                                            _errorMessage = null;
                                          });
                                        }
                                      },
                                      onFieldSubmitted: (_) => _handleLogin(),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Transform.scale(
                                  scale: 0.86,
                                  child: Switch(
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
                                    activeColor: Colors.white,
                                    activeTrackColor: primaryBlue.withOpacity(0.9),
                                    inactiveThumbColor: Colors.white,
                                    inactiveTrackColor: Colors.white.withOpacity(0.18),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Usar codigo',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cardText.withOpacity(0.88),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (!_usingPin)
                                  TextButton(
                                    style: forgotPasswordStyle,
                                    onPressed: _isLoading
                                        ? null
                                        : _openForgotPasswordDialog,
                                    child: const Text('Olvidé mi contraseña'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: primaryBlue,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        textStyle: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: _isLoading ? null : _handleLogin,
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('Acceder'),
                                    ),
                                  ),
                                ),
                                if (_showDemoHint) ...[
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: IconButton(
                                      tooltip: _showDemoCredentials
                                          ? 'Ocultar acceso de demo'
                                          : 'Mostrar acceso de demo',
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            Colors.white.withOpacity(0.08),
                                        foregroundColor: Colors.white.withOpacity(
                                          _showDemoCredentials ? 1 : 0.76,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _showDemoCredentials =
                                              !_showDemoCredentials;
                                        });
                                      },
                                      icon: Icon(
                                        _showDemoCredentials
                                            ? Icons.lock_open_rounded
                                            : Icons.lock_outline_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (_showDemoHint && _showDemoCredentials) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: subtleBlue,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Text(
                                  'Demo: admin / admin123',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withOpacity(0.82),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
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
        ],
      ),
    );
  }
}
