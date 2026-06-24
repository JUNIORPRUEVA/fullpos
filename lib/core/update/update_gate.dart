import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../errors/error_handler.dart';
import '../logging/app_logger.dart';
import 'app_update_coordinator.dart';
import 'update_block_reason.dart';
import 'update_block_resolver_service.dart';
import 'update_shutdown_coordinator.dart';


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
  int _shownPresentationToken = 0;
  int _scheduledPresentationToken = 0;
  bool _optionalDialogVisible = false;
  bool _preparationDialogVisible = false;
  Timer? _navigatorRetryTimer;
  AppUpdatePhase? _lastLoggedPhase;
  int _lastLoggedPresentationToken = -1;

  @override
  void initState() {
    super.initState();
    coordinator.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _navigatorRetryTimer?.cancel();
    coordinator.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = coordinator.state;
    if (_lastLoggedPhase != state.phase ||
        _lastLoggedPresentationToken != state.presentationToken) {
      _lastLoggedPhase = state.phase;
      _lastLoggedPresentationToken = state.presentationToken;
      _log(
        'Update state received phase=${state.phase.name} '
        'presentationToken=${state.presentationToken}',
      );
    }

    // Mostrar diálogo de bloqueo cuando la actualización es mandatory
    // y hay bloqueos activos. Esto permite al usuario navegar para resolverlos.
    if (state.isMandatory &&
        state.isBlocked &&
        state.phase == AppUpdatePhase.ready &&
        state.presentationToken > _shownPresentationToken) {
      _scheduleOptionalDialog(state.presentationToken);
    }

    // Mostrar diálogo opcional normal (solo si no es mandatory).
    if (!state.isMandatory &&
        state.phase == AppUpdatePhase.ready &&
        state.presentationToken > _shownPresentationToken) {
      _scheduleOptionalDialog(state.presentationToken);
    }
    if (state.phase == AppUpdatePhase.launching && !_preparationDialogVisible) {
      _schedulePreparationDialog();
    }
    setState(() {});
  }


  void _schedulePreparationDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _preparationDialogVisible ||
          coordinator.state.phase != AppUpdatePhase.launching) {
        return;
      }
      unawaited(_showPreparationDialog());
    });
  }

  Future<void> _showPreparationDialog() async {
    final navigator = ErrorHandler.navigatorKey.currentState;
    final context = navigator?.overlay?.context;
    if (navigator == null || context == null || !context.mounted) return;
    _preparationDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => AnimatedBuilder(
          animation: coordinator,
          builder: (context, _) {
            final state = coordinator.state;
            if (state.phase != AppUpdatePhase.launching) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(context, rootNavigator: true).canPop()) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
              });
            }
            return AlertDialog(
              title: const Text('Preparando actualización'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 18),
                    Text(_preparationStepLabel(state.preparationStep)),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      _preparationDialogVisible = false;
    }
  }

  void _scheduleOptionalDialog(int presentationToken) {
    if (!mounted || presentationToken <= _shownPresentationToken) return;
    if (_optionalDialogVisible) {
      _shownPresentationToken = presentationToken;
      _log(
        'Optional update dialog skipped because it is already visible '
        'presentationToken=$presentationToken',
      );
      return;
    }
    if (_scheduledPresentationToken > 0) {
      if (presentationToken > _scheduledPresentationToken) {
        _scheduledPresentationToken = presentationToken;
      }
      _log(
        'Optional update dialog skipped because presentation is already '
        'scheduled presentationToken=$presentationToken',
      );
      return;
    }

    _scheduledPresentationToken = presentationToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scheduledToken = _scheduledPresentationToken;
      _scheduledPresentationToken = 0;
      if (!mounted) return;
      unawaited(_showOptionalDialog(scheduledToken));
    });
  }

  void _retryWhenNavigatorIsReady(int presentationToken) {
    if (_navigatorRetryTimer?.isActive ?? false) return;
    _navigatorRetryTimer = Timer(const Duration(milliseconds: 100), () {
      _navigatorRetryTimer = null;
      if (!mounted) return;
      final state = coordinator.state;
      if (state.isMandatory ||
          state.phase != AppUpdatePhase.ready ||
          state.presentationToken != presentationToken ||
          presentationToken <= _shownPresentationToken) {
        return;
      }
      _scheduleOptionalDialog(presentationToken);
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  Future<void> _showOptionalDialog(int presentationToken) async {
    final state = coordinator.state;
    final policy = state.policy;
    final installed = state.installed;
    if (policy == null ||
        installed == null ||
        state.phase != AppUpdatePhase.ready ||
        state.presentationToken != presentationToken ||
        presentationToken <= _shownPresentationToken) {
      return;
    }

    // Si hay bloqueos activos, mostrar el diálogo de bloqueo en lugar del normal.
    // Esto aplica tanto para mandatory como para optional.
    if (state.isBlocked) {
      await _showBlockedDialog();
      return;
    }

    // Si es mandatory y no está bloqueado, mostrar el diálogo normal.
    // Si es mandatory y está bloqueado, ya se manejó arriba.
    if (state.isMandatory) {
      return;
    }


    final navigator = ErrorHandler.navigatorKey.currentState;
    final navigatorContext = navigator?.overlay?.context;
    if (!mounted ||
        navigator == null ||
        !navigator.mounted ||
        navigatorContext == null ||
        !navigatorContext.mounted) {
      _log(
        'Optional update navigator context unavailable; retry scheduled '
        'presentationToken=$presentationToken',
        warning: true,
      );
      _retryWhenNavigatorIsReady(presentationToken);
      return;
    }

    if (_optionalDialogVisible) {
      _log(
        'Optional update dialog skipped because it is already visible '
        'presentationToken=$presentationToken',
      );
      return;
    }

    _log(
      'Root navigator ready for optional update '
      'presentationToken=$presentationToken',
    );
    _optionalDialogVisible = true;
    _shownPresentationToken = presentationToken;
    _log('Optional update dialog shown presentationToken=$presentationToken');

    try {
      await showDialog<void>(
        context: navigatorContext,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Actualización lista para instalar'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FullPOS ya descargó la nueva versión. Presiona ‘Instalar ahora’ para cerrar el sistema, instalar la actualización automáticamente y abrir FullPOS nuevamente. Antes de continuar, asegúrate de no tener una venta en proceso.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Versión instalada: ${installed.semantic}+${installed.build}',
                  ),
                  Text('Versión disponible: ${policy.latest}'),
                  const SizedBox(height: 12),
                  Text(
                    policy.releaseTitle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ...policy.releaseNotes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('• $note'),
                    ),
                  ),
                  if (policy.installerSizeBytes != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Descarga aproximada: ${_formatBytes(policy.installerSizeBytes!)}',
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                  coordinator.dismissOptional();
                },
                child: const Text('Más tarde'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                  unawaited(coordinator.launchInstaller());
                },
                icon: const Icon(Icons.install_desktop_rounded),
                label: const Text('Instalar ahora'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _optionalDialogVisible = false;
      if (mounted) {
        final latestState = coordinator.state;
        if (!latestState.isMandatory &&
            latestState.phase == AppUpdatePhase.ready &&
            latestState.presentationToken > _shownPresentationToken) {
          _scheduleOptionalDialog(latestState.presentationToken);
        }
      }
    }
  }

  /// Muestra el diálogo "No se puede actualizar todavía" con las razones
  /// de bloqueo y la opción "Revisar proceso".
  Future<void> _showBlockedDialog() async {
    final state = coordinator.state;
    final reasons = state.blockReasons;
    if (reasons.isEmpty) return;

    final navigator = ErrorHandler.navigatorKey.currentState;
    final context = navigator?.overlay?.context;
    if (navigator == null || context == null || !context.mounted) return;

    _log(
      'Update install blocked reasons=${reasons.map((r) => r.code).join(',')}',
    );


    // Si hay una sola razón, mostrar mensaje específico.
    // Si hay múltiples, mostrar lista.
    final String title;
    final Widget content;
    final UpdateBlockReason primaryReason;

    if (reasons.length == 1) {
      primaryReason = reasons.first;
      title = 'No se puede actualizar todavía';
      content = Text(primaryReason.message);
    } else {
      primaryReason = reasons.reduce(
        (a, b) => a.priority <= b.priority ? a : b,
      );
      title = 'No se puede actualizar todavía';
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hay procesos abiertos que deben finalizarse antes de instalar la actualización:',
          ),
          const SizedBox(height: 12),
          for (final reason in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(reason.message)),
                ],
              ),
            ),
        ],
      );
    }

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: content,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                _log(
                  'User clicked "Más tarde" on blocked dialog',
                );
              },
              child: const Text('Más tarde'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                _log(
                  'User clicked "Revisar proceso" for ${primaryReason.code}',
                );

                unawaited(
                  const UpdateBlockResolverService()
                      .navigateToBlocker(primaryReason),
                );
              },
              icon: const Icon(Icons.search_rounded),
              label: const Text('Revisar proceso'),
            ),
          ],
        ),
      ),
    );
  }


  void _log(String message, {bool warning = false}) {
    if (!coordinator.loggingEnabled) return;
    final future = warning
        ? AppLogger.instance.logWarn(message, module: 'app_update')
        : AppLogger.instance.logInfo(message, module: 'app_update');
    unawaited(future.catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final state = coordinator.state;

    // Regla 1: Nunca mostrar pantalla de actualización durante fases de
    // descarga/verificación. El instalador se descarga en segundo plano.
    // El usuario debe poder usar la app normalmente.
    //
    // Regla 2: Solo mostrar diálogo (no pantalla completa) cuando el
    // instalador está listo (phase == ready).
    //
    // Regla 3: Para mandatory, el bloqueo solo ocurre cuando el instalador
    // está ready, no durante la descarga.
    //
    // Regla 4: installIncomplete y failed son casos especiales que se
    // manejan con diálogo, no con pantalla completa.

    // Fases que NUNCA bloquean la app:
    // idle, checking, current, optional, downloading, verifying, offline
    final bool shouldShowDialog;
    final bool isMandatoryBlocking;

    if (state.phase == AppUpdatePhase.ready) {
      // Solo cuando el instalador está listo mostramos algo.
      shouldShowDialog = true;
      isMandatoryBlocking = state.isMandatory;
    } else if (state.phase == AppUpdatePhase.installIncomplete) {
      shouldShowDialog = true;
      isMandatoryBlocking = true;
    } else if (state.phase == AppUpdatePhase.failed) {
      // Failed puede mostrar un diálogo no bloqueante si es mandatory
      shouldShowDialog = state.isMandatory;
      isMandatoryBlocking = state.isMandatory;
    } else {
      // checking, downloading, verifying, idle, current, optional, offline, launching
      shouldShowDialog = false;
      isMandatoryBlocking = false;
    }

    if (!shouldShowDialog) {
      return widget.child;
    }

    // Para mandatory ready (incluso si está bloqueado), mostrar overlay.
    // El overlay es necesario para que el usuario no pueda evadir la
    // actualización mandatory. Si está bloqueado, el overlay incluye
    // botones "Revisar proceso" y "Cerrar FullPOS".
    if (isMandatoryBlocking) {
      return Stack(
        children: [
          widget.child,
          _UpdateScreenOverlay(
            state: state,
            mandatory: true,
            onInstall: coordinator.launchInstaller,
            onRetry: () => coordinator.check(manual: true),
            onClose: coordinator.closeFullPos,
            onOpenFolder: coordinator.openUpdateFolder,
            onContactSupport: _contactSupport,
          ),
        ],
      );
    }

    // Optional ready sin bloqueos: el listener ya muestra el diálogo.
    return widget.child;
  }



  Future<void> _contactSupport() async {
    final phone = AppConfig.supportWhatsappNumber.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    if (phone.isEmpty) return;
    final uri = Uri.parse('${AppConfig.whatsappBaseUrl}/$phone').replace(
      queryParameters: {
        'text': 'Necesito ayuda para completar la actualización de FullPOS.',
      },
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Overlay que se muestra sobre el contenido normal de la app cuando la
/// actualización mandatory está lista. No reemplaza el contenido, solo se
/// superpone con un fondo semitransparente.
class _UpdateScreenOverlay extends StatelessWidget {
  const _UpdateScreenOverlay({
    required this.state,
    required this.mandatory,
    required this.onInstall,
    required this.onRetry,
    required this.onClose,
    required this.onOpenFolder,
    required this.onContactSupport,
  });

  final AppUpdateState state;
  final bool mandatory;
  final Future<void> Function() onInstall;
  final Future<void> Function() onRetry;
  final Future<void> Function() onClose;
  final Future<void> Function() onOpenFolder;
  final Future<void> Function() onContactSupport;

  @override
  Widget build(BuildContext context) {
    final policy = state.policy!;
    final scheme = Theme.of(context).colorScheme;
    final ready = state.phase == AppUpdatePhase.ready;
    final incomplete = state.phase == AppUpdatePhase.installIncomplete;

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xffdbe5f2)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      incomplete
                          ? Icons.error_outline_rounded
                          : Icons.system_update_alt_rounded,
                      color: scheme.primary,
                      size: 36,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      incomplete
                          ? 'La actualización no se completó'
                          : 'Actualización requerida',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xff12233f),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      incomplete
                          ? 'Ejecuta nuevamente el instalador o comunícate con soporte.'
                          : 'FullPOS necesita instalar una actualización importante para continuar funcionando correctamente. La actualización ya está lista. Puedes instalarla ahora o cerrar FullPOS.',
                    ),
                    if (!incomplete) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Esta actualización incluye mejoras de estabilidad, seguridad y compatibilidad necesarias para mantener el sistema funcionando correctamente.',
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 20,
                      runSpacing: 6,
                      children: [
                        Text('Actual: ${state.installed}'),
                        Text('Requerida: ${policy.latest}'),
                      ],
                    ),
                    if (ready) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(value: 1, minHeight: 6),
                      const SizedBox(height: 8),
                      const Text(
                        'La actualización está lista. FullPOS se cerrará, instalará la actualización automáticamente y volverá a abrirse.',
                      ),
                    ],
                    if (state.message != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        state.message!,
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (incomplete)
                          FilledButton(
                            onPressed: onRetry,
                            child: const Text('Reintentar instalación'),
                          )
                        else if (ready)
                          FilledButton(
                            onPressed: onInstall,
                            child: const Text('Instalar ahora'),
                          ),
                        if (incomplete)
                          OutlinedButton(
                            onPressed: onOpenFolder,
                            child: const Text('Abrir carpeta de actualización'),
                          ),
                        if (incomplete)
                          OutlinedButton(
                            onPressed: onContactSupport,
                            child: const Text('Contactar soporte'),
                          ),
                        TextButton(
                          onPressed: onClose,
                          child: const Text('Cerrar FullPOS'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _preparationStepLabel(UpdatePreparationStep? step) {
  return switch (step) {
    UpdatePreparationStep.verifyingOpenProcesses =>
      'Verificando procesos abiertos',
    UpdatePreparationStep.pausingBackgroundTasks =>
      'Pausando tareas en segundo plano',
    UpdatePreparationStep.waitingForIdle => 'Esperando procesos activos',
    UpdatePreparationStep.closingServices => 'Cerrando servicios',
    UpdatePreparationStep.startingInstaller => 'Iniciando instalador',
    null => 'Verificando procesos abiertos',
  };
}
