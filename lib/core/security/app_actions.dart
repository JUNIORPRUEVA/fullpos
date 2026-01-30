/// Definición centralizada de acciones críticas del POS.
///
/// Cada acción incluye:
/// - código único para persistencia y auditoría
/// - categoría para agrupar en UI
/// - nivel de riesgo
/// - si requiere override por defecto (configurable por empresa)
class AppAction {
  final String code;
  final String name;
  final String description;
  final AppActionCategory category;
  final ActionRisk risk;
  final bool requiresOverrideByDefault;
  final bool overrideAllowed;

  const AppAction({
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.risk,
    this.requiresOverrideByDefault = false,
    this.overrideAllowed = true,
  });
}

enum AppActionCategory { sales, inventory, cash, settings, users }

enum ActionRisk { low, medium, high, critical }

/// Catálogo único de acciones soportadas por el sistema.
class AppActions {
  AppActions._();

  // Ventas
  static const cancelSale = AppAction(
    code: 'sales.cancel_sale',
    name: 'Cancelar venta',
    description: 'Anula una venta existente y revierte stock y totales.',
    category: AppActionCategory.sales,
    risk: ActionRisk.critical,
    requiresOverrideByDefault: true,
  );
  static const deleteSaleItem = AppAction(
    code: 'sales.delete_item',
    name: 'Eliminar ítem',
    description: 'Quitar un ítem ya agregado a la venta/ticket.',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const modifyLinePrice = AppAction(
    code: 'sales.modify_line_price',
    name: 'Modificar precio en venta',
    description: 'Cambiar manualmente el precio de un ítem en el carrito.',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const applyDiscount = AppAction(
    code: 'sales.apply_discount',
    name: 'Aplicar descuento',
    description: 'Aplicar descuentos por línea o totales.',
    category: AppActionCategory.sales,
    risk: ActionRisk.medium,
    requiresOverrideByDefault: true,
  );
  static const applyDiscountOverLimit = AppAction(
    code: 'sales.apply_discount_over_limit',
    name: 'Aplicar descuento mayor al limite',
    description:
        'Aplicar descuento por encima del limite permitido (p.ej. >15%).',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const chargeSale = AppAction(
    code: 'sales.charge_sale',
    name: 'Cobrar venta',
    description: 'Procesar el cobro y cerrar la venta.',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const createQuote = AppAction(
    code: 'sales.create_quote',
    name: 'Crear cotizacion',
    description: 'Guardar una cotizacion desde el POS.',
    category: AppActionCategory.sales,
    risk: ActionRisk.medium,
    requiresOverrideByDefault: true,
  );
  static const grantCredit = AppAction(
    code: 'sales.grant_credit',
    name: 'Dar credito',
    description: 'Vender a credito con condiciones y vencimiento.',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const createLayaway = AppAction(
    code: 'sales.create_layaway',
    name: 'Apartado',
    description: 'Registrar un apartado con abono inicial.',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );

  static const processReturn = AppAction(
    code: 'sales.process_return',
    name: 'Procesar devolución',
    description: 'Registrar devoluciones o reembolsos de ventas.',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );

  static const deleteClient = AppAction(
    code: 'sales.delete_client',
    name: 'Eliminar cliente',
    description: 'Eliminar o desactivar un cliente registrado.',
    category: AppActionCategory.sales,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );

  // Inventario
  static const adjustStock = AppAction(
    code: 'inventory.adjust_stock',
    name: 'Ajustar stock',
    description: 'Entrada, salida o ajuste directo de stock.',
    category: AppActionCategory.inventory,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const editCost = AppAction(
    code: 'inventory.edit_cost',
    name: 'Editar costo',
    description: 'Modificar el costo de un producto.',
    category: AppActionCategory.inventory,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const editSalePrice = AppAction(
    code: 'inventory.edit_sale_price',
    name: 'Editar precio de venta',
    description: 'Cambiar el precio de venta base de un producto.',
    category: AppActionCategory.inventory,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const deleteProduct = AppAction(
    code: 'inventory.delete_product',
    name: 'Eliminar producto',
    description: 'Borrar o desactivar productos del catálogo.',
    category: AppActionCategory.inventory,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const deleteCategory = AppAction(
    code: 'inventory.delete_category',
    name: 'Eliminar categoria',
    description: 'Borrar o desactivar categorias del catalogo.',
    category: AppActionCategory.inventory,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const createProduct = AppAction(
    code: 'inventory.create_product',
    name: 'Crear producto',
    description: 'Registrar productos nuevos en el catalogo.',
    category: AppActionCategory.inventory,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );

  static const updateProduct = AppAction(
    code: 'inventory.update_product',
    name: 'Editar producto',
    description:
        'Modificar un producto ya creado (sin incluir ajustes de stock).',
    category: AppActionCategory.inventory,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );

  static const importProducts = AppAction(
    code: 'inventory.import_products',
    name: 'Importar productos',
    description: 'Importar lotes de productos y costos desde archivos.',
    category: AppActionCategory.inventory,
    risk: ActionRisk.medium,
    requiresOverrideByDefault: false,
  );

  // Caja
  static const openCash = AppAction(
    code: 'cash.open_session',
    name: 'Abrir caja',
    description: 'Apertura de sesión de caja con monto inicial.',
    category: AppActionCategory.cash,
    risk: ActionRisk.medium,
    requiresOverrideByDefault: false,
  );
  static const closeCash = AppAction(
    code: 'cash.close_session',
    name: 'Cerrar caja',
    description: 'Cierre y corte de caja con totales.',
    category: AppActionCategory.cash,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const cashMovement = AppAction(
    code: 'cash.manual_movement',
    name: 'Movimiento manual de caja',
    description: 'Ingresos/Egresos manuales fuera del flujo de venta.',
    category: AppActionCategory.cash,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );

  // Configuración
  static const updateTaxes = AppAction(
    code: 'settings.update_taxes',
    name: 'Cambiar impuestos',
    description: 'Modificar tasas o reglas de impuestos.',
    category: AppActionCategory.settings,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const switchCompany = AppAction(
    code: 'settings.switch_company',
    name: 'Cambiar empresa',
    description: 'Cambiar/seleccionar tenant activo en el terminal.',
    category: AppActionCategory.settings,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const toggleSecurityMethods = AppAction(
    code: 'settings.toggle_security_methods',
    name: 'Activar/Desactivar métodos de seguridad',
    description:
        'Modificar configuración de overrides, métodos offline u online.',
    category: AppActionCategory.settings,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const configureScanner = AppAction(
    code: 'settings.configure_scanner',
    name: 'Configurar scanner',
    description: 'Cambiar prefijos, sufijos o tiempo de escucha del lector.',
    category: AppActionCategory.settings,
    risk: ActionRisk.medium,
    requiresOverrideByDefault: false,
  );

  // Usuarios
  static const createUser = AppAction(
    code: 'users.create_user',
    name: 'Crear usuario',
    description: 'Alta de nuevos usuarios en la empresa.',
    category: AppActionCategory.users,
    risk: ActionRisk.high,
    requiresOverrideByDefault: true,
  );
  static const updateRole = AppAction(
    code: 'users.update_role',
    name: 'Cambiar rol',
    description: 'Cambiar rol o perfil del usuario (ADMIN/SUPERVISOR/CASHIER).',
    category: AppActionCategory.users,
    risk: ActionRisk.critical,
    requiresOverrideByDefault: true,
  );
  static const resetPin = AppAction(
    code: 'users.reset_pin',
    name: 'Resetear PIN',
    description: 'Restablecer PIN/credenciales de otro usuario.',
    category: AppActionCategory.users,
    risk: ActionRisk.critical,
    requiresOverrideByDefault: true,
  );
  static const assignPermissions = AppAction(
    code: 'users.assign_permissions',
    name: 'Asignar permisos',
    description: 'Otorgar o revocar permisos finos por acción.',
    category: AppActionCategory.users,
    risk: ActionRisk.critical,
    requiresOverrideByDefault: true,
  );

  static const List<AppAction> all = [
    cancelSale,
    deleteSaleItem,
    modifyLinePrice,
    applyDiscount,
    applyDiscountOverLimit,
    chargeSale,
    createQuote,
    grantCredit,
    createLayaway,
    processReturn,
    deleteClient,
    adjustStock,
    editCost,
    editSalePrice,
    deleteProduct,
    deleteCategory,
    createProduct,
    updateProduct,
    importProducts,
    openCash,
    closeCash,
    cashMovement,
    updateTaxes,
    switchCompany,
    toggleSecurityMethods,
    configureScanner,
    createUser,
    updateRole,
    resetPin,
    assignPermissions,
  ];

  static AppAction? findByCode(String code) {
    for (final action in all) {
      if (action.code == code) return action;
    }
    return null;
  }

  static List<AppAction> byCategory(AppActionCategory category) =>
      all.where((a) => a.category == category).toList();

  /// Tabla de defaults: acción → riesgo → requiere override por defecto.
  static List<OverrideDefaultRow> get defaultOverrideTable => all
      .map(
        (a) => OverrideDefaultRow(
          actionCode: a.code,
          actionName: a.name,
          risk: a.risk,
          requiresOverride: a.requiresOverrideByDefault,
        ),
      )
      .toList();
}

class OverrideDefaultRow {
  final String actionCode;
  final String actionName;
  final ActionRisk risk;
  final bool requiresOverride;

  const OverrideDefaultRow({
    required this.actionCode,
    required this.actionName,
    required this.risk,
    required this.requiresOverride,
  });
}
