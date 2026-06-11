import 'package:flutter/material.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/permission.dart';
import '../../../core/security/authz/permission_gate.dart';
import '../data/user_model.dart';
import '../data/users_repository.dart';
import 'dialogs/user_detail_dialog.dart';
import 'permissions_page.dart';
import 'settings_layout.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const Color _brandBlue = Color(0xFF1A56DB);
  static const Color _pageBg = Color(0xFFF2F6F9);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _darkText = Color(0xFF0F172A);
  static const Color _secondaryText = Color(0xFF64748B);

  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _users = const [];
  bool _loading = true;
  bool _refreshing = false;
  int? _busyUserId;

  String get _query => _searchController.text.trim().toLowerCase();

  List<UserModel> get _visibleUsers {
    final query = _query;
    if (query.isEmpty) return _users;
    return _users.where((user) {
      final haystack =
          '${user.displayLabel} ${user.username} ${user.roleLabel}'.toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  int get _activeCount => _users.where((user) => user.isActiveUser).length;
  int get _adminCount => _users.where((user) => user.isAdmin).length;
  int get _pinCount =>
      _users.where((user) => (user.pin ?? '').trim().isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      if (silent) {
        _refreshing = true;
      } else {
        _loading = true;
      }
    });

    try {
      final users = await UsersRepository.getAll();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (error, stackTrace) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          error,
          stackTrace: stackTrace,
          context: context,
          onRetry: _loadUsers,
          module: 'settings/users/load',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _runUserAction(
    UserModel user,
    Future<void> Function() action, {
    String successMessage = '',
  }) async {
    if (!mounted) return;
    setState(() => _busyUserId = user.id);
    try {
      await action();
      if (!mounted) return;
      if (successMessage.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
      await _loadUsers(silent: true);
    } catch (error, stackTrace) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          error,
          stackTrace: stackTrace,
          context: context,
          module: 'settings/users/action',
        );
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _openUserForm({UserModel? user}) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (context) => _UserFormDialog(user: user),
    );

    if (result == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (user == null) {
      final newUser = UserModel(
        username: result.username,
        displayName: result.displayName,
        role: result.role,
        isActive: result.isActive ? 1 : 0,
        pin: result.pin,
        passwordHash: UsersRepository.hashPassword(result.password!),
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _runUserAction(
        newUser,
        () => UsersRepository.create(newUser),
        successMessage: 'Usuario creado correctamente.',
      );
      return;
    }

    final updated = user.copyWith(
      username: result.username,
      displayName: result.displayName,
      role: result.role,
      isActive: result.isActive ? 1 : 0,
      pin: result.pin,
    );

    await _runUserAction(
      user,
      () async {
        await UsersRepository.update(updated);
        if ((result.password ?? '').trim().isNotEmpty && updated.id != null) {
          await UsersRepository.changePassword(updated.id!, result.password!);
        }
      },
      successMessage: 'Usuario actualizado correctamente.',
    );
  }

  Future<void> _openPasswordDialog(UserModel user) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _SecretValueDialog(
        title: 'Cambiar contraseña',
        subtitle: 'Define una nueva contraseña para ${user.displayLabel}.',
        label: 'Nueva contraseña',
        confirmLabel: 'Confirmar contraseña',
        obscure: true,
        minLength: 4,
      ),
    );

    if (value == null || user.id == null) return;

    await _runUserAction(
      user,
      () => UsersRepository.changePassword(user.id!, value),
      successMessage: 'Contraseña actualizada.',
    );
  }

  Future<void> _openPinDialog(UserModel user) async {
    final value = await showDialog<String?>(
      context: context,
      builder: (context) => _SecretValueDialog(
        title: 'Cambiar PIN',
        subtitle:
            'Puedes dejar el campo vacío para quitar el PIN rápido de ${user.displayLabel}.',
        label: 'PIN',
        confirmLabel: 'Confirmar PIN',
        obscure: true,
        digitsOnly: true,
        minLength: 4,
        allowEmptyValue: true,
      ),
    );

    if (value == null || user.id == null) return;

    await _runUserAction(
      user,
      () => UsersRepository.changePin(
        user.id!,
        value.trim().isEmpty ? null : value,
      ),
      successMessage:
          value.trim().isEmpty ? 'PIN eliminado.' : 'PIN actualizado.',
    );
  }

  Future<void> _openPermissions(UserModel user) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PermissionsPage(user: user)),
    );
    await _loadUsers(silent: true);
  }

  Future<void> _showUserDetail(UserModel user) async {
    final permissions = user.id == null
        ? UserPermissions.none()
        : await UsersRepository.getPermissions(user.id!);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => UserDetailDialog(
        user: user,
        permissions: permissions,
        onEdit: () => _openUserForm(user: user),
        onPermissions: () => _openPermissions(user),
        onChangePassword: () => _openPasswordDialog(user),
        onChangePin: () => _openPinDialog(user),
      ),
    );
  }

  Future<void> _toggleActive(UserModel user) async {
    if (user.id == null) return;
    await _runUserAction(
      user,
      () => UsersRepository.toggleActive(user.id!, !user.isActiveUser),
      successMessage: user.isActiveUser
          ? 'Usuario desactivado.'
          : 'Usuario activado.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Usuarios'),
        ),
        backgroundColor: _pageBg,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              max: 1080,
              child: SizedBox.expand(
                child: PermissionGate(
                  permission: Permissions.settingsPermissions,
                  reason: 'Gestión de usuarios',
                  child: _buildBody(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final users = _visibleUsers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 18),
        _buildToolbar(),
        const SizedBox(height: 16),
        _buildStats(),
        const SizedBox(height: 16),
        Expanded(
          child: users.isEmpty
              ? _buildEmptyState(hasQuery: _query.isNotEmpty)
              : _buildUsersList(users),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Gestión de usuarios',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _darkText,
              letterSpacing: -0.4,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Administra cuentas, acceso operativo y credenciales rápidas desde un solo lugar.',
            style: TextStyle(
              fontSize: 13.5,
              color: _secondaryText,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;

        final searchField = SizedBox(
          height: 48,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, usuario o rol',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Limpiar',
                    ),
            ),
          ),
        );

        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: _refreshing ? null : () => _loadUsers(silent: true),
                tooltip: 'Actualizar',
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _border),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _openUserForm(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuevo usuario'),
              style: FilledButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              actions,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 12),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildStats() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          label: 'Registrados',
          value: _users.length.toString(),
          icon: Icons.group_outlined,
          accent: _brandBlue,
        ),
        _StatCard(
          label: 'Activos',
          value: _activeCount.toString(),
          icon: Icons.verified_user_outlined,
          accent: const Color(0xFF16A34A),
        ),
        _StatCard(
          label: 'Administradores',
          value: _adminCount.toString(),
          icon: Icons.admin_panel_settings_outlined,
          accent: const Color(0xFFF59E0B),
        ),
        _StatCard(
          label: 'Con PIN',
          value: _pinCount.toString(),
          icon: Icons.pin_outlined,
          accent: const Color(0xFF7C3AED),
        ),
      ],
    );
  }

  Widget _buildUsersList(List<UserModel> users) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: const [
                Expanded(
                  flex: 4,
                  child: Text(
                    'Usuario',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _secondaryText,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Rol',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _secondaryText,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Acceso rápido',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _secondaryText,
                    ),
                  ),
                ),
                SizedBox(width: 48),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Expanded(
            child: ListView.separated(
              itemCount: users.length,
              separatorBuilder: (context, _) =>
                  const Divider(height: 1, color: _border),
              itemBuilder: (context, index) => _buildUserRow(users[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(UserModel user) {
    final busy = _busyUserId == user.id;
    final initial = user.displayLabel.isEmpty
        ? '?'
        : user.displayLabel.substring(0, 1).toUpperCase();

    return InkWell(
      onTap: busy ? null : () => _showUserDetail(user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: _brandBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.displayLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: _darkText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(active: user.isActiveUser),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${user.username}',
                          style: const TextStyle(
                            fontSize: 12.8,
                            color: _secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _RolePill(role: user.role),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PinPill(hasPin: (user.pin ?? '').trim().isNotEmpty),
              ),
            ),
            SizedBox(
              width: 48,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : PopupMenuButton<_UserAction>(
                      tooltip: 'Acciones',
                      onSelected: (action) {
                        switch (action) {
                          case _UserAction.view:
                            _showUserDetail(user);
                            break;
                          case _UserAction.edit:
                            _openUserForm(user: user);
                            break;
                          case _UserAction.permissions:
                            _openPermissions(user);
                            break;
                          case _UserAction.password:
                            _openPasswordDialog(user);
                            break;
                          case _UserAction.pin:
                            _openPinDialog(user);
                            break;
                          case _UserAction.toggleActive:
                            _toggleActive(user);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _UserAction.view,
                          child: Text('Ver detalle'),
                        ),
                        const PopupMenuItem(
                          value: _UserAction.edit,
                          child: Text('Editar usuario'),
                        ),
                        const PopupMenuItem(
                          value: _UserAction.permissions,
                          child: Text('Permisos'),
                        ),
                        const PopupMenuItem(
                          value: _UserAction.password,
                          child: Text('Cambiar contraseña'),
                        ),
                        const PopupMenuItem(
                          value: _UserAction.pin,
                          child: Text('Cambiar PIN'),
                        ),
                        PopupMenuItem(
                          value: _UserAction.toggleActive,
                          child: Text(user.isActiveUser ? 'Desactivar' : 'Activar'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool hasQuery}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasQuery ? Icons.search_off_rounded : Icons.people_outline_rounded,
                size: 46,
                color: _secondaryText,
              ),
              const SizedBox(height: 14),
              Text(
                hasQuery
                    ? 'No se encontraron usuarios con ese filtro.'
                    : 'Todavía no hay usuarios registrados.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _darkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasQuery
                    ? 'Prueba con otro nombre, usuario o rol.'
                    : 'Crea el primer usuario para empezar a asignar accesos y credenciales.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: _secondaryText,
                ),
              ),
              if (!hasQuery) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _openUserForm(),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Nuevo usuario'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _UserAction { view, edit, permissions, password, pin, toggleActive }

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final background = active ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final foreground = active ? const Color(0xFF166534) : const Color(0xFFB91C1C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Activo' : 'Inactivo',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    late final Color accent;
    late final String label;

    switch (role) {
      case 'admin':
        accent = const Color(0xFFF59E0B);
        label = 'Administrador';
        break;
      case 'supervisor':
        accent = const Color(0xFF7C3AED);
        label = 'Supervisor';
        break;
      default:
        accent = const Color(0xFF1A56DB);
        label = 'Cajero';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}

class _PinPill extends StatelessWidget {
  const _PinPill({required this.hasPin});

  final bool hasPin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: hasPin ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        hasPin ? 'Configurado' : 'Sin PIN',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: hasPin ? const Color(0xFF1A56DB) : const Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user});

  final UserModel? user;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _pinController;

  late String _role;
  late bool _isActive;
  bool _saving = false;
  bool _showPassword = false;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _displayNameController = TextEditingController(text: user?.displayName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _passwordController = TextEditingController();
    _pinController = TextEditingController(text: user?.pin ?? '');
    _role = user?.role ?? 'cashier';
    _isActive = user?.isActiveUser ?? true;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _saving = true);
    try {
      final exists = await UsersRepository.usernameExists(
        _usernameController.text.trim(),
        excludeId: widget.user?.id,
      );
      if (!mounted) return;
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ese nombre de usuario ya existe.')),
        );
        setState(() => _saving = false);
        return;
      }

      Navigator.pop(
        context,
        _UserFormResult(
          username: _usernameController.text.trim(),
          displayName: _displayNameController.text.trim().isEmpty
              ? null
              : _displayNameController.text.trim(),
          password: _passwordController.text.trim().isEmpty
              ? null
              : _passwordController.text.trim(),
          pin: _pinController.text.trim().isEmpty ? null : _pinController.text.trim(),
          role: _role,
          isActive: _isActive,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar usuario' : 'Nuevo usuario'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre para mostrar',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Ingresa un usuario.';
                    if (text.length < 3) return 'Debe tener al menos 3 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cashier', child: Text('Cajero')),
                    DropdownMenuItem(
                      value: 'supervisor',
                      child: Text('Supervisor'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrador'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _role = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: _isEditing
                        ? 'Nueva contraseña (opcional)'
                        : 'Contraseña inicial',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (!_isEditing && text.isEmpty) {
                      return 'Ingresa una contraseña inicial.';
                    }
                    if (text.isNotEmpty && text.length < 4) {
                      return 'Debe tener al menos 4 caracteres.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PIN rápido (opcional)',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    if (!RegExp(r'^\d+$').hasMatch(text)) {
                      return 'El PIN debe contener solo números.';
                    }
                    if (text.length < 4) {
                      return 'El PIN debe tener al menos 4 dígitos.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usuario activo'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _UserFormResult {
  const _UserFormResult({
    required this.username,
    required this.displayName,
    required this.password,
    required this.pin,
    required this.role,
    required this.isActive,
  });

  final String username;
  final String? displayName;
  final String? password;
  final String? pin;
  final String role;
  final bool isActive;
}

class _SecretValueDialog extends StatefulWidget {
  const _SecretValueDialog({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.confirmLabel,
    this.obscure = true,
    this.digitsOnly = false,
    this.minLength = 4,
    this.allowEmptyValue = false,
  });

  final String title;
  final String subtitle;
  final String label;
  final String confirmLabel;
  final bool obscure;
  final bool digitsOnly;
  final int minLength;
  final bool allowEmptyValue;

  @override
  State<_SecretValueDialog> createState() => _SecretValueDialogState();
}

class _SecretValueDialogState extends State<_SecretValueDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _showValue = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _valueController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _valueController,
                keyboardType:
                    widget.digitsOnly ? TextInputType.number : TextInputType.text,
                obscureText: widget.obscure && !_showValue,
                decoration: InputDecoration(
                  labelText: widget.label,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: widget.obscure
                      ? IconButton(
                          onPressed: () => setState(() => _showValue = !_showValue),
                          icon: Icon(
                            _showValue
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        )
                      : null,
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty && widget.allowEmptyValue) return null;
                  if (text.isEmpty) return 'Completa este campo.';
                  if (widget.digitsOnly && !RegExp(r'^\d+$').hasMatch(text)) {
                    return 'Solo se permiten números.';
                  }
                  if (text.length < widget.minLength) {
                    return 'Debe tener al menos ${widget.minLength} caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                keyboardType:
                    widget.digitsOnly ? TextInputType.number : TextInputType.text,
                obscureText: widget.obscure && !_showConfirm,
                decoration: InputDecoration(
                  labelText: widget.confirmLabel,
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: widget.obscure
                      ? IconButton(
                          onPressed: () =>
                              setState(() => _showConfirm = !_showConfirm),
                          icon: Icon(
                            _showConfirm
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        )
                      : null,
                ),
                validator: (value) {
                  if ((value ?? '').trim() != _valueController.text.trim()) {
                    return 'Los valores no coinciden.';
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(context, _valueController.text.trim());
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
