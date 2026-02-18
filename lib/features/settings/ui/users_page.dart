import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/errors/error_handler.dart';
import '../data/user_model.dart';
import '../data/users_repository.dart';
import '../../../core/services/cloud_sync_service.dart';
import 'dialogs/user_detail_dialog.dart';
import 'permissions_page.dart';
import 'settings_layout.dart';

/// Página de gestión de usuarios
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  List<UserModel> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    _safeSetState(() => _isLoading = true);
    try {
      final users = await DbHardening.instance.runDbSafe<List<UserModel>>(
        UsersRepository.getAll,
        stage: 'settings/users/load',
      );

      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() => _users = users);
    } catch (e, st) {
      if (!mounted || seq != _loadSeq) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadUsers,
        module: 'settings/users/load',
      );
    } finally {
      if (mounted && seq == _loadSeq) {
        _safeSetState(() => _isLoading = false);
      }
    }
  }

  List<UserModel> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final query = _searchQuery.toLowerCase();
    return _users
        .where(
          (u) =>
              u.username.toLowerCase().contains(query) ||
              (u.displayName?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        backgroundColor: _scheme.surfaceVariant,
        body: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _scheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: _scheme.shadow.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Volver',
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _scheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.people, color: _scheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GESTIÓN DE USUARIOS',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Administra los accesos al sistema',
                          style: TextStyle(
                            color: _scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Buscador
                  SizedBox(
                    width: 250,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar usuario...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: _scheme.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showUserDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('NUEVO USUARIO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _scheme.primary,
                      foregroundColor: _scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Stats cards
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildStatCard(
                    'Total Usuarios',
                    _users.length.toString(),
                    Icons.people,
                    _scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    'Administradores',
                    _users.where((u) => u.isAdmin).length.toString(),
                    Icons.admin_panel_settings,
                    _scheme.tertiary,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    'Cajeros',
                    _users.where((u) => u.isCashier).length.toString(),
                    Icons.point_of_sale,
                    _scheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    'Activos',
                    _users.where((u) => u.isActiveUser).length.toString(),
                    Icons.check_circle,
                    _scheme.tertiary,
                  ),
                ],
              ),
            ),

            // Lista de usuarios
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_off,
                            size: 64,
                            color: _scheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No hay usuarios registrados'
                                : 'No se encontraron resultados',
                            style: TextStyle(color: _scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        return _buildUserCard(user);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _scheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: _scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    final isAdmin = user.isAdmin;
    final roleColor = isAdmin ? _scheme.tertiary : _scheme.secondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showUserDetailDialog(user),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    user.displayLabel.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: roleColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          user.displayLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!user.isActiveUser) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _scheme.error.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'INACTIVO',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _scheme.error.withOpacity(0.9),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      style: TextStyle(
                        fontSize: 13,
                        color: _scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Role badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: roleColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAdmin
                          ? Icons.admin_panel_settings
                          : Icons.point_of_sale,
                      size: 16,
                      color: roleColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      user.roleLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: roleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // PIN indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: user.pin != null
                      ? _scheme.tertiary.withOpacity(0.12)
                      : _scheme.secondary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      user.pin != null ? Icons.lock : Icons.lock_open,
                      size: 14,
                      color: user.pin != null
                          ? _scheme.tertiary
                          : _scheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      user.pin != null ? 'PIN' : 'Sin PIN',
                      style: TextStyle(
                        fontSize: 11,
                        color: user.pin != null
                            ? _scheme.tertiary.withOpacity(0.9)
                            : _scheme.secondary.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Actions
              PopupMenuButton<String>(
                onSelected: (action) => _handleUserAction(action, user),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'permissions',
                    child: Row(
                      children: [
                        Icon(Icons.security, size: 18),
                        SizedBox(width: 8),
                        Text('Permisos'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'password',
                    child: Row(
                      children: [
                        Icon(Icons.lock, size: 18),
                        SizedBox(width: 8),
                        Text('Cambiar contraseña'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(Icons.password, size: 18),
                        SizedBox(width: 8),
                        Text('Cambiar PIN'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          user.isActiveUser ? Icons.block : Icons.check_circle,
                          size: 18,
                          color: user.isActiveUser
                              ? _scheme.secondary
                              : _scheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(user.isActiveUser ? 'Desactivar' : 'Activar'),
                      ],
                    ),
                  ),
                  if (user.username != 'admin')
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 18, color: _scheme.error),
                          const SizedBox(width: 8),
                          Text(
                            'Eliminar',
                            style: TextStyle(color: _scheme.error),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _scheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.more_vert, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserDetailDialog(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => UserDetailDialog(
        user: user,
        onEdit: () => _showUserDialog(user: user),
        onPermissions: () => _showPermissionsDialog(user),
        onChangePassword: () => _showChangePasswordDialog(user),
        onChangePin: () => _showChangePinDialog(user),
      ),
    );
  }

  void _handleUserAction(String action, UserModel user) {
    switch (action) {
      case 'edit':
        _showUserDialog(user: user);
        break;
      case 'permissions':
        _showPermissionsDialog(user);
        break;
      case 'password':
        _showChangePasswordDialog(user);
        break;
      case 'pin':
        _showChangePinDialog(user);
        break;
      case 'toggle':
        _toggleUserActive(user);
        break;
      case 'delete':
        _confirmDeleteUser(user);
        break;
    }
  }

  Future<void> _showUserDialog({UserModel? user}) async {
    final isEditing = user != null;
    final usernameController = TextEditingController(
      text: user?.username ?? '',
    );
    final cloudUsernameController = TextEditingController(
      text: user?.cloudUsername ?? '',
    );
    final displayNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
    final passwordController = TextEditingController();
    final pinController = TextEditingController(text: user?.pin ?? '');
    String selectedRole = user?.role ?? 'cashier';
    bool obscurePassword = true;

    bool cloudUsernameChecking = false;
    bool? cloudUsernameAvailable;
    String? cloudUsernameError;
    Timer? cloudUsernameDebounce;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _scheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isEditing ? Icons.edit : Icons.person_add,
                  color: _scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(isEditing ? 'EDITAR USUARIO' : 'NUEVO USUARIO'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Username
                  TextField(
                    controller: usernameController,
                    enabled: !isEditing || user.username != 'admin',
                    decoration: InputDecoration(
                      labelText: 'Usuario *',
                      hintText: 'nombre.usuario',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (selectedRole == 'admin') ...[
                    TextField(
                      controller: cloudUsernameController,
                      decoration: InputDecoration(
                        labelText: 'Usuario de la nube *',
                        hintText: 'ej: admin_101234567 o tu correo',
                        prefixIcon: const Icon(Icons.cloud),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        helperText:
                            'Este usuario es para iniciar sesión en FULLPOS Owner (nube).',
                        errorText: cloudUsernameError,
                        suffixIcon: cloudUsernameChecking
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : (cloudUsernameAvailable == null)
                            ? null
                            : Icon(
                                cloudUsernameAvailable == true
                                    ? Icons.check_circle
                                    : Icons.error,
                                color: cloudUsernameAvailable == true
                                    ? _scheme.tertiary
                                    : _scheme.error,
                              ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-z0-9._@-]'),
                        ),
                        LengthLimitingTextInputFormatter(50),
                      ],
                      onChanged: (v) {
                        final value = v.trim().toLowerCase();
                        if (value != v) {
                          cloudUsernameController.value =
                              cloudUsernameController.value.copyWith(
                                text: value,
                                selection: TextSelection.collapsed(
                                  offset: value.length,
                                ),
                              );
                        }
                        setDialogState(() {
                          cloudUsernameError = null;
                          cloudUsernameAvailable = null;
                        });

                        cloudUsernameDebounce?.cancel();
                        if (value.length < 3) return;
                        cloudUsernameDebounce = Timer(
                          const Duration(milliseconds: 500),
                          () async {
                            setDialogState(() {
                              cloudUsernameChecking = true;
                              cloudUsernameError = null;
                            });
                            final ok = await CloudSyncService.instance
                                .checkCloudUsernameAvailable(
                                  cloudUsername: value,
                                );
                            if (!context.mounted) return;
                            setDialogState(() {
                              cloudUsernameChecking = false;
                              cloudUsernameAvailable = ok;
                              if (!ok) {
                                cloudUsernameError =
                                    'Ese usuario ya existe en la nube o no se pudo validar';
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Display Name
                  TextField(
                    controller: displayNameController,
                    decoration: InputDecoration(
                      labelText: 'Nombre completo',
                      hintText: 'Juan Pérez',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: isEditing
                          ? 'Nueva contraseña'
                          : 'Contraseña *',
                      hintText: isEditing
                          ? 'Dejar vacío para no cambiar'
                          : 'Mínimo 6 caracteres',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      helperText: isEditing
                          ? 'Solo si desea cambiarla'
                          : 'Requerida para iniciar sesión',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // PIN
                  TextField(
                    controller: pinController,
                    decoration: InputDecoration(
                      labelText: 'PIN de acceso',
                      hintText: '4-6 dígitos',
                      prefixIcon: const Icon(Icons.password),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      helperText: 'Opcional - para acceso rápido',
                    ),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Role selector
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rol del usuario',
                          style: TextStyle(
                            fontSize: 12,
                            color: _scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRoleOption(
                                'admin',
                                'Administrador',
                                Icons.admin_panel_settings,
                                _scheme.tertiary,
                                selectedRole,
                                user?.username == 'admin',
                                (role) => setDialogState(() {
                                  selectedRole = role;
                                  cloudUsernameError = null;
                                  cloudUsernameAvailable = null;
                                }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildRoleOption(
                                'cashier',
                                'Cajero',
                                Icons.point_of_sale,
                                _scheme.secondary,
                                selectedRole,
                                user?.username == 'admin',
                                (role) => setDialogState(() {
                                  selectedRole = role;
                                  cloudUsernameError = null;
                                  cloudUsernameAvailable = null;
                                }),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () async {
                final username = usernameController.text.trim();
                final pin = pinController.text.trim();
                final cloudUsername = cloudUsernameController.text.trim();

                if (username.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('El nombre de usuario es requerido'),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                if (username.length < 3) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'El usuario debe tener al menos 3 caracteres',
                      ),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                // Verificar contraseña para nuevos usuarios
                final password = passwordController.text;
                if (!isEditing && password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('La contraseña es requerida'),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                if (password.isNotEmpty && password.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'La contraseña debe tener al menos 6 caracteres',
                      ),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                // Verificar si username ya existe
                final exists = await UsersRepository.usernameExists(
                  username,
                  excludeId: user?.id,
                );
                if (exists) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Este nombre de usuario ya existe'),
                        backgroundColor: _scheme.error,
                      ),
                    );
                  }
                  return;
                }

                if (pin.isNotEmpty && pin.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('El PIN debe tener al menos 4 dígitos'),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                // Validación de usuario cloud para Admin
                if (selectedRole == 'admin') {
                  if (cloudUsername.isEmpty || cloudUsername.length < 3) {
                    setDialogState(() {
                      cloudUsernameError =
                          'Usuario de la nube requerido (mínimo 3 caracteres)';
                    });
                    return;
                  }

                  // Validar disponibilidad en nube antes de guardar
                  setDialogState(() {
                    cloudUsernameChecking = true;
                    cloudUsernameError = null;
                  });
                  final ok = await CloudSyncService.instance
                      .checkCloudUsernameAvailable(
                        cloudUsername: cloudUsername.toLowerCase(),
                      );
                  if (!context.mounted) return;
                  setDialogState(() {
                    cloudUsernameChecking = false;
                    cloudUsernameAvailable = ok;
                    if (!ok) {
                      cloudUsernameError =
                          'Ese usuario ya existe en la nube o no se pudo validar';
                    }
                  });
                  if (!ok) return;

                  // Si está editando y cambió el usuario cloud, debe indicar contraseña
                  final prevCloud = (user?.cloudUsername ?? '')
                      .trim()
                      .toLowerCase();
                  final nextCloud = cloudUsername.trim().toLowerCase();
                  if (isEditing && prevCloud != nextCloud && password.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Para cambiar el usuario de la nube, indique una contraseña',
                        ),
                        backgroundColor: _scheme.secondary,
                      ),
                    );
                    return;
                  }
                }

                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _scheme.primary,
                foregroundColor: _scheme.onPrimary,
              ),
              child: Text(isEditing ? 'GUARDAR' : 'CREAR'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final username = usernameController.text.trim().toLowerCase();
      final cloudUsername = cloudUsernameController.text.trim().toLowerCase();
      final displayName = displayNameController.text.trim();
      final password = passwordController.text;
      final pin = pinController.text.trim();

      try {
        if (isEditing) {
          await UsersRepository.update(
            user.copyWith(
              username: username,
              cloudUsername: selectedRole == 'admin'
                  ? (cloudUsername.isEmpty ? null : cloudUsername)
                  : null,
              displayName: displayName.isEmpty ? null : displayName,
              pin: pin.isEmpty ? null : pin,
              role: selectedRole,
              updatedAtMs: now,
            ),
          );
          // Actualizar contraseña si se proporcionó una nueva
          if (password.isNotEmpty) {
            await UsersRepository.changePassword(user.id!, password);
          }
          if (selectedRole == 'admin' &&
              cloudUsername.isNotEmpty &&
              password.isNotEmpty) {
            await CloudSyncService.instance.provisionAdminUser(
              cloudUsername: cloudUsername,
              password: password,
            );
          }
        } else {
          // Crear usuario con contraseña
          final passwordHash = UsersRepository.hashPassword(password);
          await UsersRepository.create(
            UserModel(
              username: username,
              cloudUsername: selectedRole == 'admin'
                  ? (cloudUsername.isEmpty ? null : cloudUsername)
                  : null,
              displayName: displayName.isEmpty ? null : displayName,
              passwordHash: passwordHash,
              pin: pin.isEmpty ? null : pin,
              role: selectedRole,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          if (selectedRole == 'admin') {
            await CloudSyncService.instance.provisionAdminUser(
              cloudUsername: cloudUsername,
              password: password,
            );
          }
        }

        await _loadUsers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isEditing ? '✅ Usuario actualizado' : '✅ Usuario creado',
              ),
              backgroundColor: _scheme.tertiary,
            ),
          );
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _showUserDialog(user: user),
            module: 'settings/users/save',
          );
        }
      }
    }
  }

  Widget _buildRoleOption(
    String role,
    String label,
    IconData icon,
    Color color,
    String selectedRole,
    bool disabled,
    Function(String) onSelect,
  ) {
    final isSelected = selectedRole == role;

    return GestureDetector(
      onTap: disabled ? null : () => onSelect(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : _scheme.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : _scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : _scheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : _scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPermissionsDialog(UserModel user) async {
    // Navegar a la página de permisos dedicada
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PermissionsPage(user: user)),
    );
    // Recargar usuarios por si cambió algo
    _loadUsers();
  }

  Future<void> _showChangePasswordDialog(UserModel user) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirm = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _scheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.lock, color: _scheme.primary),
              ),
              const SizedBox(width: 12),
              const Text('CAMBIAR CONTRASEÑA'),
            ],
          ),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Usuario: ${user.displayLabel}',
                  style: TextStyle(color: _scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  autofocus: true,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    hintText: 'Mínimo 6 caracteres',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmController,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    hintText: 'Repita la contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setDialogState(
                        () => obscureConfirm = !obscureConfirm,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () {
                final password = passwordController.text;
                final confirm = confirmController.text;

                if (password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('La contraseña es requerida'),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                if (password.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'La contraseña debe tener al menos 6 caracteres',
                      ),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                if (password != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Las contraseñas no coinciden'),
                      backgroundColor: _scheme.secondary,
                    ),
                  );
                  return;
                }

                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _scheme.primary,
                foregroundColor: _scheme.onPrimary,
              ),
              child: const Text('GUARDAR'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        await UsersRepository.changePassword(user.id!, passwordController.text);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Contraseña actualizada'),
              backgroundColor: _scheme.tertiary,
            ),
          );
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _showChangePasswordDialog(user),
            module: 'settings/users/password',
          );
        }
      }
    }
  }

  Future<void> _showChangePinDialog(UserModel user) async {
    final pinController = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _scheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.password, color: _scheme.secondary),
            ),
            const SizedBox(width: 12),
            const Text('CAMBIAR PIN'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Usuario: ${user.displayLabel}',
                style: TextStyle(color: _scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nuevo PIN',
                  hintText: '4-6 dígitos',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  helperText: 'Dejar vacío para quitar el PIN',
                ),
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final pin = pinController.text.trim();
              if (pin.isNotEmpty && pin.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('El PIN debe tener al menos 4 dígitos'),
                    backgroundColor: _scheme.secondary,
                  ),
                );
                return;
              }
              Navigator.pop(context, pin);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _scheme.secondary,
              foregroundColor: _scheme.onPrimary,
            ),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await UsersRepository.changePin(
          user.id!,
          result.isEmpty ? null : result,
        );
        await _loadUsers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.isEmpty ? '✅ PIN eliminado' : '✅ PIN actualizado',
              ),
              backgroundColor: _scheme.tertiary,
            ),
          );
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _showChangePinDialog(user),
            module: 'settings/users/pin',
          );
        }
      }
    }
  }

  Future<void> _toggleUserActive(UserModel user) async {
    final newState = !user.isActiveUser;

    try {
      await UsersRepository.toggleActive(user.id!, newState);
      await _loadUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newState ? '✅ Usuario activado' : '⚠️ Usuario desactivado',
            ),
            backgroundColor: newState ? _scheme.tertiary : _scheme.secondary,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _toggleUserActive(user),
          module: 'settings/users/toggle_active',
        );
      }
    }
  }

  Future<void> _confirmDeleteUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.warning, color: _scheme.error, size: 48),
        title: const Text('ELIMINAR USUARIO'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¿Está seguro de eliminar a ${user.displayLabel}?'),
            const SizedBox(height: 8),
            Text(
              'Esta acción no se puede deshacer',
              style: TextStyle(color: _scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _scheme.error),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await UsersRepository.delete(user.id!);
        await _loadUsers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Usuario eliminado'),
              backgroundColor: _scheme.tertiary,
            ),
          );
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _confirmDeleteUser(user),
            module: 'settings/users/delete',
          );
        }
      }
    }
  }
}
