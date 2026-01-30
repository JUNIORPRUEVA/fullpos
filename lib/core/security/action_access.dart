import '../../features/settings/data/user_model.dart';
import 'app_actions.dart';

/// Single source of truth for "does this user have access to this critical action"
/// based on module-level permissions (UserPermissions).
///
/// This intentionally ignores the legacy per-action table (`user_permissions`).
/// Per the current product rules, module toggles are the authority; if a user
/// doesn't have module access, they may still proceed only via an admin override
/// (AuthorizationModal) at the call site.
class ActionAccess {
  ActionAccess._();

  static bool isAllowed({
    required AppAction action,
    required bool isAdmin,
    required UserPermissions permissions,
  }) {
    if (isAdmin) return true;

    switch (action.category) {
      case AppActionCategory.settings:
        return permissions.canAccessSettings;
      case AppActionCategory.users:
        return permissions.canManageUsers;
      case AppActionCategory.sales:
        return _allowedBySalesModule(action, permissions);
      case AppActionCategory.inventory:
        return _allowedByInventoryModule(action, permissions);
      case AppActionCategory.cash:
        return _allowedByCashModule(action, permissions);
    }
  }

  static bool _allowedBySalesModule(AppAction action, UserPermissions permissions) {
    switch (action.code) {
      case 'sales.cancel_sale':
        return permissions.canVoidSale;
      case 'sales.delete_item':
        return permissions.canSell;
      case 'sales.modify_line_price':
        return permissions.canApplyDiscount;
      case 'sales.apply_discount':
      case 'sales.apply_discount_over_limit':
        return permissions.canApplyDiscount;
      case 'sales.charge_sale':
        return permissions.canSell;
      case 'sales.create_quote':
        return permissions.canCreateQuotes;
      case 'sales.grant_credit':
        return permissions.canManageCredits;
      case 'sales.create_layaway':
        return permissions.canSell;
      case 'sales.process_return':
        return permissions.canProcessReturns;
      case 'sales.delete_client':
        return permissions.canDeleteClients;
    }
    return false;
  }

  static bool _allowedByInventoryModule(AppAction action, UserPermissions permissions) {
    switch (action.code) {
      case 'inventory.adjust_stock':
        return permissions.canAdjustStock;
      case 'inventory.edit_cost':
      case 'inventory.edit_sale_price':
        return permissions.canViewPurchasePrice && permissions.canViewProducts;
      case 'inventory.delete_product':
        return permissions.canDeleteProducts;
      case 'inventory.create_product':
      case 'inventory.update_product':
      case 'inventory.import_products':
      case 'inventory.delete_category':
        return permissions.canEditProducts;
    }
    return false;
  }

  static bool _allowedByCashModule(AppAction action, UserPermissions permissions) {
    switch (action.code) {
      case 'cash.open_session':
        return permissions.canOpenCash;
      case 'cash.close_session':
        return permissions.canCloseCash;
      case 'cash.manual_movement':
        return permissions.canMakeCashMovements;
    }
    return false;
  }
}
