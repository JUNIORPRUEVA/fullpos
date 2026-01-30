import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/user_model.dart';

/// Diálogo para mostrar el detalle completo de un usuario
class UserDetailDialog extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onEdit;
  final VoidCallback? onChangePassword;
  final VoidCallback? onChangePin;
  final VoidCallback? onPermissions;

  const UserDetailDialog({
    super.key,
    required this.user,
    this.onEdit,
    this.onChangePassword,
    this.onChangePin,
    this.onPermissions,
  });

  UserPermissions get _permissions {
    if (user.isAdmin) return UserPermissions.admin();
    if (user.permissions == null || user.permissions!.isEmpty) {
      return UserPermissions.cashier();
    }
    try {
      return UserPermissions.fromMap(jsonDecode(user.permissions!) as Map<String, dynamic>);
    } catch (_) {
      return UserPermissions.cashier();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final createdAt = DateTime.fromMillisecondsSinceEpoch(user.createdAtMs);
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(user.updatedAtMs);
    final roleColor = user.isAdmin ? Colors.purple : Colors.teal;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 550,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header con info principal
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [roleColor, roleColor.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  // Avatar grande
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        user.displayLabel.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
                            Flexible(
                              child: Text(
                                user.displayLabel,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!user.isActiveUser) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'INACTIVO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
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
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                user.isAdmin ? Icons.admin_panel_settings : Icons.point_of_sale,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                user.roleLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Content scrollable
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Información básica
                    _buildSection(
                      'Información General',
                      Icons.info_outline,
                      [
                        _buildInfoRow('Usuario', '@${user.username}'),
                        _buildInfoRow('Nombre', user.displayName ?? 'No especificado'),
                        _buildInfoRow('Rol', user.roleLabel),
                        _buildInfoRow('Estado', user.isActiveUser ? 'Activo' : 'Inactivo',
                            valueColor: user.isActiveUser ? Colors.green : Colors.red),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Seguridad
                    _buildSection(
                      'Seguridad',
                      Icons.security,
                      [
                        _buildInfoRow(
                          'Contraseña',
                          user.hasPassword ? '••••••••' : 'Sin contraseña',
                          trailing: user.hasPassword
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                              : const Icon(Icons.warning, color: Colors.orange, size: 18),
                        ),
                        _buildInfoRow(
                          'PIN de acceso rápido',
                          user.pin != null ? '••••' : 'No configurado',
                          trailing: user.pin != null
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                              : const Icon(Icons.info_outline, color: Colors.grey, size: 18),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Fechas
                    _buildSection(
                      'Registro',
                      Icons.calendar_today,
                      [
                        _buildInfoRow('Creado', dateFormat.format(createdAt)),
                        _buildInfoRow('Última modificación', dateFormat.format(updatedAt)),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Permisos
                    _buildPermissionsSection(),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cerrar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onPermissions != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onPermissions!();
                        },
                        icon: const Icon(Icons.security, size: 18),
                        label: const Text('Permisos'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (onEdit != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onEdit!();
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Editar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.teal700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: valueColor ?? Colors.black87,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsSection() {
    final perms = _permissions;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified_user, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              'Permisos',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const Spacer(),
            if (user.isAdmin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ACCESO TOTAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              _buildPermissionCategory('Ventas', [
                _PermissionItem('Realizar ventas', perms.canSell),
                _PermissionItem('Anular ventas', perms.canVoidSale),
                _PermissionItem('Aplicar descuentos', perms.canApplyDiscount),
                _PermissionItem('Ver historial', perms.canViewSalesHistory),
              ]),
              const Divider(height: 24),
              _buildPermissionCategory('Productos', [
                _PermissionItem('Ver productos', perms.canViewProducts),
                _PermissionItem('Editar productos', perms.canEditProducts),
                _PermissionItem('Eliminar productos', perms.canDeleteProducts),
                _PermissionItem('Ajustar stock', perms.canAdjustStock),
              ]),
              const Divider(height: 24),
              _buildPermissionCategory('Clientes', [
                _PermissionItem('Ver clientes', perms.canViewClients),
                _PermissionItem('Editar clientes', perms.canEditClients),
                _PermissionItem('Eliminar clientes', perms.canDeleteClients),
              ]),
              const Divider(height: 24),
              _buildPermissionCategory('Caja', [
                _PermissionItem('Abrir caja', perms.canOpenCash),
                _PermissionItem('Cerrar caja', perms.canCloseCash),
                _PermissionItem('Ver historial caja', perms.canViewCashHistory),
                _PermissionItem('Movimientos', perms.canMakeCashMovements),
              ]),
              const Divider(height: 24),
              _buildPermissionCategory('Otros', [
                _PermissionItem('Ver reportes', perms.canViewReports),
                _PermissionItem('Herramientas', perms.canAccessTools),
                _PermissionItem('Configuración', perms.canAccessSettings),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionCategory(String title, List<_PermissionItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: items.map((item) => _buildPermissionChip(item.name, item.enabled)).toList(),
        ),
      ],
    );
  }

  Widget _buildPermissionChip(String name, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: enabled ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: enabled ? Colors.green.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check : Icons.close,
            size: 14,
            color: enabled ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: enabled ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionItem {
  final String name;
  final bool enabled;

  _PermissionItem(this.name, this.enabled);
}
