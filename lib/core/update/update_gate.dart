import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_update_coordinator.dart';

/// UpdateGate ya no bloquea la app.
///
/// Nueva regla: UpdateGate informa, pero nunca bloquea.
///
/// - Siempre retorna [widget.child] en build().
/// - No muestra pantallas completas, overlays ni diálogos automáticos.
/// - No impide la navegación ni el uso normal de FullPOS.
/// - Cuando hay una nueva versión disponible, muestra un aviso pequeño
///   centrado una vez por sesión, con acción "Ver" que navega a Updates.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child, this.coordinator});

  final Widget child;
  final AppUpdateCoordinator? coordinator;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late final AppUpdateCoordinator coordinator =
      widget.coordinator ?? AppUpdateCoordinator.instance;

  /// Almacena la versión (semantic+build) de la última actualización notificada
  /// en esta sesión. Si aparece una versión más nueva, se notifica de nuevo.
  String? _lastNotifiedVersionBuild;
  bool _notificationDialogOpen = false;

  @override
  void initState() {
    super.initState();
    coordinator.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    coordinator.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = coordinator.state;
    final phase = state.phase;

    if (phase == AppUpdatePhase.optional || phase == AppUpdatePhase.mandatory) {
      // Determinar un identificador único para esta versión (semantic+build)
      final policy = state.policy;
      final versionBuild = policy != null
          ? '${policy.latest.semantic}+${policy.latest.build}'
          : null;

      // Solo notificar si es una versión diferente a la ya notificada
      if (versionBuild != null && versionBuild != _lastNotifiedVersionBuild) {
        _lastNotifiedVersionBuild = versionBuild;
        _showUpdateNotification();
      }
    }
  }

  void _showUpdateNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isOnUpdateCenter()) return;
      if (_notificationDialogOpen) return;

      _notificationDialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.system_update_alt_rounded),
            title: const Text('Actualización disponible'),
            content: const Text(
              'Hay una nueva actualización de FullPOS disponible.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cerrar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  try {
                    context.push('/settings/updates');
                  } catch (_) {
                    // Si falla la navegación, no interrumpir al usuario.
                  }
                },
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Ver'),
              ),
            ],
          ),
        ).whenComplete(() {
          _notificationDialogOpen = false;
        }),
      );
    });
  }

  bool _isOnUpdateCenter() {
    try {
      return GoRouterState.of(context).uri.path == '/settings/updates';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Siempre retornar el child sin bloqueos.
    return widget.child;
  }
}
