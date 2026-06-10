import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  bool _showSuccessTransition = false;
  _LoginMode _mode = _LoginMode.password;
  String? _errorMessage;

  bool get _usingPin => _mode == _LoginMode.pin;

  @override
  void initState() {
    super.initState();
    unawaited(_maybePrefillFirstRunCredentials());
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

  Future<void> _playSuccessTransition() async {
    if (!mounted) return;
    setState(() {
      _showSuccessTransition = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 720));
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
              await _playSuccessTransition();
              if (!mounted) return;
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
        await _playSuccessTransition();
        if (!mounted) return;
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
    const cardColor = Color(0xFFFFFFFF);
    const cardBorder = Color(0xFFE2E8F0);
    const cardText = Color(0xFF334155);
    const subtitleText = Color(0xFF64748B);
    const primaryBlue = Color(0xFF2563EB);
    const primaryBluePressed = Color(0xFF1D4ED8);
    const inputBackground = Color(0xFFF8FAFC);
    const inputText = Color(0xFF111827);
    const inputHint = Color(0xFF94A3B8);
    const fieldBorder = Color(0xFFCBD5E1);
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 560;
    final ultraCompact = viewport.width < 420;
    final panelRadius = ultraCompact ? 22.0 : 28.0;
    final panelPadding = ultraCompact ? 20.0 : (compact ? 24.0 : 30.0);
    final shellHorizontalPadding = ultraCompact ? 12.0 : 18.0;
    final shellVerticalPadding = ultraCompact ? 16.0 : 28.0;
    final fieldVerticalPadding = ultraCompact ? 9.0 : 11.0;
    final titleSize = ultraCompact ? 18.0 : 22.0;
    final subtitleSize = ultraCompact ? 13.0 : 14.0;
    final fieldTextSize = ultraCompact ? 13.0 : 14.0;
    final fieldLabelSize = ultraCompact ? 12.0 : 13.0;
    final optionContainerRadius = ultraCompact ? 14.0 : 16.0;
    final actionHeight = ultraCompact ? 48.0 : 52.0;
    final forgotPasswordStyle = ButtonStyle(
      foregroundColor: const WidgetStatePropertyAll(Color(0xFF334155)),
      overlayColor: WidgetStatePropertyAll(primaryBlue.withOpacity(0.06)),
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

    InputDecoration decoration({required String hint, Widget? suffix}) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: inputHint, fontSize: 13),
        suffixIcon: suffix,
        filled: true,
        fillColor: inputBackground,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: fieldVerticalPadding,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryBlue, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: fieldBorder),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.4),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFB91C1C),
          fontSize: 12,
          height: 1.2,
        ),
      );
    }

    Widget buildFieldBlock({
      required String label,
      required Widget child,
      Key? key,
      double spacing = 8,
    }) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cardText.withOpacity(0.96),
              fontWeight: FontWeight.w600,
              fontSize: fieldLabelSize,
              letterSpacing: 0.1,
            ),
          ),
          SizedBox(height: spacing),
          child,
        ],
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
              icon: const Icon(Icons.close_rounded, size: 18, color: inputHint),
            ),
          Theme(
            data: theme.copyWith(
              popupMenuTheme: PopupMenuThemeData(
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 18,
                shadowColor: const Color(0x220F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                textStyle: const TextStyle(color: inputText),
              ),
            ),
            child: PopupMenuButton<String>(
              enabled: !_isLoading && _availableUsers.isNotEmpty,
              tooltip: 'Elegir usuario',
              position: PopupMenuPosition.under,
              constraints: const BoxConstraints(minWidth: 300),
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              offset: const Offset(0, 8),
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
              itemBuilder: (context) => _availableUsers.map((user) {
                return PopupMenuItem<String>(
                  value: user.username,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: SizedBox(
                    width: 300,
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            size: 15,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            user.username,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 16,
                              height: 1.28,
                              color: inputText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth =
                    (constraints.maxWidth - (shellHorizontalPadding * 2))
                        .clamp(280.0, 420.0)
                        .toDouble();
                final stackOptions = constraints.maxWidth < 430;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: shellHorizontalPadding,
                    vertical: shellVerticalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          (constraints.maxHeight - (shellVerticalPadding * 2))
                              .clamp(0.0, double.infinity),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: panelWidth),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(panelRadius),
                            border: Border.all(
                              color: primaryBlue.withOpacity(0.18),
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
                              ultraCompact ? 20 : 26,
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
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: cardBorder.withOpacity(0.9),
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Iniciar sesión',
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                color: const Color(0xFF0F172A),
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: -0.2,
                                                fontSize: titleSize,
                                              ),
                                        ),
                                        SizedBox(height: ultraCompact ? 4 : 6),
                                        Text(
                                          'Accede al sistema para continuar',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: subtitleText,
                                                height: 1.35,
                                                fontSize: subtitleSize,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: ultraCompact ? 16 : 20),
                                  if (_errorMessage != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4B1D1D),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF7F1D1D),
                                        ),
                                      ),
                                      child: Text(
                                        _errorMessage!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFFFCA5A5),
                                              fontWeight: FontWeight.w600,
                                              height: 1.25,
                                            ),
                                      ),
                                    ),
                                    SizedBox(height: ultraCompact ? 14 : 18),
                                  ],
                                  buildFieldBlock(
                                    label: 'Usuario',
                                    child: TextFormField(
                                      controller: _usernameController,
                                      focusNode: _usernameFocusNode,
                                      style: TextStyle(
                                        color: inputText,
                                        fontSize: fieldTextSize,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      cursorColor: primaryBlue,
                                      decoration: decoration(
                                        hint: 'Ingresa tu usuario',
                                        suffix: buildUsernameSuffix(),
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
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
                                  ),
                                  SizedBox(height: ultraCompact ? 14 : 18),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    child: _usingPin
                                        ? buildFieldBlock(
                                            key: const ValueKey(
                                              'pinFieldBlock',
                                            ),
                                            label: 'Código',
                                            child: TextFormField(
                                              key: const ValueKey('pinField'),
                                              controller: _pinController,
                                              enabled: !_isLoading,
                                              style: TextStyle(
                                                color: inputText,
                                                fontSize: fieldTextSize,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              cursorColor: primaryBlue,
                                              decoration: decoration(
                                                hint: '4-6 dígitos',
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              obscureText: true,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                                LengthLimitingTextInputFormatter(
                                                  6,
                                                ),
                                              ],
                                              validator: (_) {
                                                final value = _pinController
                                                    .text
                                                    .trim();
                                                if (value.length < 4) {
                                                  return 'PIN mínimo de 4 dígitos';
                                                }
                                                return null;
                                              },
                                              textInputAction:
                                                  TextInputAction.done,
                                              onChanged: (_) {
                                                if (_errorMessage != null) {
                                                  setState(() {
                                                    _errorMessage = null;
                                                  });
                                                }
                                              },
                                              onFieldSubmitted: (_) =>
                                                  _handleLogin(),
                                            ),
                                          )
                                        : buildFieldBlock(
                                            key: const ValueKey(
                                              'passwordFieldBlock',
                                            ),
                                            label: 'Contraseña',
                                            child: TextFormField(
                                              key: const ValueKey(
                                                'passwordField',
                                              ),
                                              controller: _passwordController,
                                              style: TextStyle(
                                                color: inputText,
                                                fontSize: fieldTextSize,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              cursorColor: primaryBlue,
                                              decoration: decoration(
                                                hint: 'Ingresa tu contraseña',
                                              ),
                                              obscureText: true,
                                              validator: (value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  return 'Ingrese una contraseña';
                                                }
                                                return null;
                                              },
                                              enabled: !_isLoading,
                                              textInputAction:
                                                  TextInputAction.done,
                                              onChanged: (_) {
                                                if (_errorMessage != null) {
                                                  setState(() {
                                                    _errorMessage = null;
                                                  });
                                                }
                                              },
                                              onFieldSubmitted: (_) =>
                                                  _handleLogin(),
                                            ),
                                          ),
                                  ),
                                  SizedBox(height: ultraCompact ? 12 : 16),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: ultraCompact ? 12 : 14,
                                      vertical: ultraCompact ? 9 : 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(
                                        optionContainerRadius,
                                      ),
                                      border: Border.all(
                                        color: primaryBlue.withOpacity(0.18),
                                      ),
                                    ),
                                    child: stackOptions
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  Transform.scale(
                                                    scale: 0.82,
                                                    child: Switch(
                                                      value: _usingPin,
                                                      onChanged: _isLoading
                                                          ? null
                                                          : (value) {
                                                              FocusScope.of(
                                                                context,
                                                              ).unfocus();
                                                              _setMode(
                                                                value
                                                                    ? _LoginMode
                                                                          .pin
                                                                    : _LoginMode
                                                                          .password,
                                                              );
                                                            },
                                                      activeColor: Colors.white,
                                                      activeTrackColor:
                                                          primaryBlue
                                                              .withOpacity(
                                                                0.95,
                                                              ),
                                                      trackOutlineColor:
                                                          WidgetStateProperty.resolveWith((
                                                            states,
                                                          ) {
                                                            if (states.contains(
                                                              WidgetState
                                                                  .selected,
                                                            )) {
                                                              return primaryBlue
                                                                  .withOpacity(
                                                                    0.52,
                                                                  );
                                                            }
                                                            return const Color(
                                                              0xFF93C5FD,
                                                            );
                                                          }),
                                                      trackOutlineWidth:
                                                          const WidgetStatePropertyAll(
                                                            1.5,
                                                          ),
                                                      inactiveThumbColor:
                                                          Colors.white,
                                                      inactiveTrackColor:
                                                          const Color(
                                                            0xFFE2E8F0,
                                                          ),
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'Usar código',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: cardText
                                                                .withOpacity(
                                                                  0.9,
                                                                ),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (!_usingPin) ...[
                                                const SizedBox(height: 6),
                                                Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: TextButton(
                                                    style: forgotPasswordStyle,
                                                    onPressed: _isLoading
                                                        ? null
                                                        : _openForgotPasswordDialog,
                                                    child: const Text(
                                                      'Olvidé mi contraseña',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              Transform.scale(
                                                scale: 0.82,
                                                child: Switch(
                                                  value: _usingPin,
                                                  onChanged: _isLoading
                                                      ? null
                                                      : (value) {
                                                          FocusScope.of(
                                                            context,
                                                          ).unfocus();
                                                          _setMode(
                                                            value
                                                                ? _LoginMode.pin
                                                                : _LoginMode
                                                                      .password,
                                                          );
                                                        },
                                                  activeColor: Colors.white,
                                                  activeTrackColor: primaryBlue
                                                      .withOpacity(0.95),
                                                  trackOutlineColor:
                                                      WidgetStateProperty.resolveWith(
                                                        (states) {
                                                          if (states.contains(
                                                            WidgetState
                                                                .selected,
                                                          )) {
                                                            return primaryBlue
                                                                .withOpacity(
                                                                  0.52,
                                                                );
                                                          }
                                                          return const Color(
                                                            0xFF93C5FD,
                                                          );
                                                        },
                                                      ),
                                                  trackOutlineWidth:
                                                      const WidgetStatePropertyAll(
                                                        1.5,
                                                      ),
                                                  inactiveThumbColor:
                                                      Colors.white,
                                                  inactiveTrackColor:
                                                      const Color(0xFFE2E8F0),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Usar código',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: cardText
                                                            .withOpacity(0.9),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                              ),
                                              if (!_usingPin)
                                                TextButton(
                                                  style: forgotPasswordStyle,
                                                  onPressed: _isLoading
                                                      ? null
                                                      : _openForgotPasswordDialog,
                                                  child: const Text(
                                                    'Olvidé mi contraseña',
                                                  ),
                                                ),
                                            ],
                                          ),
                                  ),
                                  SizedBox(height: ultraCompact ? 18 : 24),
                                  SizedBox(
                                    height: actionHeight,
                                    child: FilledButton(
                                      style: ButtonStyle(
                                        backgroundColor:
                                            WidgetStateProperty.resolveWith((
                                              states,
                                            ) {
                                              if (states.contains(
                                                WidgetState.disabled,
                                              )) {
                                                return primaryBlue.withOpacity(
                                                  0.45,
                                                );
                                              }
                                              if (states.contains(
                                                WidgetState.pressed,
                                              )) {
                                                return primaryBluePressed;
                                              }
                                              return primaryBlue;
                                            }),
                                        foregroundColor:
                                            const WidgetStatePropertyAll(
                                              Colors.white,
                                            ),
                                        elevation: const WidgetStatePropertyAll(
                                          0,
                                        ),
                                        overlayColor: WidgetStatePropertyAll(
                                          Colors.white.withOpacity(0.06),
                                        ),
                                        textStyle: WidgetStatePropertyAll(
                                          TextStyle(
                                            fontSize: ultraCompact ? 13.5 : 14,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        shape: WidgetStatePropertyAll(
                                          RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                      ),
                                      onPressed: _isLoading
                                          ? null
                                          : _handleLogin,
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
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_showSuccessTransition)
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.05),
                          radius: 1.1 + (value * 0.32),
                          colors: [
                            Color.lerp(
                              primaryBlue.withOpacity(0.18),
                              primaryBlue.withOpacity(0.34),
                              value,
                            )!,
                            Color.lerp(
                              const Color(0xFFDBEAFE).withOpacity(0.76),
                              const Color(0xFFEFF6FF).withOpacity(0.94),
                              value,
                            )!,
                            Colors.white,
                          ],
                          stops: const [0.0, 0.42, 1.0],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Transform.scale(
                              scale: 0.86 + (value * 0.24),
                              child: Opacity(
                                opacity: 1 - (value * 0.22),
                                child: Container(
                                  width: 148 + (value * 120),
                                  height: 148 + (value * 120),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: primaryBlue.withOpacity(
                                        0.24 - (value * 0.12),
                                      ),
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: Transform.scale(
                              scale: 0.9 + (value * 0.18),
                              child: Container(
                                width: 86,
                                height: 86,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      const Color(0xFF60A5FA).withOpacity(0.92),
                                      primaryBlue.withOpacity(0.98),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryBlue.withOpacity(0.22),
                                      blurRadius: 34,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 38,
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0.36 * (1 - value),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withOpacity(0),
                                      primaryBlue.withOpacity(0.08),
                                      Colors.white.withOpacity(0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
