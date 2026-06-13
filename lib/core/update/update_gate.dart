import 'dart:async';

import 'package:flutter/material.dart';

import 'app_update_coordinator.dart';

class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final coordinator = AppUpdateCoordinator.instance;
  int _shownPresentationToken = 0;

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
    if (state.phase == AppUpdatePhase.optional &&
        state.presentationToken > _shownPresentationToken) {
      _shownPresentationToken = state.presentationToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showOptionalDialog());
      });
    }
    setState(() {});
  }

  Future<void> _showOptionalDialog() async {
    final state = coordinator.state;
    final policy = state.policy;
    final installed = state.installed;
    if (policy == null ||
        installed == null ||
        state.phase != AppUpdatePhase.optional) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Nueva versión disponible'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hay una nueva versión de FullPOS disponible con mejoras de estabilidad, seguridad y funcionamiento.',
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
                Navigator.of(dialogContext).pop();
                coordinator.dismissOptional();
              },
              child: const Text('Más tarde'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(coordinator.downloadAndInstall());
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('Actualizar ahora'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = coordinator.state;
    final blocks =
        state.phase == AppUpdatePhase.mandatory ||
        state.phase == AppUpdatePhase.installIncomplete ||
        state.isMandatory &&
            {
              AppUpdatePhase.downloading,
              AppUpdatePhase.verifying,
              AppUpdatePhase.ready,
              AppUpdatePhase.launching,
              AppUpdatePhase.failed,
            }.contains(state.phase);
    final optionalProgress =
        !state.isMandatory &&
        {
          AppUpdatePhase.downloading,
          AppUpdatePhase.verifying,
          AppUpdatePhase.ready,
          AppUpdatePhase.launching,
          AppUpdatePhase.failed,
        }.contains(state.phase);

    if (blocks || optionalProgress) {
      return _UpdateScreen(
        state: state,
        mandatory: blocks,
        onDownload: coordinator.downloadAndInstall,
        onInstall: coordinator.launchInstaller,
        onRetry: () => coordinator.check(manual: true),
        onCancel: optionalProgress ? coordinator.cancelOptionalDownload : null,
        onClose: coordinator.closeFullPos,
        onOpenFolder: coordinator.openUpdateFolder,
      );
    }
    return widget.child;
  }
}

class _UpdateScreen extends StatelessWidget {
  const _UpdateScreen({
    required this.state,
    required this.mandatory,
    required this.onDownload,
    required this.onInstall,
    required this.onRetry,
    required this.onCancel,
    required this.onClose,
    required this.onOpenFolder,
  });

  final AppUpdateState state;
  final bool mandatory;
  final Future<void> Function() onDownload;
  final Future<void> Function() onInstall;
  final Future<void> Function() onRetry;
  final VoidCallback? onCancel;
  final Future<void> Function() onClose;
  final Future<void> Function() onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final policy = state.policy!;
    final scheme = Theme.of(context).colorScheme;
    final isDownloading = state.phase == AppUpdatePhase.downloading;
    final isVerifying = state.phase == AppUpdatePhase.verifying;
    final isLaunching = state.phase == AppUpdatePhase.launching;
    final ready = state.phase == AppUpdatePhase.ready;
    final incomplete = state.phase == AppUpdatePhase.installIncomplete;
    final progress = state.totalBytes != null && state.totalBytes! > 0
        ? state.receivedBytes / state.totalBytes!
        : null;

    return PopScope(
      canPop: false,
      child: Material(
        color: const Color(0xfff5f8fd),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xffdbe5f2)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120b2d5c),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      incomplete
                          ? Icons.error_outline_rounded
                          : Icons.system_update_alt_rounded,
                      color: scheme.primary,
                      size: 42,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      incomplete
                          ? 'La actualización no se completó'
                          : mandatory
                          ? 'Actualización requerida'
                          : 'Actualización de FullPOS',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xff12233f),
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      incomplete
                          ? 'Ejecuta nuevamente el instalador o comunícate con soporte.'
                          : mandatory
                          ? 'Debes instalar la versión más reciente de FullPOS para continuar.'
                          : 'La actualización está lista para descargarse e instalarse.',
                    ),
                    if (mandatory && !incomplete) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Esta actualización incluye mejoras de estabilidad, seguridad y compatibilidad necesarias para mantener el sistema funcionando correctamente.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Mantener FullPOS actualizado nos permite seguir mejorando las herramientas que apoyan el crecimiento de tu negocio.',
                      ),
                    ],
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        Text('Actual: ${state.installed}'),
                        Text('Requerida: ${policy.latest}'),
                        if (policy.installerSizeBytes != null)
                          Text(
                            'Tamaño: ${_formatBytes(policy.installerSizeBytes!)}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      policy.releaseTitle,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    ...policy.releaseNotes.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('• $note'),
                      ),
                    ),
                    if (isDownloading ||
                        isVerifying ||
                        isLaunching ||
                        ready) ...[
                      const SizedBox(height: 24),
                      LinearProgressIndicator(
                        value: isDownloading
                            ? progress
                            : ready
                            ? 1
                            : null,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isDownloading
                            ? 'Descargando actualización… ${progress == null ? '' : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'}\n'
                                  '${_formatBytes(state.receivedBytes)}${state.totalBytes == null ? '' : ' de ${_formatBytes(state.totalBytes!)}'}'
                            : isVerifying
                            ? 'Verificando seguridad del archivo…'
                            : isLaunching
                            ? 'Abriendo el instalador…'
                            : 'La actualización está lista. FullPOS se cerrará y abrirá el instalador para completar el proceso.',
                      ),
                    ],
                    if (state.message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        state.message!,
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (incomplete)
                          FilledButton(
                            onPressed: onDownload,
                            child: const Text('Reintentar instalación'),
                          )
                        else if (ready)
                          FilledButton(
                            onPressed: onInstall,
                            child: const Text('Instalar ahora'),
                          )
                        else if (!isDownloading && !isVerifying && !isLaunching)
                          FilledButton(
                            onPressed: onDownload,
                            child: const Text('Descargar e instalar'),
                          ),
                        if (state.phase == AppUpdatePhase.failed)
                          OutlinedButton(
                            onPressed: onDownload,
                            child: const Text('Reintentar'),
                          ),
                        if (incomplete)
                          OutlinedButton(
                            onPressed: onOpenFolder,
                            child: const Text('Abrir carpeta de actualización'),
                          ),
                        if (onCancel != null && !isVerifying && !isLaunching)
                          TextButton(
                            onPressed: onCancel,
                            child: Text(
                              isDownloading ? 'Cancelar' : 'Más tarde',
                            ),
                          ),
                        if (mandatory)
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
