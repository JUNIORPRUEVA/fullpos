import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/permission.dart';
import '../../../core/security/authz/permission_gate.dart';
import '../data/user_model.dart';
import '../data/users_repository.dart';
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

  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _users = const [];
  bool _loading = true;
  bool _refreshing = false;
  int? _busyUserId;
  int? _selectedUserId;

  String get _query => _searchController.text.trim();

  List<UserModel> get _visibleUsers {
    final query = _normalizeSearch(_query);
    if (query.isEmpty) return _users;
    return _users
        .where((user) {
          final haystack = _normalizeSearch(
            '${user.displayLabel} ${user.username} ${user.roleLabel}',
          );
          return haystack.contains(query);
        })
        .toList(growable: false);
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

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String _normalizeSearch(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ü', 'u');
  }

  EdgeInsets _contentPadding(
    BoxConstraints constraints, {
    required bool isWide,
  }) {
    const maxContentWidth = 1440.0;
    final contentWidth = math.min(constraints.maxWidth * 0.92, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(24.0, 160.0)
        .toDouble();

    return EdgeInsets.fromLTRB(side, 22, side, 24);
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
      setState(() {
        _users = users;
        if (_selectedUserId != null &&
            !_users.any((user) => user.id == _selectedUserId)) {
          _selectedUserId = null;
        }
      });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
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

    await _runUserAction(user, () async {
      await UsersRepository.update(updated);
      if ((result.password ?? '').trim().isNotEmpty && updated.id != null) {
        await UsersRepository.changePassword(updated.id!, result.password!);
      }
    }, successMessage: 'Usuario actualizado correctamente.');
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
      successMessage: value.trim().isEmpty
          ? 'PIN eliminado.'
          : 'PIN actualizado.',
    );
  }

  Future<void> _openPermissions(UserModel user) async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PermissionsPage(user: user)),
    );

    if (!mounted) return;
    await _loadUsers(silent: true);
  }

  Future<void> _showUserDetail(UserModel user) async {
    if (!mounted) return;
    setState(() => _selectedUserId = user.id);

    final action = await showGeneralDialog<_UserDetailAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar detalle del usuario',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (drawerContext, animation, secondaryAnimation) {
        final availableWidth = MediaQuery.of(drawerContext).size.width;
        final panelWidth = math.min(392.0, availableWidth);

        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: panelWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(drawerContext).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
              child: _buildUserDetailsDrawer(
                drawerContext,
                user,
                onAction: (action) =>
                    Navigator.of(drawerContext).pop(action),
                onClose: () => Navigator.of(drawerContext).pop(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _UserDetailAction.edit:
        await _openUserForm(user: user);
        break;
      case _UserDetailAction.permissions:
        await _openPermissions(user);
        break;
      case _UserDetailAction.password:
        await _openPasswordDialog(user);
        break;
      case _UserDetailAction.pin:
        await _openPinDialog(user);
        break;
      case _UserDetailAction.toggleActive:
        await _toggleActive(user);
        break;
    }
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
            final isWide = constraints.maxWidth >= 1200;
            final padding = _contentPadding(constraints, isWide: isWide);

            return PermissionGate(
              permission: Permissions.settingsPermissions,
              reason: 'Gestión de usuarios',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopHeaderLine(contentPadding: padding),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        0,
                        padding.right,
                        padding.bottom,
                      ),
                      child: _buildBody(),
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

  Widget _buildTopHeaderLine({required EdgeInsets contentPadding}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget summaryBadge({
      required String label,
      required String value,
      required Color borderColor,
      Color? backgroundColor,
      Color? textColor,
    }) {
      return Expanded(
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: textColor ?? scheme.onSurface.withOpacity(0.72),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: textColor ?? scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final searchField = SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar nombre, usuario o rol...',
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: scheme.onSurface.withOpacity(0.48),
          ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _brandBlue, width: 1.6),
          ),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    _searchController.clear();
                    _safeSetState(() {});
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              : null,
        ),
        onChanged: (_) => _safeSetState(() {}),
      ),
    );

    final actionsButton = SizedBox(
      height: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (value) async {
          switch (value) {
            case 'new':
              await _openUserForm();
              break;
            case 'refresh':
              await _loadUsers(silent: true);
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'new',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.person_add_alt_1_rounded),
              title: Text('Nuevo usuario'),
            ),
          ),
          PopupMenuItem(
            value: 'refresh',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.refresh_rounded),
              title: Text('Actualizar'),
            ),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _brandBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _brandBlue),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_refreshing) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ] else ...[
                const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              ],
              const SizedBox(width: 8),
              const Text(
                'Acciones',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );

    final searchRow = Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 10),
        actionsButton,
      ],
    );

    final summaryRow = Row(
      children: [
        summaryBadge(
          label: 'Registrados',
          value: '${_users.length}',
          borderColor: scheme.outlineVariant,
        ),
        const SizedBox(width: 8),
        summaryBadge(
          label: 'Activos',
          value: '$_activeCount',
          borderColor: const Color(0xFF16A34A).withOpacity(0.22),
          backgroundColor: const Color(0xFF16A34A).withOpacity(0.08),
          textColor: const Color(0xFF166534),
        ),
        const SizedBox(width: 8),
        summaryBadge(
          label: 'Administradores',
          value: '$_adminCount',
          borderColor: const Color(0xFFF59E0B).withOpacity(0.26),
          backgroundColor: const Color(0xFFF59E0B).withOpacity(0.10),
          textColor: const Color(0xFFB45309),
        ),
        const SizedBox(width: 8),
        summaryBadge(
          label: 'Con PIN',
          value: '$_pinCount',
          borderColor: _brandBlue.withOpacity(0.26),
          backgroundColor: _brandBlue.withOpacity(0.10),
          textColor: _brandBlue,
        ),
      ],
    );

    return Padding(
      padding: contentPadding.copyWith(bottom: 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: LayoutBuilder(
          builder: (context, headerConstraints) {
            final stacked = headerConstraints.maxWidth < 760;

            if (stacked) {
              return Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 620, child: searchRow),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 680, child: summaryRow),
                  ),
                ],
              );
            }

            return Column(
              children: [searchRow, const SizedBox(height: 10), summaryRow],
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

    return _buildUsersList(_visibleUsers);
  }

  Widget _buildUsersList(List<UserModel> users) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            if (users.isNotEmpty) ...[
              _buildUsersHeader(),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: users.isEmpty
                  ? _buildEmptyState(hasQuery: _query.isNotEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: users.length,
                      separatorBuilder: (context, _) =>
                          Divider(height: 1, color: scheme.outlineVariant),
                      itemBuilder: (context, index) => _buildUserRow(users[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersHeader() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.70);

    Text label(String text, {TextAlign? align}) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: theme.textTheme.labelSmall?.copyWith(
          color: muted,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
      );
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(width: 32, child: label('')),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: label('Usuario')),
          const SizedBox(width: 12),
          Expanded(flex: 1, child: label('Rol')),
          const SizedBox(width: 8),
          Expanded(flex: 1, child: label('Estado')),
          const SizedBox(width: 8),
          Expanded(flex: 1, child: label('Acceso rápido')),
          const SizedBox(width: 8),
          SizedBox(width: 28, child: label('', align: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildUserRow(UserModel user) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = _busyUserId == user.id;
    final initial = user.displayLabel.isEmpty
        ? '?'
        : user.displayLabel.substring(0, 1).toUpperCase();
    final isSelected = user.id != null && _selectedUserId == user.id;
    final roleColor = _roleAccent(user.role);
    final hasPin = (user.pin ?? '').trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: busy ? null : () => _showUserDetail(user),
        borderRadius: BorderRadius.circular(12),
        hoverColor: _brandBlue.withOpacity(0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFEAF2FF).withOpacity(0.82)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF8FB3FF) : Colors.transparent,
              width: isSelected ? 1 : 0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 30,
                decoration: BoxDecoration(
                  color: isSelected ? _brandBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: user.roleLabel,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: roleColor.withOpacity(0.18)),
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withOpacity(0.66),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _RolePill(role: user.role),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(active: user.isActiveUser),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _PinPill(hasPin: hasPin),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<_UserAction>(
                        padding: EdgeInsets.zero,
                        tooltip: 'Acciones',
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: scheme.onSurface.withOpacity(0.58),
                          size: 18,
                        ),
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
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.visibility_outlined, size: 18),
                              title: Text('Ver detalle'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _UserAction.edit,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.edit_outlined, size: 18),
                              title: Text('Editar usuario'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _UserAction.permissions,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.admin_panel_settings_outlined,
                                size: 18,
                              ),
                              title: Text('Permisos'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _UserAction.password,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.lock_reset_rounded, size: 18),
                              title: Text('Cambiar contraseña'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _UserAction.pin,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.pin_outlined, size: 18),
                              title: Text('Cambiar PIN'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _UserAction.toggleActive,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                user.isActiveUser
                                    ? Icons.block_outlined
                                    : Icons.check_circle_outline_rounded,
                                size: 18,
                              ),
                              title: Text(
                                user.isActiveUser ? 'Desactivar' : 'Activar',
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserDetailsDrawer(
    BuildContext drawerContext,
    UserModel user, {
    required void Function(_UserDetailAction action) onAction,
    VoidCallback? onClose,
  }) {
    final theme = Theme.of(drawerContext);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.62);
    final border = scheme.outlineVariant.withOpacity(0.85);
    final roleColor = _roleAccent(user.role);
    final hasPin = (user.pin ?? '').trim().isNotEmpty;

    Widget sectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.1,
          ),
        ),
      );
    }

    Widget cleanDivider() {
      return Divider(height: 1, thickness: 1, color: border);
    }

    Widget infoLine({
      required IconData icon,
      required String label,
      required String value,
      int maxLines = 1,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: _brandBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget pill({
      required String text,
      required bool active,
      required IconData icon,
    }) {
      final color = active
          ? _brandBlue
          : scheme.onSurfaceVariant.withOpacity(0.85);

      return Expanded(
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? const Color(0xFFBFD1F7) : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget actionButton({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      bool danger = false,
    }) {
      final color = danger ? scheme.error : _brandBlue;
      return SizedBox(
        height: 42,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.28)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      );
    }

    final displayLabel = user.displayLabel.trim().isEmpty
        ? 'Usuario sin nombre'
        : user.displayLabel.trim();
    final username = user.username.trim().isEmpty ? '-' : user.username.trim();
    final initial = displayLabel.substring(0, 1).toUpperCase();

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: border, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Detalle del usuario',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar detalle',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: roleColor.withOpacity(0.10),
                        foregroundColor: roleColor,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@$username',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                displayLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      pill(
                        text: user.roleLabel,
                        active: true,
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                      const SizedBox(width: 8),
                      pill(
                        text: user.isActiveUser ? 'Activo' : 'Inactivo',
                        active: user.isActiveUser,
                        icon: user.isActiveUser
                            ? Icons.check_circle_outline_rounded
                            : Icons.block_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Acceso rápido',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _PinPill(hasPin: hasPin),
                      ],
                    ),
                  ),
                  sectionTitle('Datos del usuario'),
                  infoLine(
                    icon: Icons.badge_outlined,
                    label: 'Nombre para mostrar',
                    value: displayLabel,
                    maxLines: 2,
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.person_outline_rounded,
                    label: 'Usuario',
                    value: '@$username',
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Rol',
                    value: user.roleLabel,
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: user.isActiveUser
                        ? Icons.verified_user_outlined
                        : Icons.block_outlined,
                    label: 'Estado',
                    value: user.isActiveUser ? 'Activo' : 'Inactivo',
                  ),
                  sectionTitle('Acciones rápidas'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      actionButton(
                        icon: Icons.edit_outlined,
                        label: 'Editar',
                        onPressed: () =>
                            onAction(_UserDetailAction.edit),
                      ),
                      actionButton(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Permisos',
                        onPressed: () =>
                            onAction(_UserDetailAction.permissions),
                      ),
                      actionButton(
                        icon: Icons.lock_reset_rounded,
                        label: 'Contraseña',
                        onPressed: () =>
                            onAction(_UserDetailAction.password),
                      ),
                      actionButton(
                        icon: Icons.pin_outlined,
                        label: 'PIN',
                        onPressed: () =>
                            onAction(_UserDetailAction.pin),
                      ),
                      actionButton(
                        icon: user.isActiveUser
                            ? Icons.block_outlined
                            : Icons.check_circle_outline_rounded,
                        label: user.isActiveUser ? 'Desactivar' : 'Activar',
                        danger: user.isActiveUser,
                        onPressed: () =>
                            onAction(_UserDetailAction.toggleActive),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      'Desde aquí puedes revisar el usuario y ejecutar acciones sin abrir menús extra.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _roleAccent(String role) {
    switch (role) {
      case 'admin':
        return const Color(0xFFF59E0B);
      case 'supervisor':
        return const Color(0xFF7C3AED);
      default:
        return _brandBlue;
    }
  }

  Widget _buildEmptyState({required bool hasQuery}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.6);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasQuery ? Icons.search_off_rounded : Icons.people_outline_rounded,
            size: 64,
            color: mutedText,
          ),
          const SizedBox(height: 14),
          Text(
            hasQuery
                ? 'No se encontraron usuarios'
                : 'Sin usuarios registrados',
            style: theme.textTheme.titleMedium?.copyWith(color: mutedText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Intenta cambiar la búsqueda.'
                : 'Crea el primer usuario para asignar accesos y credenciales.',
            style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
            textAlign: TextAlign.center,
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
    );
  }
}

enum _UserAction { view, edit, permissions, password, pin, toggleActive }

enum _UserDetailAction { edit, permissions, password, pin, toggleActive }

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFEE2E2);
    final foreground = active
        ? const Color(0xFF166534)
        : const Color(0xFFB91C1C);
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
    _displayNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
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
          pin: _pinController.text.trim().isEmpty
              ? null
              : _pinController.text.trim(),
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
                    if (text.length < 3) {
                      return 'Debe tener al menos 3 caracteres.';
                    }
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
                  style: const TextStyle(color: Color(0xFF64748B), height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _valueController,
                keyboardType: widget.digitsOnly
                    ? TextInputType.number
                    : TextInputType.text,
                obscureText: widget.obscure && !_showValue,
                decoration: InputDecoration(
                  labelText: widget.label,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: widget.obscure
                      ? IconButton(
                          onPressed: () =>
                              setState(() => _showValue = !_showValue),
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
                keyboardType: widget.digitsOnly
                    ? TextInputType.number
                    : TextInputType.text,
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
