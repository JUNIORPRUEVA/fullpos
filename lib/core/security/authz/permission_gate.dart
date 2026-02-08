import 'dart:async';

import 'package:flutter/material.dart';

import 'authz_service.dart';
import 'permission.dart';

/// Gate de permisos que NO oculta el child.
///
/// Mantiene la UI igual pero bloquea interacción hasta autorizar.
class PermissionGate extends StatefulWidget {
  final Permission permission;
  final Widget child;
  final String? reason;
  final AuditMeta? meta;
  final String? resourceType;
  final String? resourceId;
  final bool autoPromptOnce;

  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.reason,
    this.meta,
    this.resourceType,
    this.resourceId,
    this.autoPromptOnce = false,
  });

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _authorized = false;
  bool _prompted = false;
  bool _checking = true;
  bool _promptScheduled = false;
  bool _autoPromptBlocked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkPermissionOnly());
  }

  @override
  void didUpdateWidget(covariant PermissionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.permission.code != widget.permission.code ||
        oldWidget.resourceId != widget.resourceId ||
        oldWidget.resourceType != widget.resourceType) {
      // Re-check on permission/context change.
      _authorized = false;
      _prompted = false;
      _autoPromptBlocked = false;
      _checking = true;
      unawaited(_checkPermissionOnly());
    }
  }

  Future<void> _checkPermissionOnly() async {
    try {
      final user = await AuthzService.currentUser();
      if (!mounted) return;

      if (user == null) {
        setState(() {
          _authorized = false;
          _autoPromptBlocked = true;
        });
        return;
      }

      final can = AuthzService.can(user, widget.permission);
      setState(() {
        _authorized = can;
        _autoPromptBlocked = !can;
      });
    } catch (e, st) {
      debugPrint(
        'PermissionGate precheck (${widget.permission.code}): $e\n$st',
      );
      if (!mounted) return;
      setState(() {
        _authorized = false;
        _autoPromptBlocked = true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _ensureAuthorized({bool userInitiated = false}) async {
    if (_checking) return;
    if (_authorized) return;
    if (!userInitiated && widget.autoPromptOnce && _prompted) return;

    setState(() {
      _checking = true;
      if (widget.autoPromptOnce) _prompted = true;
      _autoPromptBlocked = false;
    });
    try {
      final ok = await AuthzService.runGuardedCurrent<bool>(
        context,
        widget.permission,
        () async => true,
        reason: widget.reason,
        meta: widget.meta,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
      );
      if (!mounted) return;
      setState(() {
        _authorized = ok == true;
        _autoPromptBlocked = !(_authorized);
      });
    } catch (e, st) {
      debugPrint('PermissionGate error (${widget.permission.code}): $e\\n$st');
      if (!mounted) return;
      setState(() {
        _authorized = false;
        _autoPromptBlocked = true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _scheduleAuthorizationPrompt() {
    if (!widget.autoPromptOnce) return;
    if (_authorized || _checking || _promptScheduled || _autoPromptBlocked) {
      return;
    }
    if (widget.autoPromptOnce && _prompted) return;

    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptScheduled = false;
      if (!mounted) return;
      _ensureAuthorized();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      _scheduleAuthorizationPrompt();
    }

    return Stack(
      children: [
        AbsorbPointer(absorbing: !_authorized, child: widget.child),
        if (!_authorized) ...[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.08),
              ),
              child: const ModalBarrier(dismissible: false),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Center(
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.9),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => _ensureAuthorized(userInitiated: true),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Acción prohibida',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Autorizar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
