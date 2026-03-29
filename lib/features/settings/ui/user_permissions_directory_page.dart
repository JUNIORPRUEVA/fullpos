import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/errors/error_handler.dart';
import '../data/user_model.dart';
import '../data/users_repository.dart';
import 'permissions_page.dart';
import 'settings_layout.dart';
import 'users_page.dart';

class UserPermissionsDirectoryPage extends StatefulWidget {
  const UserPermissionsDirectoryPage({super.key});

  @override
  State<UserPermissionsDirectoryPage> createState() =>
      _UserPermissionsDirectoryPageState();
}

class _UserPermissionsDirectoryPageState
    extends State<UserPermissionsDirectoryPage> {
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
        stage: 'settings/permissions-directory/load',
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
        module: 'settings/permissions-directory/load',
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
    return _users.where((user) {
      final haystack =
          '${user.username} ${user.displayName ?? ''} ${user.roleLabel}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Roles y permisos'),
          actions: [
            IconButton(
              tooltip: 'Recargar',
              onPressed: _isLoading ? null : _loadUsers,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsLayout.sectionHeading(
                    context,
                    title: 'Permisos por usuario',
                    subtitle:
                        'Cada acceso se define por cuenta. Aqui eliges el usuario y editas sus privilegios por modulo.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          decoration: const InputDecoration(
                            hintText: 'Buscar usuario o rol...',
                            prefixIcon: Icon(Icons.search, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: _openUsersPage,
                        icon: const Icon(Icons.people_outline, size: 18),
                        label: const Text('Ir a usuarios'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildStatCard(
                        'Total cuentas',
                        _users.length.toString(),
                        Icons.people,
                        _scheme.primary,
                      ),
                      _buildStatCard(
                        'Administradores',
                        _users.where((user) => user.isAdmin).length.toString(),
                        Icons.admin_panel_settings,
                        _scheme.tertiary,
                      ),
                      _buildStatCard(
                        'Perfiles personalizados',
                        _users.where(_hasCustomPermissions).length.toString(),
                        Icons.tune,
                        _scheme.secondary,
                      ),
                      _buildStatCard(
                        'Activos',
                        _users.where((user) => user.isActiveUser).length.toString(),
                        Icons.check_circle,
                        _scheme.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredUsers.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'No hay usuarios disponibles para configurar permisos.'
                                  : 'No se encontraron usuarios para ese criterio.',
                              style: TextStyle(
                                color: _scheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _filteredUsers.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, index) =>
                                _buildPermissionCard(_filteredUsers[index]),
                          ),
                  ),
                ],
              ),
            );
          },
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
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
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
    );
  }

  Widget _buildPermissionCard(UserModel user) {
    final permissions = _resolvePermissions(user);
    final enabledCount = permissions.toMap().values.where((value) => value == true).length;
    final roleColor = user.isAdmin ? _scheme.tertiary : _scheme.secondary;
    final profileLabel = user.isAdmin
        ? 'Acceso total de administrador'
        : _hasCustomPermissions(user)
        ? 'Perfil personalizado'
        : 'Perfil base de cajero';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openPermissionsPage(user),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  user.isAdmin
                      ? Icons.admin_panel_settings_outlined
                      : Icons.badge_outlined,
                  color: roleColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          user.displayLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _buildPill(
                          user.isActiveUser ? 'ACTIVO' : 'INACTIVO',
                          user.isActiveUser
                              ? _scheme.tertiary
                              : _scheme.error,
                        ),
                        _buildPill(user.roleLabel, roleColor),
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
                    const SizedBox(height: 8),
                    Text(
                      profileLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: roleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$enabledCount permisos activos. Usa esta cuenta como punto unico para editar el acceso por modulo.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => _openPermissionsPage(user),
                icon: const Icon(Icons.security_outlined, size: 18),
                label: const Text('Editar permisos'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  UserPermissions _resolvePermissions(UserModel user) {
    if (user.isAdmin) return UserPermissions.admin();
    final raw = user.permissions?.trim();
    if (raw == null || raw.isEmpty) return UserPermissions.cashier();
    try {
      return UserPermissions.fromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return UserPermissions.cashier();
    }
  }

  bool _hasCustomPermissions(UserModel user) {
    if (user.isAdmin) return false;
    final current = _resolvePermissions(user).toMap();
    final defaults = UserPermissions.cashier().toMap();
    for (final entry in current.entries) {
      if (entry.value != defaults[entry.key]) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openPermissionsPage(UserModel user) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PermissionsPage(user: user)),
    );
    _loadUsers();
  }

  Future<void> _openUsersPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UsersPage()),
    );
    _loadUsers();
  }
}