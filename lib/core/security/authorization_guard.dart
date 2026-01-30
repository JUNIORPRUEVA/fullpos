import 'package:flutter/material.dart';

import '../../features/settings/data/users_repository.dart';
import '../session/session_manager.dart';
import 'action_access.dart';
import 'app_actions.dart';
import 'permission_service.dart';
import 'security_config.dart';
import '../../widgets/authorization_modal.dart';

/// Helper central para exigir autorización adicional en acciones críticas.
Future<bool> requireAuthorizationIfNeeded({
  required BuildContext context,
  required AppAction action,
  required String resourceType,
  String? resourceId,
  String? reason,
  SecurityConfig? config,
  bool isOnline = true,
}) async {
  final userId = await SessionManager.userId();
  final role = await SessionManager.role() ?? PermissionService.roleCashier;
  final companyId = await SessionManager.companyId() ?? 1;
  final terminalId =
      await SessionManager.terminalId() ??
      await SessionManager.ensureTerminalId();

  if (userId == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No hay usuario autenticado')));
    return false;
  }

  final userPermissions = await UsersRepository.getPermissions(userId);
  final isAdmin = await SessionManager.isAdmin();
  if (ActionAccess.isAllowed(
    action: action,
    isAdmin: isAdmin,
    permissions: userPermissions,
  )) {
    return true;
  }

  final decision = await PermissionService.check(
    actionCode: action.code,
    companyId: companyId,
    userId: userId,
    role: role,
    config: config,
  );

  if (!decision.overrideAllowed) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Acción bloqueada: ${action.name}')));
    return false;
  }
  final securityConfig =
      config ??
      await SecurityConfigRepository.load(
        companyId: companyId,
        terminalId: terminalId,
      );

  final authorized = await AuthorizationModal.show(
    context: context,
    action: action,
    resourceType: resourceType,
    resourceId: resourceId,
    companyId: companyId,
    requestedByUserId: userId,
    terminalId: terminalId,
    config: securityConfig,
    isOnline: isOnline,
  );
  return authorized;
}
