import 'dart:async';

import 'package:flutter/material.dart';

import 'authz_service.dart';
import 'permission.dart';

/// Gate de permisos que OCULTA el child si no está autorizado.
///
/// Caso de uso: pantallas sensibles (ej. Reportes) donde no se debe renderizar
/// nada del contenido hasta obtener permiso u override.
class BlankPermissionGate extends StatefulWidget {
  final Permission permission;
  final Widget child;
  final String? reason;
  final AuditMeta? meta;
  final String? resourceType;
  final String? resourceId;

  /// Si es true, solo intenta pedir autorización 1 vez automáticamente.
  final bool autoPromptOnce;

  const BlankPermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.reason,
    this.meta,
    this.resourceType,
    this.resourceId,
    this.autoPromptOnce = true,
  });

  @override
  State<BlankPermissionGate> createState() => _BlankPermissionGateState();
}

class _BlankPermissionGateState extends State<BlankPermissionGate> {
  bool _authorized = false;
  bool _prompted = false;
  // Tracks which userId received the override so dispose() can clear it on unmount.
  int? _overrideUserId;

  @override
  void initState() {
    super.initState();
    unawaited(_checkAndPromptIfNeeded());
  }

  @override
  void dispose() {
    // When this screen/widget is unmounted (navigated away, popped, closed),
    // explicitly remove the temporary override so re-entry always requires fresh
    // authorization. This enforces the one-use-per-visit rule for non-admin users.
    if (_overrideUserId != null) {
      AuthzService.clearOverrideFor(
        userId: _overrideUserId!,
        permission: widget.permission,
      );
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BlankPermissionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.permission.code != widget.permission.code ||
        oldWidget.resourceId != widget.resourceId ||
        oldWidget.resourceType != widget.resourceType) {
      _authorized = false;
      _prompted = false;
      _overrideUserId = null;
      unawaited(_checkAndPromptIfNeeded());
    }
  }

  Future<void> _checkAndPromptIfNeeded() async {
    if (!mounted) return;
    setState(() {});

    try {
      final user = await AuthzService.currentUser();
      if (!mounted) return;

      if (user == null) {
        setState(() {
          _authorized = false;
        });
        return;
      }

      final can = AuthzService.can(user, widget.permission);
      if (can) {
        // If access is via a temporary override (not native admin permission),
        // record the userId so dispose() can clear the override on unmount.
        if (!user.isAdmin) _overrideUserId = user.userId;
        setState(() {
          _authorized = true;
        });
        return;
      }

      final canPrompt = !widget.autoPromptOnce || !_prompted;
      if (!canPrompt) {
        setState(() {
          _authorized = false;
        });
        return;
      }

      _prompted = true;
      // Usamos el flujo oficial de autorización (PIN admin) como modal.
      final ok = await AuthzService.require(
        context,
        user,
        widget.permission,
        reason: widget.reason,
        meta: widget.meta,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
      );

      if (!mounted) return;
      if (ok) _overrideUserId = user.userId;
      setState(() {
        _authorized = ok;
      });
    } catch (e, st) {
      debugPrint(
        'BlankPermissionGate error (${widget.permission.code}): $e\n$st',
      );
      if (!mounted) return;
      setState(() {
        _authorized = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_authorized) return widget.child;

    final bg = Theme.of(context).colorScheme.surface;

    // En modo no-autorizado: pantalla en blanco (sin renderizar el contenido).
    // El modal de autorización se muestra automáticamente desde initState.
    return ColoredBox(color: bg, child: const SizedBox.expand());
  }
}
