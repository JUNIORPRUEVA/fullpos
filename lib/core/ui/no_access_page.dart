import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/data/user_model.dart';
import '../security/module_access.dart';

class NoAccessPage extends StatelessWidget {
  final String requestedPath;
  final bool isAdmin;
  final UserPermissions permissions;

  const NoAccessPage({
    super.key,
    required this.requestedPath,
    required this.isAdmin,
    required this.permissions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final label = ModuleAccess.moduleLabelForPath(requestedPath);
    final fallback = _fallbackLocation(isAdmin, permissions);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest.withOpacity(0.55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: scheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.error.withOpacity(0.25)),
                  ),
                  child: Icon(Icons.lock_outline, color: scheme.error, size: 26),
                ),
                const SizedBox(height: 14),
                Text(
                  'Sin acceso',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'No tienes permiso para entrar a: $label',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withOpacity(0.78),
                    height: 1.25,
                  ),
                ),
                if (requestedPath.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    requestedPath,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go(fallback),
                        icon: const Icon(Icons.home_outlined, size: 18),
                        label: const Text('Ir al inicio'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final router = GoRouter.of(context);
                          final canPopRouter =
                              router.routerDelegate.currentConfiguration.matches.length >
                              1;
                          if (canPopRouter) {
                            context.pop();
                          } else {
                            context.go(fallback);
                          }
                        },
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Volver'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Duplicado intencional: el router usa la misma heuristica para elegir fallback.
String _fallbackLocation(bool isAdmin, UserPermissions permissions) {
  if (isAdmin) return '/sales';
  if (permissions.canSell) return '/sales';
  if (permissions.canViewProducts) return '/products';
  if (permissions.canViewClients) return '/clients';
  if (permissions.canViewReports) return '/reports';
  if (permissions.canAdjustStock) return '/purchases';
  if (permissions.canAccessTools) return '/tools';
  if (permissions.canAccessSettings) return '/settings';
  return '/account';
}
