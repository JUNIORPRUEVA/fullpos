class TemporaryAuthorizationEntry {
  final String scope;
  final DateTime expiresAt;
  final String approvedByUserId;

  const TemporaryAuthorizationEntry({
    required this.scope,
    required this.expiresAt,
    required this.approvedByUserId,
  });
}

class TemporaryAuthorizationService {
  TemporaryAuthorizationService._();

  static const Duration defaultDuration = Duration(minutes: 2);
  static final Map<String, TemporaryAuthorizationEntry> _authorizations =
      <String, TemporaryAuthorizationEntry>{};

  static DateTime Function() _now = DateTime.now;

  static void debugSetClock(DateTime Function() now) {
    _now = now;
  }

  static void debugResetClock() {
    _now = DateTime.now;
  }

  static String normalizeScope(String scope) {
    switch (scope.trim()) {
      case 'sale.discount':
        return 'sales.apply_discount';
      case 'sale.cancel':
      case 'sale.delete':
        return 'sales.cancel_sale';
      case 'cash.withdraw':
        return 'cash.manual_movement';
      case 'cash.close_shift':
        return 'cash.close_session';
      case 'product.edit_price':
        return 'inventory.edit_sale_price';
      case 'settings.modify':
        return 'settings.update_taxes';
      default:
        return scope.trim();
    }
  }

  static void authorize({
    required String scope,
    Duration duration = defaultDuration,
    required String approvedByUserId,
  }) {
    final normalizedScope = normalizeScope(scope);
    if (normalizedScope.isEmpty) return;
    final effectiveDuration = duration < defaultDuration
        ? defaultDuration
        : duration;
    _authorizations[normalizedScope] = TemporaryAuthorizationEntry(
      scope: normalizedScope,
      expiresAt: _now().add(effectiveDuration),
      approvedByUserId: approvedByUserId,
    );
  }

  static bool isAuthorized(String scope) {
    final normalizedScope = normalizeScope(scope);
    return _isAuthorizedExact(normalizedScope);
  }

  static bool _isAuthorizedExact(String scope) {
    final entry = _authorizations[scope];
    if (entry == null) return false;
    if (!_now().isBefore(entry.expiresAt)) {
      _authorizations.remove(scope);
      return false;
    }
    return true;
  }

  static void clearAuthorization(String scope) {
    _authorizations.remove(normalizeScope(scope));
  }

  static void clearAll() {
    _authorizations.clear();
  }
}
