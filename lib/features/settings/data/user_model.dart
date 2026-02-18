/// Modelo de usuario del sistema
class UserModel {
  final int? id;
  final int companyId;
  final String username;
  final String? displayName;
  final String? pin;
  final String? passwordHash;
  final String role; // 'admin' o 'cashier'
  final int isActive;
  final String? permissions; // JSON string con permisos personalizados
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  UserModel({
    this.id,
    this.companyId = 1,
    required this.username,
    this.displayName,
    this.pin,
    this.passwordHash,
    this.role = 'cashier',
    this.isActive = 1,
    this.permissions,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deletedAtMs,
  });

  bool get isAdmin => role == 'admin';
  bool get isSupervisor => role == 'supervisor';
  bool get isCashier => role == 'cashier';
  bool get isActiveUser => isActive == 1;
  bool get hasPassword => passwordHash != null && passwordHash!.isNotEmpty;

  String get roleLabel =>
      isAdmin ? 'Administrador' : isSupervisor ? 'Supervisor' : 'Cajero';
  String get displayLabel => displayName ?? username;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'company_id': companyId,
    'username': username,
    'display_name': displayName,
    'pin': pin,
    'password_hash': passwordHash,
    'role': role,
    'is_active': isActive,
    'permissions': permissions,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
    'deleted_at_ms': deletedAtMs,
  };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
    id: map['id'] as int?,
    companyId: map['company_id'] as int? ?? 1,
    username: map['username'] as String,
    displayName: map['display_name'] as String?,
    pin: map['pin'] as String?,
    passwordHash: map['password_hash'] as String?,
    role: map['role'] as String? ?? 'cashier',
    isActive: map['is_active'] as int? ?? 1,
    permissions: map['permissions'] as String?,
    createdAtMs: map['created_at_ms'] as int,
    updatedAtMs: map['updated_at_ms'] as int,
    deletedAtMs: map['deleted_at_ms'] as int?,
  );

  UserModel copyWith({
    int? id,
    int? companyId,
    String? username,
    String? displayName,
    String? pin,
    String? passwordHash,
    String? role,
    int? isActive,
    String? permissions,
    int? createdAtMs,
    int? updatedAtMs,
    int? deletedAtMs,
  }) => UserModel(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    pin: pin ?? this.pin,
    passwordHash: passwordHash ?? this.passwordHash,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
    permissions: permissions ?? this.permissions,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    deletedAtMs: deletedAtMs ?? this.deletedAtMs,
  );
}

/// Modelo de permisos del sistema
class UserPermissions {
  // Ventas
  final bool canSell;
  final bool canVoidSale;
  final bool canApplyDiscount;
  final bool canViewSalesHistory;
  
  // Productos
  final bool canViewProducts;
  final bool canEditProducts;
  final bool canDeleteProducts;
  final bool canAdjustStock;

  // Costos / Ganancias (finanzas de productos)
  final bool canViewPurchasePrice;
  final bool canViewProfit;
  
  // Clientes
  final bool canViewClients;
  final bool canEditClients;
  final bool canDeleteClients;
  
  // Caja
  final bool canOpenCash;
  final bool canCloseCash;
  final bool canViewCashHistory;
  final bool canMakeCashMovements;
  final bool canOpenCashbox;
  final bool canCloseCashbox;
  final bool canOpenShift;
  final bool canCloseShift;
  final bool canExitWithOpenShift;
  
  // Reportes
  final bool canViewReports;
  final bool canExportReports;
  
  // Cotizaciones
  final bool canCreateQuotes;
  final bool canViewQuotes;
  
  // Herramientas
  final bool canAccessTools;
  
  // Devoluciones
  final bool canProcessReturns;
  
  // Créditos
  final bool canViewCredits;
  final bool canManageCredits;
  
  // Usuarios (solo admin normalmente)
  final bool canManageUsers;
  
  // Configuración
  final bool canAccessSettings;

  const UserPermissions({
    this.canSell = false,
    this.canVoidSale = false,
    this.canApplyDiscount = false,
    this.canViewSalesHistory = false,
    this.canViewProducts = false,
    this.canEditProducts = false,
    this.canDeleteProducts = false,
    this.canAdjustStock = false,
    this.canViewPurchasePrice = false,
    this.canViewProfit = false,
    this.canViewClients = false,
    this.canEditClients = false,
    this.canDeleteClients = false,
    this.canOpenCash = false,
    this.canCloseCash = false,
    this.canViewCashHistory = false,
    this.canMakeCashMovements = false,
    this.canOpenCashbox = false,
    this.canCloseCashbox = false,
    this.canOpenShift = false,
    this.canCloseShift = false,
    this.canExitWithOpenShift = false,
    this.canViewReports = false,
    this.canExportReports = false,
    this.canCreateQuotes = false,
    this.canViewQuotes = false,
    this.canAccessTools = false,
    this.canProcessReturns = false,
    this.canViewCredits = false,
    this.canManageCredits = false,
    this.canManageUsers = false,
    this.canAccessSettings = false,
  });

  /// Sin permisos (deny-all)
  factory UserPermissions.none() => const UserPermissions(
        canSell: false,
        canVoidSale: false,
        canApplyDiscount: false,
        canViewSalesHistory: false,
        canViewProducts: false,
        canEditProducts: false,
        canDeleteProducts: false,
        canAdjustStock: false,
        canViewPurchasePrice: false,
        canViewProfit: false,
        canViewClients: false,
        canEditClients: false,
        canDeleteClients: false,
        canOpenCash: false,
        canCloseCash: false,
        canViewCashHistory: false,
        canMakeCashMovements: false,
        canOpenCashbox: false,
        canCloseCashbox: false,
        canOpenShift: false,
        canCloseShift: false,
        canExitWithOpenShift: false,
        canViewReports: false,
        canExportReports: false,
        canCreateQuotes: false,
        canViewQuotes: false,
        canAccessTools: false,
        canProcessReturns: false,
        canViewCredits: false,
        canManageCredits: false,
        canManageUsers: false,
        canAccessSettings: false,
      );

  /// Permisos completos para admin
  factory UserPermissions.admin() => const UserPermissions(
    canSell: true,
    canVoidSale: true,
    canApplyDiscount: true,
    canViewSalesHistory: true,
    canViewProducts: true,
    canEditProducts: true,
    canDeleteProducts: true,
    canAdjustStock: true,
    canViewPurchasePrice: true,
    canViewProfit: true,
    canViewClients: true,
    canEditClients: true,
    canDeleteClients: true,
    canOpenCash: true,
    canCloseCash: true,
    canViewCashHistory: true,
    canMakeCashMovements: true,
    canOpenCashbox: true,
    canCloseCashbox: true,
    canOpenShift: true,
    canCloseShift: true,
    canExitWithOpenShift: true,
    canViewReports: true,
    canExportReports: true,
    canCreateQuotes: true,
    canViewQuotes: true,
    canAccessTools: true,
    canProcessReturns: true,
    canViewCredits: true,
    canManageCredits: true,
    canManageUsers: true,
    canAccessSettings: true,
  );

  /// Permisos básicos para cajero
  factory UserPermissions.cashier() => const UserPermissions(
    canSell: true,
    canVoidSale: false,
    canApplyDiscount: true,
    canViewSalesHistory: true,
    canViewProducts: true,
    canEditProducts: false,
    canDeleteProducts: false,
    canAdjustStock: false,
    canViewPurchasePrice: false,
    canViewProfit: false,
    canViewClients: true,
    canEditClients: true,
    canDeleteClients: false,
    canOpenCash: true,
    canCloseCash: true,
    canViewCashHistory: false,
    canMakeCashMovements: false,
    canOpenCashbox: false,
    canCloseCashbox: false,
    canOpenShift: true,
    canCloseShift: true,
    canExitWithOpenShift: false,
    canViewReports: false,
    canExportReports: false,
    canCreateQuotes: true,
    canViewQuotes: true,
    canAccessTools: false,
    canProcessReturns: false,
    canViewCredits: true,
    canManageCredits: false,
    canManageUsers: false,
    canAccessSettings: false,
  );

  Map<String, dynamic> toMap() => {
    'can_sell': canSell,
    'can_void_sale': canVoidSale,
    'can_apply_discount': canApplyDiscount,
    'can_view_sales_history': canViewSalesHistory,
    'can_view_products': canViewProducts,
    'can_edit_products': canEditProducts,
    'can_delete_products': canDeleteProducts,
    'can_adjust_stock': canAdjustStock,
    'can_view_purchase_price': canViewPurchasePrice,
    'can_view_profit': canViewProfit,
    'can_view_clients': canViewClients,
    'can_edit_clients': canEditClients,
    'can_delete_clients': canDeleteClients,
    'can_open_cash': canOpenCash,
    'can_close_cash': canCloseCash,
    'can_view_cash_history': canViewCashHistory,
    'can_make_cash_movements': canMakeCashMovements,
    'can_open_cashbox': canOpenCashbox,
    'can_close_cashbox': canCloseCashbox,
    'can_open_shift': canOpenShift,
    'can_close_shift': canCloseShift,
    'can_exit_with_open_shift': canExitWithOpenShift,
    'can_view_reports': canViewReports,
    'can_export_reports': canExportReports,
    'can_create_quotes': canCreateQuotes,
    'can_view_quotes': canViewQuotes,
    'can_access_tools': canAccessTools,
    'can_process_returns': canProcessReturns,
    'can_view_credits': canViewCredits,
    'can_manage_credits': canManageCredits,
    'can_manage_users': canManageUsers,
    'can_access_settings': canAccessSettings,
  };

  factory UserPermissions.fromMap(Map<String, dynamic> map) {
    final defaults = UserPermissions.cashier();

    return UserPermissions(
      canSell: map['can_sell'] as bool? ?? defaults.canSell,
      canVoidSale: map['can_void_sale'] as bool? ?? defaults.canVoidSale,
      canApplyDiscount:
          map['can_apply_discount'] as bool? ?? defaults.canApplyDiscount,
      canViewSalesHistory: map['can_view_sales_history'] as bool? ??
          defaults.canViewSalesHistory,
      canViewProducts:
          map['can_view_products'] as bool? ?? defaults.canViewProducts,
      canEditProducts:
          map['can_edit_products'] as bool? ?? defaults.canEditProducts,
      canDeleteProducts:
          map['can_delete_products'] as bool? ?? defaults.canDeleteProducts,
      canAdjustStock:
          map['can_adjust_stock'] as bool? ?? defaults.canAdjustStock,
      canViewPurchasePrice: map['can_view_purchase_price'] as bool? ??
          defaults.canViewPurchasePrice,
      canViewProfit:
          map['can_view_profit'] as bool? ?? defaults.canViewProfit,
      canViewClients: map['can_view_clients'] as bool? ?? defaults.canViewClients,
      canEditClients: map['can_edit_clients'] as bool? ?? defaults.canEditClients,
      canDeleteClients:
          map['can_delete_clients'] as bool? ?? defaults.canDeleteClients,
        canOpenCash: map['can_open_cash'] as bool? ?? defaults.canOpenCash,
        canCloseCash: map['can_close_cash'] as bool? ?? defaults.canCloseCash,
      canViewCashHistory:
          map['can_view_cash_history'] as bool? ?? defaults.canViewCashHistory,
      canMakeCashMovements: map['can_make_cash_movements'] as bool? ??
          defaults.canMakeCashMovements,
        canOpenCashbox:
          map['can_open_cashbox'] as bool? ??
          map['can_open_cash'] as bool? ??
          defaults.canOpenCashbox,
        canCloseCashbox:
          map['can_close_cashbox'] as bool? ??
          map['can_close_cash'] as bool? ??
          defaults.canCloseCashbox,
        canOpenShift:
          map['can_open_shift'] as bool? ??
          map['can_open_cash'] as bool? ??
          defaults.canOpenShift,
        canCloseShift:
          map['can_close_shift'] as bool? ??
          map['can_close_cash'] as bool? ??
          defaults.canCloseShift,
        canExitWithOpenShift:
          map['can_exit_with_open_shift'] as bool? ??
          defaults.canExitWithOpenShift,
      canViewReports:
          map['can_view_reports'] as bool? ?? defaults.canViewReports,
      canExportReports:
          map['can_export_reports'] as bool? ?? defaults.canExportReports,
      canCreateQuotes:
          map['can_create_quotes'] as bool? ?? defaults.canCreateQuotes,
      canViewQuotes:
          map['can_view_quotes'] as bool? ?? defaults.canViewQuotes,
      canAccessTools:
          map['can_access_tools'] as bool? ?? defaults.canAccessTools,
      canProcessReturns:
          map['can_process_returns'] as bool? ?? defaults.canProcessReturns,
      canViewCredits:
          map['can_view_credits'] as bool? ?? defaults.canViewCredits,
      canManageCredits:
          map['can_manage_credits'] as bool? ?? defaults.canManageCredits,
      canManageUsers:
          map['can_manage_users'] as bool? ?? defaults.canManageUsers,
      canAccessSettings:
          map['can_access_settings'] as bool? ?? defaults.canAccessSettings,
    );
  }

  UserPermissions copyWith({
    bool? canSell,
    bool? canVoidSale,
    bool? canApplyDiscount,
    bool? canViewSalesHistory,
    bool? canViewProducts,
    bool? canEditProducts,
    bool? canDeleteProducts,
    bool? canAdjustStock,
    bool? canViewPurchasePrice,
    bool? canViewProfit,
    bool? canViewClients,
    bool? canEditClients,
    bool? canDeleteClients,
    bool? canOpenCash,
    bool? canCloseCash,
    bool? canViewCashHistory,
    bool? canMakeCashMovements,
    bool? canOpenCashbox,
    bool? canCloseCashbox,
    bool? canOpenShift,
    bool? canCloseShift,
    bool? canExitWithOpenShift,
    bool? canViewReports,
    bool? canExportReports,
    bool? canCreateQuotes,
    bool? canViewQuotes,
    bool? canAccessTools,
    bool? canProcessReturns,
    bool? canViewCredits,
    bool? canManageCredits,
    bool? canManageUsers,
    bool? canAccessSettings,
  }) => UserPermissions(
    canSell: canSell ?? this.canSell,
    canVoidSale: canVoidSale ?? this.canVoidSale,
    canApplyDiscount: canApplyDiscount ?? this.canApplyDiscount,
    canViewSalesHistory: canViewSalesHistory ?? this.canViewSalesHistory,
    canViewProducts: canViewProducts ?? this.canViewProducts,
    canEditProducts: canEditProducts ?? this.canEditProducts,
    canDeleteProducts: canDeleteProducts ?? this.canDeleteProducts,
    canAdjustStock: canAdjustStock ?? this.canAdjustStock,
    canViewPurchasePrice: canViewPurchasePrice ?? this.canViewPurchasePrice,
    canViewProfit: canViewProfit ?? this.canViewProfit,
    canViewClients: canViewClients ?? this.canViewClients,
    canEditClients: canEditClients ?? this.canEditClients,
    canDeleteClients: canDeleteClients ?? this.canDeleteClients,
    canOpenCash: canOpenCash ?? this.canOpenCash,
    canCloseCash: canCloseCash ?? this.canCloseCash,
    canViewCashHistory: canViewCashHistory ?? this.canViewCashHistory,
    canMakeCashMovements: canMakeCashMovements ?? this.canMakeCashMovements,
    canOpenCashbox: canOpenCashbox ?? this.canOpenCashbox,
    canCloseCashbox: canCloseCashbox ?? this.canCloseCashbox,
    canOpenShift: canOpenShift ?? this.canOpenShift,
    canCloseShift: canCloseShift ?? this.canCloseShift,
    canExitWithOpenShift: canExitWithOpenShift ?? this.canExitWithOpenShift,
    canViewReports: canViewReports ?? this.canViewReports,
    canExportReports: canExportReports ?? this.canExportReports,
    canCreateQuotes: canCreateQuotes ?? this.canCreateQuotes,
    canViewQuotes: canViewQuotes ?? this.canViewQuotes,
    canAccessTools: canAccessTools ?? this.canAccessTools,
    canProcessReturns: canProcessReturns ?? this.canProcessReturns,
    canViewCredits: canViewCredits ?? this.canViewCredits,
    canManageCredits: canManageCredits ?? this.canManageCredits,
    canManageUsers: canManageUsers ?? this.canManageUsers,
    canAccessSettings: canAccessSettings ?? this.canAccessSettings,
  );
}
