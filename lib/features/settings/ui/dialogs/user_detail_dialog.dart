import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class UserDetailDialog extends StatelessWidget {
  const UserDetailDialog({
    super.key,
    required this.user,
    this.permissions,
    this.onEdit,
    this.onPermissions,
    this.onChangePassword,
    this.onChangePin,
  });

  final dynamic user;
  final dynamic permissions;
  final VoidCallback? onEdit;
  final VoidCallback? onPermissions;
  final VoidCallback? onChangePassword;
  final VoidCallback? onChangePin;

  static const Color _brandBlue = Color(0xFF1A56DB);
  static const Color _darkText = Color(0xFF0F172A);
  static const Color _secondaryText = Color(0xFF64748B);
  static const Color _pageBg = Color(0xFFF2F6F9);
  static const Color _softBlueBg = Color(0xFFEFF6FF);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _successGreen = Color(0xFF16A34A);
  static const Color _dangerRed = Color(0xFFDC2626);
  static const Color _warningOrange = Color(0xFFF59E0B);

  dynamic get _permissions {
    if (permissions != null) return permissions;
    try {
      final value = user.permissions;
      if (value != null) return value;
    } catch (_) {}
    return _EmptyPermissions();
  }

  bool get _hasPin {
    try {
      final value = user.pin;
      if (value != null && value.toString().trim().isNotEmpty) return true;
    } catch (_) {}
    try {
      if (user.hasPin == true) return true;
    } catch (_) {}
    try {
      if (user.pinConfigured == true) return true;
    } catch (_) {}
    try {
      final value = user.pinHash;
      if (value != null && value.toString().trim().isNotEmpty) return true;
    } catch (_) {}
    return false;
  }

  bool get _isActive {
    try {
      return user.isActiveUser == true;
    } catch (_) {}
    try {
      return user.isActive == true;
    } catch (_) {}
    return false;
  }

  bool get _isAdmin {
    try {
      return user.isAdmin == true;
    } catch (_) {}
    try {
      final role = user.role?.toString().toLowerCase();
      return role == 'admin' || role == 'administrator';
    } catch (_) {}
    return false;
  }

  String get _displayName {
    try {
      final value = user.displayLabel?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    try {
      final value = user.displayName?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    try {
      final value = user.name?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    return 'Usuario';
  }

  String get _username {
    try {
      final value = user.username?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    return 'usuario';
  }

  String get _roleLabel {
    try {
      final value = user.roleLabel?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    try {
      final role = user.role?.toString().trim();
      if (role != null && role.isNotEmpty) {
        if (role == 'admin') return 'Administrador';
        if (role == 'supervisor') return 'Supervisor';
        if (role == 'cashier') return 'Cajero';
        return role;
      }
    } catch (_) {}
    return 'Usuario';
  }

  String get _roleValue {
    try {
      return user.role?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  DateTime? get _createdAt =>
      _coerceDateTime(_readDynamic('createdAt'), 'createdAtMs');

  DateTime? get _updatedAt =>
      _coerceDateTime(_readDynamic('updatedAt'), 'updatedAtMs');

  dynamic _readDynamic(String property) {
    try {
      switch (property) {
        case 'createdAt':
          return user.createdAt;
        case 'updatedAt':
          return user.updatedAt;
      }
    } catch (_) {}
    return null;
  }

  DateTime? _coerceDateTime(dynamic value, String fallbackMsField) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    try {
      final ms = fallbackMsField == 'createdAtMs'
          ? user.createdAtMs
          : user.updatedAtMs;
      if (ms is int && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isSmallScreen = screenSize.width < 600;

    final dialogWidth = isSmallScreen
        ? screenSize.width * 0.96
        : screenSize.width >= 1200
            ? 920.0
            : 840.0;

    final maxDialogHeight = screenSize.height * 0.92;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 24,
        vertical: 16,
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Center(
          child: SizedBox(
            width: dialogWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxDialogHeight),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        Container(
                          color: _pageBg,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24, 24, 24, 24,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildUserInfoPanel(context),
                                    const SizedBox(height: 20),
                                    _buildPermissionsSection(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildBottomActions(context),
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

  Widget _buildHeader(BuildContext context) {
    final initial = _displayName.isEmpty
        ? '?'
        : _displayName.substring(0, 1).toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 18, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 80,
            decoration: BoxDecoration(
              color: _brandBlue,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 22),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _softBlueBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: _brandBlue,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _darkText,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildStatusChip(
                      _isActive ? 'Activo' : 'Inactivo',
                      isActive: _isActive,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '@$_username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildRoleBadge(),
                    const SizedBox(width: 8),
                    if (_isAdmin)
                      _buildSoftChip(
                        label: 'Acceso total',
                        icon: Icons.verified_user_rounded,
                        color: _warningOrange,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 20),
              color: _secondaryText,
              tooltip: 'Cerrar',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge() {
    final icon = _isAdmin
        ? Icons.admin_panel_settings_rounded
        : _roleValue == 'supervisor'
            ? Icons.supervisor_account_rounded
            : Icons.point_of_sale_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _softBlueBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _brandBlue),
          const SizedBox(width: 6),
          Text(
            _roleLabel,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _brandBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoPanel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _buildCleanSectionHeader(
            icon: Icons.info_outline_rounded,
            title: 'Información del usuario',
          ),
          _buildInfoGrid(
            children: [
              _InfoItem('Usuario', '@$_username'),
              _InfoItem('Nombre', _displayName),
              _InfoItem('Rol', _roleLabel),
              _InfoItem(
                'Estado',
                _isActive ? 'Activo' : 'Inactivo',
                customValue: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildStatusChip(
                    _isActive ? 'Activo' : 'Inactivo',
                    isActive: _isActive,
                  ),
                ),
              ),
            ],
          ),
          const _DialogDivider(),
          _buildCleanSectionHeader(
            icon: Icons.shield_outlined,
            title: 'Seguridad',
          ),
          _buildInfoGrid(
            children: [
              _InfoItem(
                'Contraseña',
                'Configurada',
                customValue: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSecurityActionChip(
                    context: context,
                    label: 'Configurada',
                    icon: Icons.check_circle_rounded,
                    color: _successGreen,
                    actionLabel:
                        onChangePassword == null ? null : 'Cambiar',
                    onTap: onChangePassword,
                  ),
                ),
              ),
              _InfoItem(
                'PIN de acceso rápido',
                _hasPin ? 'Configurado' : 'No configurado',
                customValue: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSecurityActionChip(
                    context: context,
                    label: _hasPin ? 'Configurado' : 'No configurado',
                    icon: _hasPin
                        ? Icons.lock_rounded
                        : Icons.info_outline_rounded,
                    color: _hasPin ? _successGreen : _secondaryText,
                    actionLabel: onChangePin == null
                        ? null
                        : (_hasPin ? 'Cambiar' : 'Crear'),
                    onTap: onChangePin,
                  ),
                ),
              ),
            ],
          ),
          const _DialogDivider(),
          _buildCleanSectionHeader(
            icon: Icons.calendar_today_outlined,
            title: 'Registro',
          ),
          _buildInfoGrid(
            children: [
              _InfoItem('Creado', _formatDate(_createdAt)),
              _InfoItem('Última modificación', _formatDate(_updatedAt)),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCleanSectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _brandBlue),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _darkText,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid({required List<_InfoItem> children}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          final itemWidth = isWide
              ? (constraints.maxWidth - 18) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: 18,
            runSpacing: 12,
            children: children
                .map(
                  (item) => SizedBox(
                    width: itemWidth,
                    child: _buildInfoItem(item),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildInfoItem(_InfoItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            item.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _secondaryText,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: item.customValue ??
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _darkText,
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(
    String label, {
    required bool isActive,
    bool compact = false,
  }) {
    final bgColor =
        isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final textColor = isActive ? _successGreen : _dangerRed;
    final icon = isActive ? Icons.check_circle : Icons.cancel;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityActionChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    String? actionLabel,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                onTap();
              },
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: _brandBlue,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionsSection() {
    final perms = _permissions;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: _brandBlue,
              ),
              const SizedBox(width: 8),
              const Text(
                'Permisos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _darkText,
                  letterSpacing: -0.1,
                ),
              ),
              const Spacer(),
              if (_isAdmin)
                _buildSoftChip(
                  label: 'Acceso total',
                  icon: Icons.star_rounded,
                  color: _warningOrange,
                ),
            ],
          ),
          const SizedBox(height: 18),
          _buildPermissionCategory(
            'Ventas',
            [
              _PermissionItem('Realizar ventas', _readBool(perms, 'canSell')),
              _PermissionItem(
                'Anular ventas',
                _readBool(perms, 'canVoidSale'),
              ),
              _PermissionItem(
                'Aplicar descuentos',
                _readBool(perms, 'canApplyDiscount'),
              ),
              _PermissionItem(
                'Ver historial',
                _readBool(perms, 'canViewSalesHistory'),
              ),
            ],
          ),
          _buildPermissionCategory(
            'Productos',
            [
              _PermissionItem(
                'Ver productos',
                _readBool(perms, 'canViewProducts'),
              ),
              _PermissionItem(
                'Editar productos',
                _readBool(perms, 'canEditProducts'),
              ),
              _PermissionItem(
                'Eliminar productos',
                _readBool(perms, 'canDeleteProducts'),
              ),
              _PermissionItem(
                'Ajustar stock',
                _readBool(perms, 'canAdjustStock'),
              ),
            ],
          ),
          _buildPermissionCategory(
            'Clientes',
            [
              _PermissionItem(
                'Ver clientes',
                _readBool(perms, 'canViewClients'),
              ),
              _PermissionItem(
                'Editar clientes',
                _readBool(perms, 'canEditClients'),
              ),
              _PermissionItem(
                'Eliminar clientes',
                _readBool(perms, 'canDeleteClients'),
              ),
            ],
          ),
          _buildPermissionCategory(
            'Caja',
            [
              _PermissionItem(
                'Iniciar sesión de caja',
                _readBool(perms, 'canOpenCash'),
              ),
              _PermissionItem(
                'Cerrar sesión de caja',
                _readBool(perms, 'canCloseCash'),
              ),
              _PermissionItem(
                'Ver historial caja',
                _readBool(perms, 'canViewCashHistory'),
              ),
              _PermissionItem(
                'Movimientos',
                _readBool(perms, 'canMakeCashMovements'),
              ),
            ],
          ),
          _buildPermissionCategory(
            'Otros',
            [
              _PermissionItem(
                'Ver reportes',
                _readBool(perms, 'canViewReports'),
              ),
              _PermissionItem(
                'Herramientas',
                _readBool(perms, 'canAccessTools'),
              ),
              _PermissionItem(
                'Configuración',
                _readBool(perms, 'canAccessSettings'),
              ),
            ],
            isLast: true,
          ),
        ],
      ),
    );
  }

  bool _readBool(dynamic object, String name) {
    try {
      switch (name) {
        case 'canSell':
          return object.canSell == true;
        case 'canVoidSale':
          return object.canVoidSale == true;
        case 'canApplyDiscount':
          return object.canApplyDiscount == true;
        case 'canViewSalesHistory':
          return object.canViewSalesHistory == true;
        case 'canViewProducts':
          return object.canViewProducts == true;
        case 'canEditProducts':
          return object.canEditProducts == true;
        case 'canDeleteProducts':
          return object.canDeleteProducts == true;
        case 'canAdjustStock':
          return object.canAdjustStock == true;
        case 'canViewClients':
          return object.canViewClients == true;
        case 'canEditClients':
          return object.canEditClients == true;
        case 'canDeleteClients':
          return object.canDeleteClients == true;
        case 'canOpenCash':
          return object.canOpenCash == true;
        case 'canCloseCash':
          return object.canCloseCash == true;
        case 'canViewCashHistory':
          return object.canViewCashHistory == true;
        case 'canMakeCashMovements':
          return object.canMakeCashMovements == true;
        case 'canViewReports':
          return object.canViewReports == true;
        case 'canAccessTools':
          return object.canAccessTools == true;
        case 'canAccessSettings':
          return object.canAccessSettings == true;
      }
    } catch (_) {}
    return false;
  }

  Widget _buildPermissionCategory(
    String title,
    List<_PermissionItem> items, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 500;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: _darkText,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: items
                        .map((item) =>
                            _buildPermissionChip(item.name, item.enabled))
                        .toList(),
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: _darkText,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items
                    .map((item) =>
                        _buildPermissionChip(item.name, item.enabled))
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPermissionChip(String name, bool enabled) {
    final color = enabled ? _successGreen : _secondaryText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFEAFBF0) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check_rounded : Icons.remove_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: enabled ? const Color(0xFF166534) : _secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('Cerrar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _darkText,
                side: const BorderSide(color: _border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          const Spacer(),
          if (onPermissions != null) ...[
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onPermissions!();
                },
                icon: const Icon(Icons.security_rounded, size: 17),
                label: const Text('Permisos'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _warningOrange,
                  side: const BorderSide(color: _warningOrange),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (onEdit != null) ...[
            SizedBox(
              height: 42,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onEdit!();
                },
                icon: const Icon(Icons.edit_rounded, size: 17),
                label: const Text('Editar'),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyPermissions {
  bool get canSell => false;
  bool get canVoidSale => false;
  bool get canApplyDiscount => false;
  bool get canViewSalesHistory => false;
  bool get canViewProducts => false;
  bool get canEditProducts => false;
  bool get canDeleteProducts => false;
  bool get canAdjustStock => false;
  bool get canViewClients => false;
  bool get canEditClients => false;
  bool get canDeleteClients => false;
  bool get canOpenCash => false;
  bool get canCloseCash => false;
  bool get canViewCashHistory => false;
  bool get canMakeCashMovements => false;
  bool get canViewReports => false;
  bool get canAccessTools => false;
  bool get canAccessSettings => false;
}

class _DialogDivider extends StatelessWidget {
  const _DialogDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 22),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  final Widget? customValue;

  const _InfoItem(this.label, this.value, {this.customValue});
}

class _PermissionItem {
  final String name;
  final bool enabled;

  const _PermissionItem(this.name, this.enabled);
}
