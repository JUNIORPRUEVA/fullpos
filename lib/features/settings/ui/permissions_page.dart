import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/permission.dart';
import '../../../core/security/authz/permission_gate.dart';
import '../data/user_model.dart';
import '../data/users_repository.dart';

enum _RiskLevel { low, medium, high, critical }

class _PermissionDef {
  final String id;
  final String title;
  final String description;
  final _RiskLevel riskLevel;
  final bool Function(UserPermissions p) read;
  final UserPermissions Function(UserPermissions p, bool value) write;

  const _PermissionDef({
    required this.id,
    required this.title,
    required this.description,
    required this.riskLevel,
    required this.read,
    required this.write,
  });
}

enum _UserPermissionCategory {
  sales,
  products,
  clients,
  cash,
  reports,
  quotes,
  returns,
  credits,
  tools,
  users,
  settings,
}

class _PermissionCategory {
  final _UserPermissionCategory id;
  final String label;
  final IconData icon;
  final Color color;

  const _PermissionCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Página de gestión de permisos de usuario
class PermissionsPage extends StatefulWidget {
  final UserModel user;

  const PermissionsPage({super.key, required this.user});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  late UserPermissions _permissions;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _isFetching = true;
  final ScrollController _moduleListController = ScrollController();
  _UserPermissionCategory _selectedCategory = _UserPermissionCategory.sales;
  static const double _contentMaxWidth = 1200;
  static const EdgeInsets _outerPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  @override
  void initState() {
    super.initState();
    _permissions = widget.user.isAdmin
        ? UserPermissions.admin()
        : UserPermissions.cashier();
    _loadUserPermissions();
  }

  @override
  void dispose() {
    _moduleListController.dispose();
    super.dispose();
  }

  Future<void> _loadUserPermissions() async {
    final userId = widget.user.id;
    if (userId == null) {
      if (mounted) setState(() => _isFetching = false);
      return;
    }

    setState(() => _isFetching = true);
    try {
      final loaded = await UsersRepository.getPermissions(userId);
      if (mounted) {
        setState(() {
          _permissions = loaded;
          _hasChanges = false;
        });
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _loadUserPermissions,
          module: 'settings/permissions/load',
        );
      }
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> _savePermissions() async {
    if (widget.user.id == null) return;

    setState(() => _isSaving = true);

    try {
      await UsersRepository.savePermissions(widget.user.id!, _permissions);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permisos guardados correctamente'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _hasChanges = false;
        });
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _savePermissions,
          module: 'settings/permissions/save',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _updatePermission(UserPermissions Function(UserPermissions) updater) {
    setState(() {
      _permissions = updater(_permissions);
      _hasChanges = true;
    });
  }

  UserPermissions _suggestedPermissions() {
    if (widget.user.isAdmin) return UserPermissions.admin();
    return UserPermissions.cashier();
  }

  static final Map<_UserPermissionCategory, List<_PermissionDef>>
  _permissionMap = {
    _UserPermissionCategory.sales: [
      _PermissionDef(
        id: 'ventas.vender',
        title: 'Realizar ventas',
        description: 'Puede crear nuevas ventas.',
        riskLevel: _RiskLevel.medium,
        read: (p) => p.canSell,
        write: (p, v) => p.copyWith(canSell: v),
      ),
      _PermissionDef(
        id: 'ventas.anular',
        title: 'Anular ventas',
        description: 'Puede cancelar o anular ventas completadas.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canVoidSale,
        write: (p, v) => p.copyWith(canVoidSale: v),
      ),
      _PermissionDef(
        id: 'ventas.descuentos',
        title: 'Aplicar descuentos',
        description: 'Puede aplicar descuentos en ventas.',
        riskLevel: _RiskLevel.medium,
        read: (p) => p.canApplyDiscount,
        write: (p, v) => p.copyWith(canApplyDiscount: v),
      ),
      _PermissionDef(
        id: 'ventas.historial',
        title: 'Ver historial de ventas',
        description: 'Puede consultar el historial completo de ventas.',
        riskLevel: _RiskLevel.low,
        read: (p) => p.canViewSalesHistory,
        write: (p, v) => p.copyWith(canViewSalesHistory: v),
      ),
    ],
    _UserPermissionCategory.products: [
      _PermissionDef(
        id: 'productos.ver',
        title: 'Ver productos',
        description: 'Puede ver el catálogo de productos.',
        riskLevel: _RiskLevel.low,
        read: (p) => p.canViewProducts,
        write: (p, v) => p.copyWith(canViewProducts: v),
      ),
      _PermissionDef(
        id: 'productos.costos',
        title: 'Ver costo de compra',
        description: 'Puede ver el precio de compra (costo).',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canViewPurchasePrice,
        write: (p, v) => p.copyWith(canViewPurchasePrice: v),
      ),
      _PermissionDef(
        id: 'productos.ganancia',
        title: 'Ver ganancia/margen',
        description: 'Puede ver ganancia, margen y métricas relacionadas.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canViewProfit,
        write: (p, v) => p.copyWith(canViewProfit: v),
      ),
      _PermissionDef(
        id: 'productos.editar',
        title: 'Editar productos',
        description: 'Puede modificar información de productos.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canEditProducts,
        write: (p, v) => p.copyWith(canEditProducts: v),
      ),
      _PermissionDef(
        id: 'productos.eliminar',
        title: 'Eliminar productos',
        description: 'Puede eliminar productos del sistema.',
        riskLevel: _RiskLevel.critical,
        read: (p) => p.canDeleteProducts,
        write: (p, v) => p.copyWith(canDeleteProducts: v),
      ),
      _PermissionDef(
        id: 'inventario.ajustar',
        title: 'Ajustar inventario',
        description: 'Puede realizar ajustes de stock.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canAdjustStock,
        write: (p, v) => p.copyWith(canAdjustStock: v),
      ),
    ],
    _UserPermissionCategory.clients: [
      _PermissionDef(
        id: 'clientes.ver',
        title: 'Ver clientes',
        description: 'Puede ver la lista de clientes.',
        riskLevel: _RiskLevel.low,
        read: (p) => p.canViewClients,
        write: (p, v) => p.copyWith(canViewClients: v),
      ),
      _PermissionDef(
        id: 'clientes.editar',
        title: 'Editar clientes',
        description: 'Puede modificar información de clientes.',
        riskLevel: _RiskLevel.medium,
        read: (p) => p.canEditClients,
        write: (p, v) => p.copyWith(canEditClients: v),
      ),
      _PermissionDef(
        id: 'clientes.eliminar',
        title: 'Eliminar clientes',
        description: 'Puede eliminar clientes del sistema.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canDeleteClients,
        write: (p, v) => p.copyWith(canDeleteClients: v),
      ),
    ],
    _UserPermissionCategory.cash: [
      _PermissionDef(
        id: 'caja.abrir',
        title: 'Abrir caja',
        description: 'Puede iniciar una sesión de caja.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canOpenCash,
        write: (p, v) => p.copyWith(canOpenCash: v),
      ),
      _PermissionDef(
        id: 'caja.cerrar',
        title: 'Cerrar caja',
        description: 'Puede realizar el cierre de caja.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canCloseCash,
        write: (p, v) => p.copyWith(canCloseCash: v),
      ),
      _PermissionDef(
        id: 'caja.historial',
        title: 'Ver historial de caja',
        description: 'Puede consultar sesiones anteriores.',
        riskLevel: _RiskLevel.medium,
        read: (p) => p.canViewCashHistory,
        write: (p, v) => p.copyWith(canViewCashHistory: v),
      ),
      _PermissionDef(
        id: 'caja.movimientos',
        title: 'Movimientos de caja',
        description: 'Puede registrar entradas y salidas.',
        riskLevel: _RiskLevel.critical,
        read: (p) => p.canMakeCashMovements,
        write: (p, v) => p.copyWith(canMakeCashMovements: v),
      ),
    ],
    _UserPermissionCategory.reports: [
      _PermissionDef(
        id: 'rep.ver',
        title: 'Ver reportes',
        description: 'Puede acceder a los reportes del sistema.',
        riskLevel: _RiskLevel.medium,
        read: (p) => p.canViewReports,
        write: (p, v) => p.copyWith(canViewReports: v),
      ),
      _PermissionDef(
        id: 'rep.exportar',
        title: 'Exportar reportes',
        description: 'Puede exportar reportes a Excel/PDF.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canExportReports,
        write: (p, v) => p.copyWith(canExportReports: v),
      ),
    ],
    _UserPermissionCategory.quotes: [
      _PermissionDef(
        id: 'cotizaciones.crear',
        title: 'Crear cotizaciones',
        description: 'Puede generar nuevas cotizaciones.',
        riskLevel: _RiskLevel.low,
        read: (p) => p.canCreateQuotes,
        write: (p, v) => p.copyWith(canCreateQuotes: v),
      ),
      _PermissionDef(
        id: 'cotizaciones.ver',
        title: 'Ver cotizaciones',
        description: 'Puede consultar cotizaciones existentes.',
        riskLevel: _RiskLevel.low,
        read: (p) => p.canViewQuotes,
        write: (p, v) => p.copyWith(canViewQuotes: v),
      ),
    ],
    _UserPermissionCategory.returns: [
      _PermissionDef(
        id: 'ventas.devolucion',
        title: 'Procesar devoluciones',
        description: 'Puede registrar y procesar devoluciones.',
        riskLevel: _RiskLevel.critical,
        read: (p) => p.canProcessReturns,
        write: (p, v) => p.copyWith(canProcessReturns: v),
      ),
    ],
    _UserPermissionCategory.credits: [
      _PermissionDef(
        id: 'creditos.ver',
        title: 'Ver créditos',
        description: 'Puede ver ventas a crédito pendientes.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canViewCredits,
        write: (p, v) => p.copyWith(canViewCredits: v),
      ),
      _PermissionDef(
        id: 'creditos.gestionar',
        title: 'Gestionar créditos',
        description: 'Puede registrar abonos y modificar créditos.',
        riskLevel: _RiskLevel.critical,
        read: (p) => p.canManageCredits,
        write: (p, v) => p.copyWith(canManageCredits: v),
      ),
    ],
    _UserPermissionCategory.tools: [
      _PermissionDef(
        id: 'tools.acceso',
        title: 'Acceso a herramientas',
        description: 'Puede acceder al módulo de herramientas.',
        riskLevel: _RiskLevel.medium,
        read: (p) => p.canAccessTools,
        write: (p, v) => p.copyWith(canAccessTools: v),
      ),
    ],
    _UserPermissionCategory.users: [
      _PermissionDef(
        id: 'usuarios.gestionar',
        title: 'Gestionar usuarios',
        description: 'Puede crear, editar y eliminar usuarios.',
        riskLevel: _RiskLevel.critical,
        read: (p) => p.canManageUsers,
        write: (p, v) => p.copyWith(canManageUsers: v),
      ),
    ],
    _UserPermissionCategory.settings: [
      _PermissionDef(
        id: 'cfg.acceso',
        title: 'Acceso a configuración',
        description: 'Puede acceder al módulo de configuración.',
        riskLevel: _RiskLevel.high,
        read: (p) => p.canAccessSettings,
        write: (p, v) => p.copyWith(canAccessSettings: v),
      ),
    ],
  };

  List<_PermissionDef> _defsFor(_UserPermissionCategory category) =>
      _permissionMap[category] ?? const [];

  void _setAllForModule(_UserPermissionCategory category, bool value) {
    final defs = _defsFor(category);
    _updatePermission((p) {
      var next = p;
      for (final def in defs) {
        next = def.write(next, value);
      }
      return next;
    });
  }

  void _resetModuleToDefault(_UserPermissionCategory category) {
    final defs = _defsFor(category);
    final defaults = _suggestedPermissions();
    _updatePermission((p) {
      var next = p;
      for (final def in defs) {
        next = def.write(next, def.read(defaults));
      }
      return next;
    });
  }

  List<_PermissionCategory> _categories() => const [
    _PermissionCategory(
      id: _UserPermissionCategory.sales,
      label: 'Ventas',
      icon: Icons.point_of_sale,
      color: AppColors.teal700,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.products,
      label: 'Productos',
      icon: Icons.inventory_2,
      color: Colors.blue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.clients,
      label: 'Clientes',
      icon: Icons.people,
      color: Colors.purple,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.cash,
      label: 'Caja',
      icon: Icons.account_balance_wallet,
      color: Colors.green,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.reports,
      label: 'Reportes',
      icon: Icons.bar_chart,
      color: Colors.orange,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.quotes,
      label: 'Cotizaciones',
      icon: Icons.request_quote,
      color: Colors.cyan,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.returns,
      label: 'Devoluciones',
      icon: Icons.assignment_return,
      color: Colors.red,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.credits,
      label: 'Créditos',
      icon: Icons.credit_card,
      color: Colors.indigo,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.tools,
      label: 'Herramientas',
      icon: Icons.build,
      color: Colors.grey,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.users,
      label: 'Usuarios',
      icon: Icons.manage_accounts,
      color: Colors.deepPurple,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.settings,
      label: 'Configuración',
      icon: Icons.settings,
      color: Colors.blueGrey,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user.isAdmin;
    final categories = _categories();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: PermissionGate(
          permission: Permissions.settingsPermissions,
          autoPromptOnce: true,
          reason: 'Acceso a configuración de permisos',
          resourceType: 'screen',
          resourceId: 'settings.permissions',
          child: Column(
            children: [
              Padding(padding: _outerPadding, child: _buildHeader()),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _contentMaxWidth,
                    ),
                    child: isAdmin
                        ? _buildAdminMessage()
                        : _buildPermissionsContent(categories),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: !isAdmin && _hasChanges && !_isFetching
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _savePermissions,
              backgroundColor: AppColors.teal700,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, color: Colors.white),
              label: Text(
                _isSaving ? 'Guardando...' : 'Guardar cambios',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildPermissionsContent(List<_PermissionCategory> categories) {
    if (_isFetching) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: _buildModulePermissions(categories),
    );
  }

  Widget _buildModulePermissions(List<_PermissionCategory> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = categories.firstWhere(
      (c) => c.id == _selectedCategory,
      orElse: () => categories.first,
    );
    final defs = _defsFor(selected.id);

    final permissionArea = _buildPermissionSection(
      selected.label,
      selected.icon,
      selected.color,
      defs,
      moduleId: selected.id,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1024;

        if (isWide) {
          return SizedBox(
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 360,
                  child: _buildModuleList(categories, expandList: true),
                ),
                const SizedBox(width: 28),
                Expanded(child: permissionArea),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildModuleList(categories, expandList: false),
            const SizedBox(height: 24),
            permissionArea,
          ],
        );
      },
    );
  }

  Widget _buildModuleList(
    List<_PermissionCategory> categories, {
    required bool expandList,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = scheme.outlineVariant.withOpacity(0.45);

    final activeModules = categories
        .where((cat) => _defsFor(cat.id).any((def) => def.read(_permissions)))
        .length;

    final listView = Scrollbar(
      controller: _moduleListController,
      thumbVisibility: true,
      radius: const Radius.circular(6),
      thickness: 6,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        controller: _moduleListController,
        primary: false,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final defs = _defsFor(cat.id);
          final enabled = defs.where((d) => d.read(_permissions)).length;
          final selected = cat.id == _selectedCategory;
          return _buildModuleTile(cat, selected, defs.length, enabled);
        },
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Módulos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: border, thickness: 1)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.teal700.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.teal700.withOpacity(0.4)),
              ),
              child: Text(
                '$activeModules/${categories.length}',
                style: TextStyle(
                  color: AppColors.teal700,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Visualiza y compara los módulos activos del rol.',
          style: TextStyle(
            color: scheme.onSurface.withOpacity(0.70),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        expandList
            ? Expanded(child: listView)
            : SizedBox(height: 320, child: listView),
      ],
    );

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: content),
    );
  }

  Widget _buildModuleTile(
    _PermissionCategory category,
    bool selected,
    int total,
    int enabled,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withOpacity(0.45);
    final progress = total == 0 ? 0.0 : enabled / total;

    return Material(
      color: selected ? category.color.withOpacity(0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedCategory = category.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? category.color.withOpacity(0.6) : border,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: selected
                    ? category.color
                    : Colors.grey.shade200,
                child: Icon(
                  category.icon,
                  size: 18,
                  color: selected ? Colors.white : Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$enabled de $total permisos activos',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withOpacity(0.70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$enabled/$total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: category.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 56,
                    height: 5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        color: category.color,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withOpacity(0.45);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
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
              color: AppColors.teal700.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.security,
              color: AppColors.teal700,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PERMISOS DE USUARIO',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  widget.user.displayLabel,
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.70),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.user.isAdmin
                  ? Colors.purple.withOpacity(0.1)
                  : AppColors.teal700.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.user.isAdmin
                      ? Icons.admin_panel_settings
                      : Icons.person,
                  size: 16,
                  color: widget.user.isAdmin
                      ? Colors.purple
                      : AppColors.teal700,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.user.roleLabel,
                  style: TextStyle(
                    color: widget.user.isAdmin
                        ? Colors.purple
                        : AppColors.teal700,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminMessage() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                size: 64,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Usuario Administrador',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Los administradores tienen acceso completo a todas las funciones del sistema.\nNo es posible restringir sus permisos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.70),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text(
                    'Todos los permisos habilitados',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
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

  // REMOVED: Global per-action permissions UI (Eleventa-style uses only module permissions).
  // ignore: unused_element
  Widget _buildSecurityOverridesCard() {
    return const SizedBox.shrink();
    /*

    if (_securityLoading) {

      return const Card(

        child: Padding(

          padding: EdgeInsets.all(16),

          child: Row(

            children: [

              SizedBox(

                width: 18,

                height: 18,

                child: CircularProgressIndicator(strokeWidth: 2),

              ),

              SizedBox(width: 12),

              Text('Cargando configuración de seguridad...'),

            ],

          ),

        ),

      );

    }



    final config = _securityConfig;

    if (config == null) return const SizedBox.shrink();



    return Card(

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

      child: Padding(

        padding: const EdgeInsets.all(16),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            const Text(

              'Seguridad (Overrides globales)',

              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),

            ),

            const SizedBox(height: 4),

            Text(

              'Activa qué acciones requieren token/override para todos los usuarios. Terminal: $_terminalId',

              style: TextStyle(color: Colors.grey, fontSize: 12),

            ),

            const SizedBox(height: 12),

            ...AppActionCategory.values.map(

              (cat) => _buildOverrideCategory(cat, config),

            ),

          ],

        ),

      ),

    );

    */
  }

  Widget _buildPermissionSection(
    String title,
    IconData icon,
    Color color,
    List<_PermissionDef> defs, {
    required _UserPermissionCategory moduleId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withOpacity(0.45);

    final enabled = defs.where((d) => d.read(_permissions)).length;
    final screenHeight = MediaQuery.of(context).size.height;
    final listMaxHeight = (screenHeight * 0.55).clamp(280.0, 520.0);

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withOpacity(0.5)),
                      ),
                      child: Text(
                        '$enabled/${defs.length}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Controla el acceso a operaciones clave del módulo.',
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.75),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: defs.isEmpty
                          ? null
                          : () => _setAllForModule(moduleId, true),
                      icon: const Icon(Icons.done_all),
                      label: const Text('Seleccionar todo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: defs.isEmpty
                          ? null
                          : () => _setAllForModule(moduleId, false),
                      icon: const Icon(Icons.remove_done),
                      label: const Text('Deseleccionar todo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: defs.isEmpty
                          ? null
                          : () => _resetModuleToDefault(moduleId),
                      icon: const Icon(Icons.restore),
                      label: const Text('Por defecto'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listMaxHeight),
              child: defs.isEmpty
                  ? Text(
                      'No hay permisos definidos para este módulo.',
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.70),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      physics: const BouncingScrollPhysics(),
                      itemCount: defs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final def = defs[index];
                        return _buildPermissionTile(def, accentColor: color);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile(
    _PermissionDef def, {
    required Color accentColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final value = def.read(_permissions);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      tileColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        def.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: value ? scheme.onSurface : scheme.onSurface.withOpacity(0.75),
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              def.description,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withOpacity(0.70),
              ),
            ),
            const SizedBox(height: 6),
            _riskPill(def.riskLevel),
          ],
        ),
      ),
      trailing: Switch.adaptive(
        value: value,
        activeColor: accentColor,
        onChanged: (v) {
          _updatePermission((p) => def.write(p, v));
        },
      ),
    );
  }

  Widget _riskPill(_RiskLevel risk) {
    Color bg;
    Color fg;
    final label = 'Riesgo: ${risk.name}';

    switch (risk) {
      case _RiskLevel.low:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        break;
      case _RiskLevel.medium:
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFFEF6C00);
        break;
      case _RiskLevel.high:
        bg = const Color(0xFFFFE0B2);
        fg = const Color(0xFFE65100);
        break;
      case _RiskLevel.critical:
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
