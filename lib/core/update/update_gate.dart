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
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFD1F7)),
                          ),
                          child: const Icon(
                            Icons.system_update_alt_rounded,
                            color: Color(0xFF1A56DB),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Actualización disponible',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Hay una nueva versión de FullPOS lista para revisar.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Más tarde'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              try {
                                context.push('/settings/updates');
                              } catch (_) {
                                // Si falla la navegación, no interrumpir.
                              }
                            },
                            icon: const Icon(
                              Icons.visibility_rounded,
                              size: 18,
                            ),
                            label: const Text('Ver actualización'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
