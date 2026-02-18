import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/session/ui_preferences.dart';
import '../../../core/session/session_manager.dart';
import '../../auth/services/logout_flow_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../settings/data/user_model.dart';
import '../../settings/data/users_repository.dart';

/// Página de cuenta de usuario
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _loading = true;
  UserModel? _user;
  String? _sessionUsername;
  String? _sessionDisplayName;
  String? _sessionRole;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final username = await SessionManager.username();
    final displayName = await SessionManager.displayName();
    final role = await SessionManager.role();

    final user = await AuthRepository.getCurrentUser();

    if (!mounted) return;
    setState(() {
      _sessionUsername = username;
      _sessionDisplayName = displayName;
      _sessionRole = role;
      _user = user;
      _loading = false;
    });
  }

  Future<void> _openEditProfile() async {
    final user = _user;
    if (user == null) return;

    final scheme = Theme.of(context).colorScheme;

    final displayNameCtrl = TextEditingController(text: user.displayName ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar Perfil'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: user.username,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  TextFormField(
                    controller: displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre para mostrar',
                      hintText: 'Ej: Juan Pérez',
                      prefixIcon: Icon(Icons.badge),
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isNotEmpty && value.length < 2) {
                        return 'El nombre debe tener al menos 2 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoPill(label: 'Rol', value: user.roleLabel),
                      ),
                      const SizedBox(width: AppSizes.paddingM),
                      Expanded(
                        child: _InfoPill(
                          label: 'Estado',
                          value: user.isActiveUser ? 'Activo' : 'Inactivo',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(context, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final newDisplayName = displayNameCtrl.text.trim();
    final updated = user.copyWith(
      displayName: newDisplayName.isEmpty ? null : newDisplayName,
    );

    try {
      await UsersRepository.update(updated);
      await SessionManager.setDisplayName(updated.displayLabel);
      if (!mounted) return;
      setState(() {
        _user = updated;
        _sessionDisplayName = updated.displayLabel;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Perfil actualizado',
            style: TextStyle(color: scheme.onPrimary),
          ),
          backgroundColor: scheme.primary,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo actualizar el perfil',
            style: TextStyle(color: scheme.onError),
          ),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  Future<void> _openChangePassword() async {
    final user = _user;
    if (user == null || user.id == null) return;

    final scheme = Theme.of(context).colorScheme;

    final formKey = GlobalKey<FormState>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    bool showCurrent = false;
    bool showNew = false;
    bool showConfirm = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Cambiar Contraseña'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user.hasPassword) ...[
                        TextFormField(
                          controller: currentCtrl,
                          obscureText: !showCurrent,
                          decoration: InputDecoration(
                            labelText: 'Contraseña actual',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setLocal(() => showCurrent = !showCurrent),
                              icon: Icon(
                                showCurrent
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (!user.hasPassword) return null;
                            if ((v ?? '').isEmpty) {
                              return 'Ingrese la contraseña actual';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSizes.paddingM),
                      ],
                      TextFormField(
                        controller: newCtrl,
                        obscureText: !showNew,
                        decoration: InputDecoration(
                          labelText: user.hasPassword
                              ? 'Nueva contraseña'
                              : 'Establecer contraseña',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            onPressed: () => setLocal(() => showNew = !showNew),
                            icon: Icon(
                              showNew ? Icons.visibility_off : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (v) {
                          final value = (v ?? '');
                          if (value.isEmpty) {
                            return 'Ingrese la nueva contraseña';
                          }
                          if (value.length < 4) {
                            return 'Debe tener al menos 4 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSizes.paddingM),
                      TextFormField(
                        controller: confirmCtrl,
                        obscureText: !showConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: const Icon(Icons.lock_reset),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setLocal(() => showConfirm = !showConfirm),
                            icon: Icon(
                              showConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) {
                            return 'Confirme la contraseña';
                          }
                          if (v != newCtrl.text) {
                            return 'Las contraseñas no coinciden';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;

    try {
      if (user.hasPassword) {
        final ok = await UsersRepository.verifyCredentials(
          user.username,
          currentCtrl.text,
        );
        if (ok == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Contraseña actual incorrecta',
                style: TextStyle(color: scheme.onError),
              ),
              backgroundColor: scheme.error,
            ),
          );
          return;
        }
      }

      await UsersRepository.changePassword(user.id!, newCtrl.text);
      if (!mounted) return;
      // Refrescar usuario (para que user.hasPassword quede true)
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Contraseña actualizada',
            style: TextStyle(color: scheme.onPrimary),
          ),
          backgroundColor: scheme.primary,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo cambiar la contraseña',
            style: TextStyle(color: scheme.onError),
          ),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  Future<void> _openPreferences() async {
    final current = await UiPreferences.isSidebarCollapsed();
    if (!mounted) return;

    bool collapsed = current;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Preferencias'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      value: collapsed,
                      onChanged: (v) async {
                        setLocal(() => collapsed = v);
                        await UiPreferences.setSidebarCollapsed(v);
                      },
                      title: const Text('Menú lateral colapsado'),
                      subtitle: const Text(
                        'Mantener el menú compacto por defecto.',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: scheme.primary)),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = _user;
    final titleName = (_sessionDisplayName?.isNotEmpty == true)
        ? _sessionDisplayName!
        : (_sessionUsername ?? 'Usuario');

    Widget sectionTitle(String text, {IconData? icon}) {
      return Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: scheme.onSurface,
            ),
          ),
        ],
      );
    }

    Widget card({required Widget child}) {
      final bg = scheme.surfaceContainerHighest;
      final border = scheme.outlineVariant.withOpacity(0.45);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: child,
      );
    }

    Future<void> confirmLogout() async {
      await LogoutFlowService.requestLogout(
        context,
        performLogout: () => LogoutFlowService.defaultPerformLogout(context),
      );
    }

    final roleLabel =
        user?.roleLabel ??
        (_sessionRole == 'admin' ? 'Administrador' : 'Cajero');

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final isWide = maxWidth >= 980;
          final contentMaxWidth = isWide ? 1100.0 : 760.0;
          final outerPadding = (maxWidth >= 520)
              ? const EdgeInsets.all(18)
              : const EdgeInsets.all(12);

          Widget profileHeader() {
            final avatarBg = Color.alphaBlend(
              scheme.primary.withOpacity(0.18),
              scheme.surfaceContainerHighest,
            );
            final avatarFg = scheme.primary;

            return card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: avatarBg,
                          border: Border.all(
                            color: scheme.primary.withOpacity(0.35),
                            width: 2,
                          ),
                        ),
                        child: Icon(Icons.person, size: 36, color: avatarFg),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurface,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '@${_sessionUsername ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface.withOpacity(0.70),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            scheme.primary.withOpacity(0.14),
                            scheme.surfaceContainerHighest,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: scheme.primary.withOpacity(0.30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              roleLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoPill(
                          label: 'Usuario',
                          value: _sessionUsername ?? '—',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InfoPill(
                          label: 'Estado',
                          value: (user?.isActiveUser ?? true)
                              ? 'Activo'
                              : 'Inactivo',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          Widget actionsCard() {
            return card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle('Acciones', icon: Icons.tune),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit, color: scheme.primary),
                    title: const Text('Editar perfil'),
                    subtitle: const Text('Nombre para mostrar y datos básicos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: user == null ? null : _openEditProfile,
                  ),
                  const Divider(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock, color: scheme.primary),
                    title: const Text('Cambiar contraseña'),
                    subtitle: const Text('Actualiza tu contraseña de acceso'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: user == null ? null : _openChangePassword,
                  ),
                  const Divider(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.view_sidebar_outlined,
                      color: scheme.primary,
                    ),
                    title: const Text('Preferencias'),
                    subtitle: const Text('Ajustes de interfaz del sistema'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openPreferences,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: confirmLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          Widget missingUserCard() {
            return card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle('Sesión', icon: Icons.warning_amber_rounded),
                  const SizedBox(height: 8),
                  Text(
                    'No hay un usuario cargado en la sesión.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withOpacity(0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.login),
                      label: const Text('Ir a iniciar sesión'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final content = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            profileHeader(),
                            const SizedBox(height: 14),
                            if (user == null) missingUserCard(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: actionsCard()),
                    ],
                  )
                : Column(
                    children: [
                      profileHeader(),
                      const SizedBox(height: 14),
                      if (user == null) missingUserCard(),
                      const SizedBox(height: 14),
                      actionsCard(),
                    ],
                  ),
          );

          return Center(
            child: SingleChildScrollView(padding: outerPadding, child: content),
          );
        },
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = scheme.surfaceContainerHighest;
    final border = scheme.outlineVariant.withOpacity(0.45);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingM,
        vertical: AppSizes.paddingS,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface.withOpacity(0.70),
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}
