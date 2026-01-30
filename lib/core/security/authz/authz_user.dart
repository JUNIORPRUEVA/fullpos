import '../../../features/settings/data/user_model.dart';

/// Modelo de usuario para autorización (no depende de widgets).
///
/// Nota: `modulePermissions` viene del sistema legacy (`UserPermissions` JSON).
/// `actionPermissions` viene del sistema de acciones críticas (AppActions/DB).
class AuthzUser {
  final int userId;
  final int companyId;
  final String role;
  final String terminalId;
  final UserPermissions modulePermissions;
  final Map<String, bool> actionPermissions;

  const AuthzUser({
    required this.userId,
    required this.companyId,
    required this.role,
    required this.terminalId,
    required this.modulePermissions,
    required this.actionPermissions,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
}

/// API pedida: `can(User u, Permission p)` etc.
typedef User = AuthzUser;

