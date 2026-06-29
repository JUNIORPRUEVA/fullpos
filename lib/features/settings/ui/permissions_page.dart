import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dart:convert';

import '../../../core/constants/app_colors.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/security/authz/permission.dart';
import '../../../core/security/authz/permission_gate.dart';
import '../../../core/session/session_manager.dart';
import '../data/business_settings_repository.dart';
import '../data/user_model.dart';
import '../data/users_repository.dart';
import 'settings_layout.dart';

// ──────────────────────────────────────────────
// Design tokens for this screen
// ──────────────────────────────────────────────
const Color _primaryBlue = Color(0xFF2563EB);
const Color _deepNavy = Color(0xFF0F172A);
const Color _secondaryText = Color(0xFF64748B);
const Color _softBackground = Color(0xFFF8FAFC);
const Color _white = Color(0xFFFFFFFF);
const Color _borderColor = Color(0xFFE2E8F0);
const Color _lightBlueTint = Color(0xFFEFF6FF);
const Color _hoverTint = Color(0xFFF8FAFC);
const Color _warningAmber = Color(0xFFF59E0B);
const double _controlHeight = 40;
const double _rowMinHeight = 52;
const double _moduleHeaderHeight = 42;
const double _toolbarGap = 8;

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
  static const double _contentMaxWidth = 1120;
  static const double _panelBorderRadius = 18;
  static const Color _panelBorderColor = Color(0xFFE2E8F0);
  static const double _bottomSafePadding = 72;

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
      _PermissionDef(
        id: 'inventario.movimientos',
        title: 'Movimiento de inventario',
        description: 'Permite consultar el historial de movimientos de stock.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewInventoryMovements,
        write: (permissions, value) =>
            permissions.copyWith(canViewInventoryMovements: value),
      ),
      _PermissionDef(
        id: 'inventario.recuento',
        title: 'Recuento de inventario',
        description: 'Permite entrar a la pantalla de conteo de inventario.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.operate,
        read: (permissions) => permissions.canCountInventory,
        write: (permissions, value) =>
            permissions.copyWith(canCountInventory: value),
      ),
      _PermissionDef(
        id: 'suplidores.ver',
        title: 'Ver suplidores',
        description: 'Permite consultar suplidores registrados.',
        riskLevel: _RiskLevel.medium,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewSuppliers,
        write: (permissions, value) =>
            permissions.copyWith(canViewSuppliers: value),
      ),
      _PermissionDef(
        id: 'suplidores.registrar',
        title: 'Registrar suplidores',
        description: 'Permite crear nuevos suplidores desde compras.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.create,
        read: (permissions) => permissions.canRegisterSuppliers,
        write: (permissions, value) =>
            permissions.copyWith(canRegisterSuppliers: value),
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
      _PermissionDef(
        id: 'apartados.ver',
        title: 'Ver apartados',
        description: 'Permite entrar a la pantalla de apartados.',
        riskLevel: _RiskLevel.high,
        column: _PermissionColumn.view,
        read: (permissions) => permissions.canViewLayaways,
        write: (permissions, value) =>
            permissions.copyWith(canViewLayaways: value),
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

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.assignPermissions,
      resourceType: 'user_permissions',
      resourceId: userId.toString(),
      reason:
          'Actualizar permisos de ${_selectedUser?.displayLabel ?? 'usuario'}',
    );
    if (!authorized || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await UsersRepository.savePermissions(userId, _permissions);
      if (!mounted) return;

      // Si el usuario editado es el mismo que está logueado, actualizar la sesión
      final loggedUserId = await SessionManager.userId();
      if (loggedUserId == userId) {
        await SessionManager.setPermissions(
          jsonEncode(_permissions.toMap()),
        );
      }

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
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.products,
      label: 'Productos',
      icon: Icons.inventory_2_outlined,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.clients,
      label: 'Clientes',
      icon: Icons.people_outline,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.cash,
      label: 'Caja',
      icon: Icons.account_balance_wallet_outlined,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.reports,
      label: 'Reportes',
      icon: Icons.assessment_outlined,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.quotes,
      label: 'Cotizaciones',
      icon: Icons.request_quote_outlined,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.returns,
      label: 'Devoluciones',
      icon: Icons.assignment_return_outlined,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.credits,
      label: 'Creditos',
      icon: Icons.credit_score_outlined,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.users,
      label: 'Usuarios',
      icon: Icons.manage_accounts_outlined,
      color: _primaryBlue,
    ),
    _PermissionCategory(
      id: _UserPermissionCategory.settings,
      label: 'Configuracion',
      icon: Icons.settings_outlined,
      color: _primaryBlue,
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
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _contentMaxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        18,
                        24,
                        _bottomSafePadding,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            _panelBorderRadius,
                          ),
                          border: Border.all(color: _panelBorderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCompactControlBar(
                              availableWidth: _contentMaxWidth - 48,
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

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 940;

          final userSelector = _buildCleanUserSelector(
            currentUser: currentUser,
          );

          final categorySelector = _buildCleanCategorySelector(
            categories: categories,
          );

          final searchField = SizedBox(
            height: 40,
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 13.2,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar permiso o módulo',
                hintStyle: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12.8,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: scheme.primary.withOpacity(0.45),
                    width: 1.1,
                  ),
                ),
              ),
            ),
          );

          final badgesAndActions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          );

          if (isCompact) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                userSelector,
                categorySelector,
                SizedBox(width: constraints.maxWidth, child: searchField),
                badgesAndActions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              userSelector,
              const SizedBox(width: 8),
              categorySelector,
              const SizedBox(width: 8),
              Expanded(child: searchField),
              const SizedBox(width: 8),
              badgesAndActions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildCleanUserSelector({required UserModel? currentUser}) {
    final selectedLabel = currentUser == null
        ? 'Seleccionar usuario'
        : '${currentUser.displayLabel} · ${currentUser.roleLabel}';

    return SizedBox(
      width: 250,
      height: 40,
      child: MenuAnchor(
        style: _cleanMenuStyle(),
        builder: (context, controller, child) {
          return _selectorButton(
            icon: Icons.person_outline_rounded,
            label: selectedLabel,
            enabled: !_isLoadingUsers && _users.isNotEmpty,
            onTap: () {
              if (_isLoadingUsers || _users.isEmpty) return;

              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          );
        },
        menuChildren: [
          for (final user in _users)
            _cleanMenuItem(
              width: 250,
              label: '${user.displayLabel} · ${user.roleLabel}',
              selected: user.id == currentUser?.id,
              onPressed: () => _changeSelectedUser(user),
            ),
        ],
      ),
    );
  }

  Widget _buildCleanCategorySelector({
    required List<_PermissionCategory> categories,
  }) {
    final selectedCategory = _selectedCategory;

    final selectedLabel = selectedCategory == null
        ? 'Todos'
        : categories
                  .where((category) => category.id == selectedCategory)
                  .map((category) => category.label)
                  .firstOrNull ??
              'Todos';

    return SizedBox(
      width: 156,
      height: 40,
      child: MenuAnchor(
        style: _cleanMenuStyle(),
        builder: (context, controller, child) {
          return _selectorButton(
            icon: Icons.filter_list_rounded,
            label: selectedLabel,
            enabled: true,
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          );
        },
        menuChildren: [
          _cleanMenuItem(
            width: 156,
            label: 'Todos',
            selected: _selectedCategory == null,
            onPressed: () {
              setState(() => _selectedCategory = null);
            },
          ),
          for (final category in categories)
            _cleanMenuItem(
              width: 156,
              label: category.label,
              selected: _selectedCategory == category.id,
              onPressed: () {
                setState(() => _selectedCategory = category.id);
              },
            ),
        ],
      ),
    );
  }

  MenuStyle _cleanMenuStyle() {
    return MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.white),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }

  Widget _selectorButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                    fontSize: 13.4,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: enabled
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cleanMenuItem({
    required double width,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: MenuItemButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (selected) return const Color(0xFFEAF2FF);
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFFF8FAFC);
            }
            return Colors.white;
          }),
          foregroundColor: const WidgetStatePropertyAll(Color(0xFF0F172A)),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        child: SizedBox(
          width: width - 24,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF1A56DB)
                        : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Color(0xFF1A56DB),
                ),
              ],
            ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Guardar - primary button
        FilledButton.icon(
          onPressed: editingEnabled ? _savePermissions : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, _controlHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            backgroundColor: _primaryBlue,
            foregroundColor: _white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
            shadowColor: Colors.transparent,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(
            _isSaving ? 'Guardando' : (_hasChanges ? 'Guardar *' : 'Guardar'),
          ),
        ),
        const SizedBox(width: _toolbarGap),
        // Acciones - secondary button
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
            height: _controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_outlined, size: 16, color: _secondaryText),
                const SizedBox(width: 6),
                const Text(
                  'Acciones',
                  style: TextStyle(
                    color: _deepNavy,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: _secondaryText,
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
    final visibleDefs = [for (final group in groups) ...group.defs];
    final enabledVisible = _enabledCount(visibleDefs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permisos del usuario',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _deepNavy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Cada fila representa un permiso concreto. La columna Tipo indica si corresponde a ver, editar, aprobar o administrar.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: _secondaryText,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          _buildHeaderBadge(
            icon: Icons.grid_view_rounded,
            label:
                '${groups.length} modulos · $enabledVisible / ${visibleDefs.length} activos',
            tone: _primaryBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixHeaderRow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _softBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor.withOpacity(0.6)),
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
        height: 36,
        padding: EdgeInsets.fromLTRB(alignStart ? 14 : 6, 0, 6, 0),
        alignment: alignStart ? Alignment.centerLeft : Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignStart ? TextAlign.left : TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _secondaryText,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildMatrixGroup(_PermissionGroup group) {
    final enabled = _enabledCount(group.defs);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor.withOpacity(0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Module header - clean white with subtle border
          Container(
            height: _moduleHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _softBackground,
              border: Border(
                bottom: BorderSide(
                  color: _borderColor.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  group.category.icon,
                  size: 17,
                  color: _primaryBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  group.category.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _deepNavy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                // Subtle count chip
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: _lightBlueTint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _primaryBlue.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        size: 12,
                        color: _primaryBlue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$enabled/${group.defs.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _primaryBlue,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
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
          // Permission rows
          for (var index = 0; index < group.defs.length; index++)
            _buildMatrixPermissionRow(
              group.defs[index],
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
    return OutlinedButton(
      onPressed: _isSaving ? null : onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: _white,
        foregroundColor: _deepNavy,
        side: BorderSide(color: _borderColor.withOpacity(0.7)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(0, 28),
        textStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: _deepNavy,
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: Text(label),
    );
  }

  Widget _buildMatrixPermissionRow(
    _PermissionDef def, {
    required bool isLast,
  }) {
    final value = def.read(_permissions);
    final disabledByConfig = _isDisabledByConfig(def);

    return InkWell(
      onTap: disabledByConfig || _isSaving
          ? null
          : () => _updatePermission((current) => def.write(current, !value)),
      hoverColor: _hoverTint,
      child: Container(
        constraints: const BoxConstraints(minHeight: _rowMinHeight),
        decoration: BoxDecoration(
          color: value ? _lightBlueTint.withOpacity(0.35) : _white,
          border: Border(
            bottom: BorderSide(
              color: isLast
                  ? Colors.transparent
                  : _borderColor.withOpacity(0.4),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
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
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: disabledByConfig
                                  ? _secondaryText.withOpacity(0.5)
                                  : _deepNavy,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _riskPill(def.riskLevel),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      def.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _secondaryText,
                        height: 1.3,
                      ),
                    ),
                    if (disabledByConfig) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Requiere activar el flujo completo de cotizaciones desde Configuracion del negocio.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _warningAmber,
                          fontWeight: FontWeight.w600,
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
                child: _buildPermissionTypeChip(def.column),
              ),
            ),
            Expanded(
              flex: 1,
              child: _buildMatrixToggleCell(
                active: value,
                enabled: !disabledByConfig && !_isSaving,
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

  Widget _buildPermissionTypeChip(_PermissionColumn column) {
    return Container(
      constraints: const BoxConstraints(minWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _primaryBlue.withOpacity(0.3)),
      ),
      child: Text(
        column.label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _primaryBlue,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildMatrixToggleCell({
    required bool active,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return Center(
      child: Theme(
        data: ThemeData(
          checkboxTheme: CheckboxThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: BorderSide(
              color: enabled
                  ? _borderColor
                  : _borderColor.withOpacity(0.4),
              width: 1.5,
            ),
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _primaryBlue;
              }
              return _white;
            }),
            checkColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _white;
              }
              return Colors.transparent;
            }),
            visualDensity: const VisualDensity(
              horizontal: -4,
              vertical: -4,
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: Checkbox(
          value: active,
          onChanged: enabled ? (_) => onTap?.call() : null,
        ),
      ),
    );
  }

  Widget _buildAdminMessage(int enabledCount, int totalCount) {
    final currentUser = _selectedUser;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _lightBlueTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.admin_panel_settings_outlined,
                size: 36,
                color: _primaryBlue,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Perfil con acceso total',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _deepNavy,
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Este usuario pertenece al rol administrador. El sistema mantiene todos los permisos habilitados para preservar la operacion completa y la capacidad de soporte.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _secondaryText,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _buildHeaderBadge(
                  icon: Icons.check_circle_outline,
                  label: '$enabledCount de $totalCount permisos activos',
                  tone: _primaryBlue,
                ),
                _buildHeaderBadge(
                  icon: Icons.lock_open_outlined,
                  label: currentUser == null
                      ? 'Selecciona un usuario'
                      : 'Edicion deshabilitada para ${currentUser.displayLabel}',
                  tone: _secondaryText,
                ),
              ],
            ),
          ],
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
        background = const Color(0xFFF1F5F9);
        foreground = const Color(0xFF475569);
        label = 'Bajo';
        break;
      case _RiskLevel.medium:
        background = const Color(0xFFFFFBEB);
        foreground = const Color(0xFF92400E);
        label = 'Medio';
        break;
      case _RiskLevel.high:
        background = const Color(0xFFFFF7ED);
        foreground = const Color(0xFF9A3412);
        label = 'Alto';
        break;
      case _RiskLevel.critical:
        background = const Color(0xFFFEF2F2);
        foreground = const Color(0xFF991B1B);
        label = 'Critico';
        break;
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: foreground.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}
