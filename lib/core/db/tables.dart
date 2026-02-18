/// Nombres de tablas de la base de datos
class DbTables {
  DbTables._();

  static const String appConfig = 'app_config';
  static const String clients = 'clients';
  static const String categories = 'categories';
  static const String suppliers = 'suppliers';
  static const String products = 'products';
  static const String stockMovements = 'stock_movements';

  // Compras / ordenes de compra
  static const String purchaseOrders = 'compras_ordenes';
  static const String purchaseOrderItems = 'compras_detalle';

  // Ventas
  static const String sales = 'sales';
  static const String saleItems = 'sale_items';
  static const String returns = 'returns';

  // Configuracion de negocio y fiscal
  static const String businessInfo = 'business_info';
  static const String appSettings = 'app_settings';
  static const String ncfBooks = 'ncf_books';
  static const String customersNcfUsage = 'customers_ncf_usage';

  // Usuarios y caja
  static const String users = 'users';
  static const String cashboxDaily = 'cashbox_daily';
  static const String cashSessions = 'cash_sessions';
  static const String cashMovements = 'cash_movements';

  // Tickets POS y Cotizaciones
  static const String posTickets = 'pos_tickets';
  static const String posTicketItems = 'pos_ticket_items';
  static const String quotes = 'quotes';
  static const String quoteItems = 'quote_items';

  // Carritos temporales de ventas
  static const String tempCarts = 'temp_carts';
  static const String tempCartItems = 'temp_cart_items';

  // Configuracion de impresora y creditos
  static const String printerSettings = 'printer_settings';
  static const String creditPayments = 'credit_payments';
  static const String layawayPayments = 'layaway_payments';
  static const String returnItems = 'return_items';

  // Seguridad y multi-tenant
  static const String companies = 'companies';
  static const String terminals = 'terminals';
  static const String userPermissions = 'user_permissions';
  static const String overrideTokens = 'override_tokens';
  static const String overrideRequests = 'override_requests';
  static const String auditLog = 'audit_log';
  static const String backupHistory = 'backup_history';
  static const String dangerActionsLog = 'danger_actions_log';

  // Futuros modulos
  static const String pawn = 'pawn';
  static const String services = 'services';
}
