import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/permission.dart';
import '../../../core/security/authz/permission_gate.dart';
import '../data/business_settings_repository.dart';
import '../data/user_model.dart';
import '../data/users_repository.dart';
import 'settings_layout.dart';

enum _RiskLevel { low, medium, high, critical }

enum _ControlAction { reset, selectAll, clearAll, profileBase }

enum _PermissionColumn {
  view,
  create,
  edit,
  delete,
  export,
  print,
  approve,
  manage,
  operate,
}

extension _PermissionColumnX on _PermissionColumn {
  String get label {
    switch (this) {
      case _PermissionColumn.view:
        return 'Ver';
      case _PermissionColumn.create:
        return 'Crear';
      case _PermissionColumn.edit:
        return 'Editar';
      case _PermissionColumn.delete:
        return 'Eliminar';
      case _PermissionColumn.export:
        return 'Exportar';
      case _PermissionColumn.print:
        return 'Imprimir';
      case _PermissionColumn.approve:
        return 'Aprobar';
      case _PermissionColumn.manage:
        return 'Administrar';
      case _PermissionColumn.operate:
        return 'Operar';
    }
  }
}

class _PermissionDef {
  final String id;
  final String title;
  final String description;
  final _RiskLevel riskLevel;
  final _PermissionColumn column;
  final bool Function(UserPermissions permissions) read;
  final UserPermissions Function(UserPermissions permissions, bool value) write;

  const _PermissionDef({
    required this.id,
    required this.title,
    required this.description,
    required this.riskLevel,
    required this.column,
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

class _PermissionGroup {
  final _PermissionCategory category;
  final List<_PermissionDef> defs;

  const _PermissionGroup({required this.category, required this.defs});
}

class PermissionsPage extends StatefulWidget {
  final UserModel? user;

  const PermissionsPage({super.key, this.user});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  static const double _matrixMinWidth = 860;
  static const double _contentMaxWidth = 1880;

  static final Map<_UserPermissionCategory, List<_PermissionDef>>
  _permissionMap = {
    _UserPermissionCategory.sales: [
      _PermissionDef(
        id: 'ventas.vender',
        title: 'Realizar ventas',
        description:
            'Permite registrar nuevas ventas y avanzar el flujo comercial.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.create,
        read: (permissions) => permissions.canSell,
        write: (permissions, value) => permissions.copyWith(canSell: value),
      ),
      _PermissionDef(
        id: 'ventas.anular',
        title: 'Anular ventas',
        description: 'Autoriza revertir ventas ya confirmadas.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.approve,
        read: (permissions) => permissions.canVoidSale,
        write: (permissions, value) => permissions.copyWith(canVoidSale: value),
      ),
      _PermissionDef(
        id: 'ventas.descuentos',
        title: 'Aplicar descuentos',
        description: 'Permite modificar el valor final antes del cobro.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.edit,
        read: (permissions) => permissions.canApplyDiscount,
        write: (permissions, value) =>
            permissions.copyWith(canApplyDiscount: value),
      ),
      _PermissionDef(
        id: 'ventas.historial',
        title: 'Ver historial de ventas',
        description: 'Permite consultar ventas emitidas y su trazabilidad.',
        riskLevel: _RiskLevel.low,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewSalesHistory,
        write: (permissions, value) =>
            permissions.copyWith(canViewSalesHistory: value),
      ),
    ],
    _UserPermissionCategory.products: [
      _PermissionDef(
        id: 'productos.ver',
        title: 'Ver productos',
        description: 'Consulta de catalogo, existencias y referencias.',
        riskLevel: _RiskLevel.low,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewProducts,
        write: (permissions, value) =>
            permissions.copyWith(canViewProducts: value),
      ),
      _PermissionDef(
        id: 'productos.costos',
        title: 'Ver costo de compra',
        description: 'Expone valores internos y estructura de costo.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewPurchasePrice,
        write: (permissions, value) =>
            permissions.copyWith(canViewPurchasePrice: value),
      ),
      _PermissionDef(
        id: 'productos.ganancia',
        title: 'Ver margen y ganancia',
        description: 'Muestra rentabilidad por producto y margen operativo.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewProfit,
        write: (permissions, value) =>
            permissions.copyWith(canViewProfit: value),
      ),
      _PermissionDef(
        id: 'productos.editar',
        title: 'Editar productos',
        description: 'Permite actualizar descripciones, precios y atributos.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.edit,
        read: (permissions) => permissions.canEditProducts,
        write: (permissions, value) =>
            permissions.copyWith(canEditProducts: value),
      ),
      _PermissionDef(
        id: 'productos.eliminar',
        title: 'Eliminar productos',
        description: 'Permite retirar productos del sistema.',
        riskLevel: _RiskLevel.critical,
        column: _PermissionColumn.delete,
        read: (permissions) => permissions.canDeleteProducts,
        write: (permissions, value) =>
            permissions.copyWith(canDeleteProducts: value),
      ),
      _PermissionDef(
        id: 'inventario.ajustar',
        title: 'Ajustar inventario',
        description: 'Autoriza movimientos manuales de stock y correcciones.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.operate,
        read: (permissions) => permissions.canAdjustStock,
        write: (permissions, value) =>
            permissions.copyWith(canAdjustStock: value),
      ),
    ],
    _UserPermissionCategory.clients: [
      _PermissionDef(
        id: 'clientes.ver',
        title: 'Ver clientes',
        description: 'Consulta de fichas, historial y datos generales.',
        riskLevel: _RiskLevel.low,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewClients,
        write: (permissions, value) =>
            permissions.copyWith(canViewClients: value),
      ),
      _PermissionDef(
        id: 'clientes.editar',
        title: 'Editar clientes',
        description: 'Permite actualizar datos de contacto y condiciones.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.edit,
        read: (permissions) => permissions.canEditClients,
        write: (permissions, value) =>
            permissions.copyWith(canEditClients: value),
      ),
      _PermissionDef(
        id: 'clientes.eliminar',
        title: 'Eliminar clientes',
        description: 'Permite remover registros de clientes.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.delete,
        read: (permissions) => permissions.canDeleteClients,
        write: (permissions, value) =>
            permissions.copyWith(canDeleteClients: value),
      ),
    ],
    _UserPermissionCategory.cash: [
      _PermissionDef(
        id: 'caja.abrir',
        title: 'Abrir caja',
        description: 'Inicia la sesion operativa y habilita caja.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.operate,
        read: (permissions) => permissions.canOpenCash,
        write: (permissions, value) => permissions.copyWith(canOpenCash: value),
      ),
      _PermissionDef(
        id: 'caja.cerrar',
        title: 'Cerrar caja',
        description: 'Permite cierre operativo y arqueo final.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.approve,
        read: (permissions) => permissions.canCloseCash,
        write: (permissions, value) =>
            permissions.copyWith(canCloseCash: value),
      ),
      _PermissionDef(
        id: 'caja.historial',
        title: 'Ver historial de caja',
        description: 'Consulta de aperturas, cierres y sesiones previas.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewCashHistory,
        write: (permissions, value) =>
            permissions.copyWith(canViewCashHistory: value),
      ),
      _PermissionDef(
        id: 'caja.movimientos',
        title: 'Registrar movimientos de caja',
        description: 'Entradas, salidas y operaciones sensibles de efectivo.',
        riskLevel: _RiskLevel.critical,
        column: _PermissionColumn.manage,
        read: (permissions) => permissions.canMakeCashMovements,
        write: (permissions, value) =>
            permissions.copyWith(canMakeCashMovements: value),
      ),
    ],
    _UserPermissionCategory.reports: [
      _PermissionDef(
        id: 'rep.ver',
        title: 'Ver reportes',
        description: 'Acceso a tableros, analitica y cortes de informacion.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewReports,
        write: (permissions, value) =>
            permissions.copyWith(canViewReports: value),
      ),
      _PermissionDef(
        id: 'rep.exportar',
        title: 'Exportar reportes',
        description: 'Genera salidas para auditoria externa o archivo.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.export,
        read: (permissions) => permissions.canExportReports,
        write: (permissions, value) =>
            permissions.copyWith(canExportReports: value),
      ),
    ],
    _UserPermissionCategory.quotes: [
      _PermissionDef(
        id: 'cotizaciones.crear',
        title: 'Crear cotizaciones',
        description: 'Permite registrar propuestas comerciales.',
        riskLevel: _RiskLevel.low,
        column: _PermissionColumn.create,
        read: (permissions) => permissions.canCreateQuotes,
        write: (permissions, value) =>
            permissions.copyWith(canCreateQuotes: value),
      ),
      _PermissionDef(
        id: 'cotizaciones.ver',
        title: 'Ver cotizaciones',
        description: 'Consulta cotizaciones emitidas y su avance.',
        riskLevel: _RiskLevel.low,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewQuotes,
        write: (permissions, value) =>
            permissions.copyWith(canViewQuotes: value),
      ),
      _PermissionDef(
        id: 'cotizaciones.pasar_ticket',
        title: 'Convertir cotizacion en ticket',
        description:
            'Convierte cotizaciones en ticket pendiente dentro del flujo ampliado.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.approve,
        read: (permissions) => permissions.canConvertQuotesToTicket,
        write: (permissions, value) =>
            permissions.copyWith(canConvertQuotesToTicket: value),
      ),
    ],
    _UserPermissionCategory.returns: [
      _PermissionDef(
        id: 'ventas.devolucion',
        title: 'Procesar devoluciones',
        description: 'Permite recibir y aplicar devoluciones de venta.',
        riskLevel: _RiskLevel.critical,
        column: _PermissionColumn.approve,
        read: (permissions) => permissions.canProcessReturns,
        write: (permissions, value) =>
            permissions.copyWith(canProcessReturns: value),
      ),
    ],
    _UserPermissionCategory.credits: [
      _PermissionDef(
        id: 'creditos.ver',
        title: 'Ver creditos',
        description: 'Consulta cuentas pendientes y estado de cobro.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewCredits,
        write: (permissions, value) =>
            permissions.copyWith(canViewCredits: value),
      ),
      _PermissionDef(
        id: 'creditos.gestionar',
        title: 'Gestionar creditos',
        description: 'Permite aplicar abonos, cambios y seguimiento.',
        riskLevel: _RiskLevel.critical,
        column: _PermissionColumn.manage,
        read: (permissions) => permissions.canManageCredits,
        write: (permissions, value) =>
            permissions.copyWith(canManageCredits: value),
      ),
    ],
    _UserPermissionCategory.tools: [
      _PermissionDef(
        id: 'tools.acceso',
        title: 'Acceso a herramientas',
        description: 'Habilita utilidades operativas y tecnicas.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.operate,
        read: (permissions) => permissions.canAccessTools,
        write: (permissions, value) =>
            permissions.copyWith(canAccessTools: value),
      ),
    ],
    _UserPermissionCategory.users: [
      _PermissionDef(
        id: 'usuarios.gestionar',
        title: 'Gestionar usuarios',
        description: 'Permite crear, editar, activar y depurar cuentas.',
        riskLevel: _RiskLevel.critical,
        column: _PermissionColumn.manage,
        read: (permissions) => permissions.canManageUsers,
        write: (permissions, value) =>
            permissions.copyWith(canManageUsers: value),
      ),
    ],
    _UserPermissionCategory.settings: [
      _PermissionDef(
        id: 'cfg.acceso',
        title: 'Acceso a configuracion',
        description: 'Habilita ajustes estructurales del sistema.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.manage,
        read: (permissions) => permissions.canAccessSettings,
        write: (permissions, value) =>
            permissions.copyWith(canAccessSettings: value),
      ),
    ],
  };

  late UserPermissions _permissions;
  List<UserModel> _users = [];
  UserModel? _selectedUser;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _isFetching = true;
  bool _isLoadingUsers = true;
  bool _fullQuotesFlowEnabled = false;
  String _searchQuery = '';
  int _userLoadSeq = 0;
  _UserPermissionCategory? _selectedCategory;

  final ScrollController _tableVerticalController = ScrollController();
  final ScrollController _tableHorizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedUser = widget.user;
    _permissions = _defaultPermissionsFor(widget.user);
    _loadAvailableUsers();
    _loadBusinessSettings();
  }

  @override
  void dispose() {
    _tableVerticalController.dispose();
    _tableHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadBusinessSettings() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!mounted) return;
      setState(() {
        _fullQuotesFlowEnabled = settings.enableFullQuotesFlow;
      });
    } catch (_) {}
  }

  UserPermissions _defaultPermissionsFor(UserModel? user) {
    if (user == null) {
      return UserPermissions.none();
    }
    return user.isAdmin ? UserPermissions.admin() : UserPermissions.cashier();
  }

  UserModel? _preferredInitialUser(List<UserModel> users) {
    if (users.isEmpty) return null;
    final requestedId = widget.user?.id ?? _selectedUser?.id;
    if (requestedId != null) {
      for (final user in users) {
        if (user.id == requestedId) {
          return user;
        }
      }
    }

    for (final user in users) {
      if (user.isActiveUser && !user.isAdmin) {
        return user;
      }
    }
    for (final user in users) {
      if (user.isActiveUser) {
        return user;
      }
    }
    return users.first;
  }

  Future<void> _loadAvailableUsers() async {
    final seq = ++_userLoadSeq;
    if (mounted) {
      setState(() => _isLoadingUsers = true);
    }
    try {
      final users = await UsersRepository.getAll();
      if (!mounted || seq != _userLoadSeq) return;

      final preferredUser = _preferredInitialUser(users);
      setState(() {
        _users = users;
        _selectedUser = preferredUser;
        if (preferredUser == null) {
          _permissions = UserPermissions.none();
          _hasChanges = false;
          _isFetching = false;
        }
      });

      if (preferredUser != null) {
        await _loadUserPermissions();
      }
    } catch (error, stackTrace) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          error,
          stackTrace: stackTrace,
          context: context,
          onRetry: _loadAvailableUsers,
          module: 'settings/permissions/users',
        );
      }
    } finally {
      if (mounted && seq == _userLoadSeq) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  Future<void> _loadUserPermissions() async {
    final userId = _selectedUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() => _isFetching = false);
      }
      return;
    }

    setState(() => _isFetching = true);
    try {
      final loaded = await UsersRepository.getPermissions(userId);
      if (!mounted) return;
      setState(() {
        _permissions = loaded;
        _hasChanges = false;
      });
    } catch (error, stackTrace) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          error,
          stackTrace: stackTrace,
          context: context,
          onRetry: _loadUserPermissions,
          module: 'settings/permissions/load',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  Future<void> _changeSelectedUser(UserModel? user) async {
    if (user == null || user.id == _selectedUser?.id) return;
    setState(() {
      _selectedUser = user;
      _permissions = _defaultPermissionsFor(user);
      _hasChanges = false;
      _selectedCategory = null;
      _searchQuery = '';
    });
    await _loadUserPermissions();
  }

  Future<void> _savePermissions() async {
    final userId = _selectedUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      await UsersRepository.savePermissions(userId, _permissions);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Permisos guardados correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() => _hasChanges = false);
    } catch (error, stackTrace) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          error,
          stackTrace: stackTrace,
          context: context,
          onRetry: _savePermissions,
          module: 'settings/permissions/save',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _updatePermission(
    UserPermissions Function(UserPermissions current) updater,
  ) {
    setState(() {
      _permissions = updater(_permissions);
      _hasChanges = true;
    });
  }

  UserPermissions _suggestedPermissions() {
    return _defaultPermissionsFor(_selectedUser);
  }

  List<_PermissionCategory> _categories() => const [
    _PermissionCategory(
      id: _UserPermissionCategory.sales,
      label: 'Ventas',
      icon: Icons.point_of_sale_outlined,
      color: Color(0xFF0F766E),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.products,
      label: 'Productos',
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF1D4ED8),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.clients,
      label: 'Clientes',
      icon: Icons.people_outline,
      color: Color(0xFF7C3AED),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.cash,
      label: 'Caja',
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFF15803D),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.reports,
      label: 'Reportes',
      icon: Icons.assessment_outlined,
      color: Color(0xFFB45309),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.quotes,
      label: 'Cotizaciones',
      icon: Icons.request_quote_outlined,
      color: Color(0xFF0F4C81),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.returns,
      label: 'Devoluciones',
      icon: Icons.assignment_return_outlined,
      color: Color(0xFFB91C1C),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.credits,
      label: 'Creditos',
      icon: Icons.credit_score_outlined,
      color: Color(0xFF4338CA),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.tools,
      label: 'Herramientas',
      icon: Icons.build_outlined,
      color: Color(0xFF475569),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.users,
      label: 'Usuarios',
      icon: Icons.manage_accounts_outlined,
      color: Color(0xFF6D28D9),
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.settings,
      label: 'Configuracion',
      icon: Icons.settings_outlined,
      color: Color(0xFF334155),
    ),
  ];

  List<_PermissionGroup> _visibleGroups(List<_PermissionCategory> categories) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredCategories = _selectedCategory == null
        ? categories
        : categories
              .where((category) => category.id == _selectedCategory)
              .toList(growable: false);

    final groups = <_PermissionGroup>[];
    for (final category in filteredCategories) {
      final defs = (_permissionMap[category.id] ?? const <_PermissionDef>[])
          .where((def) {
            if (query.isEmpty) return true;
            final haystack =
                '${category.label} ${def.title} ${def.description} ${def.column.label}'
                    .toLowerCase();
            return haystack.contains(query);
          })
          .toList(growable: false);
      if (defs.isNotEmpty) {
        groups.add(_PermissionGroup(category: category, defs: defs));
      }
    }
    return groups;
  }

  List<_PermissionDef> _allDefs(List<_PermissionCategory> categories) {
    return [
      for (final category in categories)
        ...(_permissionMap[category.id] ?? const <_PermissionDef>[]),
    ];
  }

  int _enabledCount(Iterable<_PermissionDef> defs) {
    return defs.where((def) => def.read(_permissions)).length;
  }

  void _setAllPermissions(List<_PermissionDef> defs, bool value) {
    _updatePermission((current) {
      var next = current;
      for (final def in defs) {
        if (_isDisabledByConfig(def)) continue;
        next = def.write(next, value);
      }
      return next;
    });
  }

  void _setAllForModule(_UserPermissionCategory category, bool value) {
    final defs = _permissionMap[category] ?? const <_PermissionDef>[];
    _setAllPermissions(defs, value);
  }

  void _resetModuleToDefault(_UserPermissionCategory category) {
    final defs = _permissionMap[category] ?? const <_PermissionDef>[];
    final defaults = _suggestedPermissions();
    _updatePermission((current) {
      var next = current;
      for (final def in defs) {
        next = def.write(next, def.read(defaults));
      }
      return next;
    });
  }

  void _applySuggestedProfile() {
    setState(() {
      _permissions = _suggestedPermissions();
      _hasChanges = true;
    });
  }

  bool _isDisabledByConfig(_PermissionDef def) {
    return def.id == 'cotizaciones.pasar_ticket' && !_fullQuotesFlowEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories();
    final allDefs = _allDefs(categories);
    final visibleGroups = _visibleGroups(categories);
    final enabledCount = _enabledCount(allDefs);
    final totalCount = allDefs.length;
    final currentUser = _selectedUser;
    final isAdmin = currentUser?.isAdmin ?? false;

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(toolbarHeight: 42, titleSpacing: 0),
        body: SafeArea(
          child: PermissionGate(
            permission: Permissions.settingsPermissions,
            autoPromptOnce: true,
            reason: 'Acceso a configuracion de permisos',
            resourceType: 'screen',
            resourceId: 'settings.permissions',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = EdgeInsets.fromLTRB(
                  constraints.maxWidth < 1200 ? 8 : 12,
                  6,
                  constraints.maxWidth < 1200 ? 8 : 12,
                  12,
                );
                final boundedHeight = constraints.maxHeight - padding.vertical;
                final availableWidth = math.min(
                  _contentMaxWidth,
                  math.max(0.0, constraints.maxWidth - padding.horizontal),
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _contentMaxWidth,
                    ),
                    child: Padding(
                      padding: padding,
                      child: SizedBox(
                        height: boundedHeight > 0 ? boundedHeight : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCompactControlBar(
                              availableWidth: availableWidth,
                              categories: categories,
                              allDefs: allDefs,
                              currentUser: currentUser,
                              enabledCount: enabledCount,
                              totalCount: totalCount,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: currentUser == null
                                  ? _buildNoUsersState()
                                  : isAdmin
                                  ? _buildAdminMessage(enabledCount, totalCount)
                                  : (_isFetching
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : _buildPermissionMatrixCard(
                                            groups: visibleGroups,
                                            currentUser: currentUser,
                                          )),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactControlBar({
    required double availableWidth,
    required List<_PermissionCategory> categories,
    required List<_PermissionDef> allDefs,
    required UserModel? currentUser,
    required int enabledCount,
    required int totalCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final editingEnabled =
        !_isSaving &&
        !_isFetching &&
        !_isLoadingUsers &&
        currentUser != null &&
        !currentUser.isAdmin;
    final minRowWidth = math.max(availableWidth, 1260.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minRowWidth),
          child: SizedBox(
            width: minRowWidth,
            child: Row(
              children: [
                SizedBox(
                  width: 228,
                  height: 40,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(currentUser?.id),
                    initialValue: currentUser?.id,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'Usuario',
                      prefixIcon: Icon(Icons.person_outline),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      for (final user in _users)
                        DropdownMenuItem<int>(
                          value: user.id,
                          child: Text(
                            '${user.displayLabel} · ${user.roleLabel}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _isLoadingUsers
                        ? null
                        : (value) {
                            final nextUser = _users
                                .where((user) => user.id == value)
                                .firstOrNull;
                            _changeSelectedUser(nextUser);
                          },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  height: 40,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_selectedCategory?.name ?? '__all__'),
                    initialValue: _selectedCategory?.name ?? '__all__',
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'Modulo',
                      prefixIcon: Icon(Icons.filter_list_outlined),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '__all__',
                        child: Text('Todos'),
                      ),
                      for (final category in categories)
                        DropdownMenuItem<String>(
                          value: category.id.name,
                          child: Text(category.label),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value == null || value == '__all__'
                            ? null
                            : _UserPermissionCategory.values.firstWhere(
                                (category) => category.name == value,
                              );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: const InputDecoration(
                        hintText: 'Buscar permiso o modulo',
                        prefixIcon: Icon(Icons.search_outlined),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildHeaderBadge(
                  icon: Icons.badge_outlined,
                  label: currentUser == null
                      ? 'Sin usuario'
                      : currentUser.roleLabel,
                  tone: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                _buildHeaderBadge(
                  icon: Icons.check_box_outlined,
                  label: '$enabledCount / $totalCount',
                  tone: scheme.primary,
                ),
                const SizedBox(width: 8),
                _buildControlActions(editingEnabled, allDefs, currentUser),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlActions(
    bool editingEnabled,
    List<_PermissionDef> allDefs,
    UserModel? currentUser,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: editingEnabled ? _savePermissions : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(
            _isSaving ? 'Guardando' : (_hasChanges ? 'Guardar *' : 'Guardar'),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_ControlAction>(
          enabled: currentUser != null && !_isLoadingUsers,
          tooltip: 'Acciones',
          onSelected: (action) {
            switch (action) {
              case _ControlAction.reset:
                _loadUserPermissions();
                break;
              case _ControlAction.selectAll:
                _setAllPermissions(allDefs, true);
                break;
              case _ControlAction.clearAll:
                _setAllPermissions(allDefs, false);
                break;
              case _ControlAction.profileBase:
                _applySuggestedProfile();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<_ControlAction>(
              value: _ControlAction.reset,
              child: Text('Restablecer'),
            ),
            const PopupMenuItem<_ControlAction>(
              value: _ControlAction.selectAll,
              child: Text('Marcar todo'),
            ),
            const PopupMenuItem<_ControlAction>(
              value: _ControlAction.clearAll,
              child: Text('Limpiar'),
            ),
            const PopupMenuItem<_ControlAction>(
              value: _ControlAction.profileBase,
              child: Text('Perfil base'),
            ),
          ],
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.32),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_outlined, size: 16, color: scheme.onSurface),
                const SizedBox(width: 6),
                Text(
                  'Acciones',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBadge({
    required IconData icon,
    required String label,
    required Color tone,
  }) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionMatrixCard({
    required List<_PermissionGroup> groups,
    required UserModel currentUser,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.38)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = math.max(constraints.maxWidth, _matrixMinWidth);
            return SizedBox(
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: _tableHorizontalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _tableHorizontalController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: tableWidth),
                    child: IntrinsicWidth(
                      child: SizedBox(
                        width: tableWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMatrixTopRow(groups),
                            const SizedBox(height: 4),
                            _buildMatrixHeaderRow(),
                            const SizedBox(height: 4),
                            Expanded(
                              child: groups.isEmpty
                                  ? _buildEmptyState()
                                  : Scrollbar(
                                      controller: _tableVerticalController,
                                      thumbVisibility: true,
                                      child: ListView.separated(
                                        controller: _tableVerticalController,
                                        padding: EdgeInsets.zero,
                                        itemCount: groups.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (context, index) {
                                          return _buildMatrixGroup(
                                            groups[index],
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
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
    );
  }

  Widget _buildMatrixTopRow(List<_PermissionGroup> groups) {
    final scheme = Theme.of(context).colorScheme;
    final visibleDefs = [for (final group in groups) ...group.defs];
    final enabledVisible = _enabledCount(visibleDefs);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permisos del usuario',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Cada fila representa un permiso concreto. La columna Tipo indica si corresponde a ver, editar, aprobar o administrar.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        _buildHeaderBadge(
          icon: Icons.grid_view_rounded,
          label:
              '${groups.length} modulos · $enabledVisible / ${visibleDefs.length} activos',
          tone: scheme.primary,
        ),
      ],
    );
  }

  Widget _buildMatrixHeaderRow() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Permiso', flex: 6, alignStart: true),
          _buildHeaderCell('Tipo', flex: 2),
          _buildHeaderCell('Activo', flex: 1),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    String label, {
    required int flex,
    bool alignStart = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 40,
        padding: EdgeInsets.fromLTRB(alignStart ? 12 : 6, 0, 6, 0),
        alignment: alignStart ? Alignment.centerLeft : Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignStart ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildMatrixGroup(_PermissionGroup group) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _enabledCount(group.defs);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: group.category.color.withOpacity(0.06),
            child: Row(
              children: [
                Icon(
                  group.category.icon,
                  size: 18,
                  color: group.category.color,
                ),
                const SizedBox(width: 6),
                Text(
                  group.category.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                _buildHeaderBadge(
                  icon: Icons.checklist_rounded,
                  label: '$enabled/${group.defs.length}',
                  tone: group.category.color,
                ),
                const Spacer(),
                _buildGroupActionButton(
                  label: 'Todo',
                  onTap: () => _setAllForModule(group.category.id, true),
                ),
                const SizedBox(width: 6),
                _buildGroupActionButton(
                  label: 'Limpiar',
                  onTap: () => _setAllForModule(group.category.id, false),
                ),
                const SizedBox(width: 6),
                _buildGroupActionButton(
                  label: 'Base',
                  onTap: () => _resetModuleToDefault(group.category.id),
                ),
              ],
            ),
          ),
          Container(height: 1, color: scheme.outlineVariant.withOpacity(0.20)),
          for (var index = 0; index < group.defs.length; index++)
            _buildMatrixPermissionRow(
              group.defs[index],
              accentColor: group.category.color,
              isLast: index == group.defs.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildGroupActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: _isSaving ? null : onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: scheme.surface.withOpacity(0.92),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        minimumSize: const Size(0, 30),
        textStyle: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  Widget _buildMatrixPermissionRow(
    _PermissionDef def, {
    required Color accentColor,
    required bool isLast,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final value = def.read(_permissions);
    final disabledByConfig = _isDisabledByConfig(def);

    return InkWell(
      onTap: disabledByConfig || _isSaving
          ? null
          : () => _updatePermission((current) => def.write(current, !value)),
      hoverColor: accentColor.withOpacity(0.03),
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(
          color: value
              ? accentColor.withOpacity(0.035)
              : scheme.surface.withOpacity(0.01),
          border: Border(
            bottom: BorderSide(
              color: isLast
                  ? Colors.transparent
                  : scheme.outlineVariant.withOpacity(0.22),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            def.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: disabledByConfig
                                      ? scheme.onSurface.withOpacity(0.45)
                                      : scheme.onSurface,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _riskPill(def.riskLevel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      def.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                    if (disabledByConfig) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Requiere activar el flujo completo de cotizaciones desde Configuracion del negocio.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: _buildPermissionTypeChip(def.column, accentColor),
              ),
            ),
            Expanded(
              flex: 1,
              child: _buildMatrixToggleCell(
                active: value,
                enabled: !disabledByConfig && !_isSaving,
                accentColor: accentColor,
                onTap: !disabledByConfig && !_isSaving
                    ? () => _updatePermission(
                        (current) => def.write(current, !value),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTypeChip(_PermissionColumn column, Color accentColor) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withOpacity(0.18)),
      ),
      child: Text(
        column.label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Color.lerp(accentColor, scheme.onSurface, 0.15),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildMatrixToggleCell({
    required bool active,
    required bool enabled,
    required Color accentColor,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: active ? accentColor.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            checkboxTheme: CheckboxThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              side: BorderSide(
                color: enabled
                    ? accentColor.withOpacity(0.55)
                    : scheme.outlineVariant.withOpacity(0.32),
              ),
            ),
          ),
          child: Checkbox(
            value: active,
            onChanged: enabled ? (_) => onTap?.call() : null,
            activeColor: accentColor,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  Widget _buildAdminMessage(int enabledCount, int totalCount) {
    final scheme = Theme.of(context).colorScheme;
    final currentUser = _selectedUser;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.36)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: const Color(0xFF6D28D9).withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 42,
                  color: Color(0xFF6D28D9),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Perfil con acceso total',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Este usuario pertenece al rol administrador. El sistema mantiene todos los permisos habilitados para preservar la operacion completa y la capacidad de soporte.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildHeaderBadge(
                    icon: Icons.check_circle_outline,
                    label: '$enabledCount de $totalCount permisos activos',
                    tone: const Color(0xFF15803D),
                  ),
                  _buildHeaderBadge(
                    icon: Icons.lock_open_outlined,
                    label: currentUser == null
                        ? 'Selecciona un usuario'
                        : 'Edicion deshabilitada para ${currentUser.displayLabel}',
                    tone: const Color(0xFF6D28D9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 44,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay permisos para el filtro actual.',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Prueba con otro modulo o limpia el buscador para ver toda la matriz.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildNoUsersState() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.36)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline,
                size: 46,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                'No hay usuarios disponibles para asignar permisos.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea o activa un usuario desde la gestion de usuarios y luego vuelve a esta misma pantalla para marcar sus permisos.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _riskPill(_RiskLevel riskLevel) {
    late final Color background;
    late final Color foreground;
    late final String label;

    switch (riskLevel) {
      case _RiskLevel.low:
        background = const Color(0xFFDCFCE7);
        foreground = const Color(0xFF166534);
        label = 'Bajo';
        break;
      case _RiskLevel.medium:
        background = const Color(0xFFFEF3C7);
        foreground = const Color(0xFFB45309);
        label = 'Medio';
        break;
      case _RiskLevel.high:
        background = const Color(0xFFFEE2E2);
        foreground = const Color(0xFFB91C1C);
        label = 'Alto';
        break;
      case _RiskLevel.critical:
        background = const Color(0xFFFFE4E6);
        foreground = const Color(0xFF9F1239);
        label = 'Critico';
        break;
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
