import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_update_coordinator.dart';

/// Página interna de actualizaciones de FullPOS.
///
/// Permite al usuario consultar, descargar e instalar actualizaciones
/// de forma manual y controlada, sin bloqueos automáticos.
class UpdateCenterPage extends StatefulWidget {
  const UpdateCenterPage({super.key});

  @override
  State<UpdateCenterPage> createState() => _UpdateCenterPageState();
}

class _UpdateCenterPageState extends State<UpdateCenterPage> {
  final AppUpdateCoordinator _coordinator = AppUpdateCoordinator.instance;
  bool _isChecking = false;
  bool _isDownloading = false;
  bool _isInstalling = false;

  @override
  void initState() {
    super.initState();
    _coordinator.addListener(_onCoordinatorChanged);
    final phase = _coordinator.state.phase;
    if (phase != AppUpdatePhase.downloading &&
        phase != AppUpdatePhase.verifying &&
        phase != AppUpdatePhase.ready &&
        phase != AppUpdatePhase.launching) {
      _startCheck();
    }
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onCoordinatorChanged);
    super.dispose();
  }

  void _onCoordinatorChanged() {
    if (!mounted) return;
    setState(() {
      final phase = _coordinator.state.phase;
      _isChecking = phase == AppUpdatePhase.checking;
      _isDownloading =
          phase == AppUpdatePhase.downloading ||
          phase == AppUpdatePhase.verifying;
      _isInstalling = phase == AppUpdatePhase.launching;
    });
  }

  Future<void> _startCheck() async {
    setState(() => _isChecking = true);
    try {
      await _coordinator.check(manual: true);
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _startDownload() async {
    setState(() => _isDownloading = true);
    try {
      await _coordinator.downloadAndInstall(presentWhenReady: false);
      if (!mounted) return;
      if (_coordinator.state.phase == AppUpdatePhase.ready) {
        await _confirmAndInstall();
      }
    } finally {
      if (mounted) {
        setState(() {
          final phase = _coordinator.state.phase;
          _isDownloading =
              phase == AppUpdatePhase.downloading ||
              phase == AppUpdatePhase.verifying;
        });
      }
    }
  }

  Future<void> _confirmAndInstall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Instalar actualización'),
        content: const Text(
          'FullPOS se cerrará para completar la instalación. '
          'Guarda cualquier venta o proceso pendiente antes de continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.install_desktop_rounded),
            label: const Text('Instalar ahora'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isInstalling = true);
      unawaited(_coordinator.launchInstaller());
    }
  }

  // ──────────────────────────────────────────────
  // Helpers de estado
  // ──────────────────────────────────────────────

  String _stateLabel() {
    switch (_coordinator.state.phase) {
      case AppUpdatePhase.idle:
      case AppUpdatePhase.checking:
        return 'Buscando actualizaciones…';
      case AppUpdatePhase.current:
        return 'Actualizado';
      case AppUpdatePhase.optional:
      case AppUpdatePhase.mandatory:
        return 'Nueva versión disponible';
      case AppUpdatePhase.downloading:
        return 'Descargando…';
      case AppUpdatePhase.verifying:
        return 'Verificando…';
      case AppUpdatePhase.ready:
        return 'Listo para instalar';
      case AppUpdatePhase.launching:
        return 'Instalando…';
      case AppUpdatePhase.offline:
        return 'Sin conexión';
      case AppUpdatePhase.failed:
        return 'Error';
      case AppUpdatePhase.installIncomplete:
        return 'Instalación incompleta';
    }
  }

  Color _stateColor() {
    switch (_coordinator.state.phase) {
      case AppUpdatePhase.current:
        return const Color(0xFF15803D);
      case AppUpdatePhase.optional:
      case AppUpdatePhase.mandatory:
        return const Color(0xFF2563EB);
      case AppUpdatePhase.ready:
        return const Color(0xFF15803D);
      case AppUpdatePhase.offline:
      case AppUpdatePhase.failed:
      case AppUpdatePhase.installIncomplete:
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _stateIcon() {
    switch (_coordinator.state.phase) {
      case AppUpdatePhase.current:
        return Icons.check_circle_outline_rounded;
      case AppUpdatePhase.optional:
      case AppUpdatePhase.mandatory:
        return Icons.system_update_alt_rounded;
      case AppUpdatePhase.ready:
        return Icons.download_done_rounded;
      case AppUpdatePhase.offline:
        return Icons.cloud_off_rounded;
      case AppUpdatePhase.failed:
      case AppUpdatePhase.installIncomplete:
        return Icons.error_outline_rounded;
      default:
        return Icons.hourglass_empty_rounded;
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

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  // ──────────────────────────────────────────────
  // Constantes de diseño
  // ──────────────────────────────────────────────

  static const Color _bgColor = Color(0xFFF2F6F9);
  static const Color _cardBorder = Color(0xFFE7EEF5);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _red = Color(0xFFB91C1C);
  static const Color _amber = Color(0xFFB45309);
  static const double _cardRadius = 14;
  static const double _maxContentWidth = 920;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final state = _coordinator.state;
    final installed = state.installed;
    final policy = state.policy;
    final phase = state.phase;

    final hasUpdate =
        phase == AppUpdatePhase.optional ||
        phase == AppUpdatePhase.mandatory ||
        phase == AppUpdatePhase.ready ||
        phase == AppUpdatePhase.downloading ||
        phase == AppUpdatePhase.verifying ||
        phase == AppUpdatePhase.failed ||
        phase == AppUpdatePhase.installIncomplete;

    final isUpdateAvailable =
        phase == AppUpdatePhase.optional || phase == AppUpdatePhase.mandatory;

    final isReady = phase == AppUpdatePhase.ready;
    final isError =
        phase == AppUpdatePhase.failed ||
        phase == AppUpdatePhase.installIncomplete;
    final isOffline = phase == AppUpdatePhase.offline;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final router = GoRouter.of(context);
            if (router.canPop()) {
              router.pop();
            } else {
              context.go('/sales');
            }
          },
        ),
        title: const Text(
          'Actualizaciones',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: _textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _cardBorder),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Encabezado ──
                Text(
                  'Updates',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: _textPrimary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mantén FullPOS actualizado con las últimas mejoras y correcciones.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: _textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Versión instalada ──
                _buildCompactCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _sectionIcon(
                            Icons.info_outline_rounded,
                            bgColor: const Color(0xFFEFF6FF),
                            iconColor: _blue,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Versión instalada',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _textPrimary,
                            ),
                          ),
                          const Spacer(),
                          _statusBadge(
                            label: _stateLabel(),
                            icon: _stateIcon(),
                            color: _stateColor(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _infoRow(
                        label: 'Versión',
                        value: installed?.semantic ?? 'Cargando…',
                      ),
                      if (installed != null) ...[
                        const SizedBox(height: 5),
                        _infoRow(
                          label: 'Build',
                          value: installed.build.toString(),
                        ),
                      ],
                      const SizedBox(height: 5),
                      _infoRow(label: 'Plataforma', value: 'Windows'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Nueva versión disponible ──
                if (hasUpdate && policy != null) ...[
                  _buildCompactCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _sectionIcon(
                              policy.mandatory
                                  ? Icons.warning_amber_rounded
                                  : Icons.system_update_alt_rounded,
                              bgColor: policy.mandatory
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFEFF6FF),
                              iconColor: policy.mandatory ? _red : _blue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nueva versión disponible',
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: _textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    policy.mandatory
                                        ? 'Actualización importante'
                                        : 'Actualización recomendada',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: policy.mandatory ? _red : _blue,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _infoRow(
                          label: 'Nueva versión',
                          value: policy.latest.semantic,
                        ),
                        const SizedBox(height: 5),
                        _infoRow(
                          label: 'Build',
                          value: policy.latest.build.toString(),
                        ),
                        if (policy.installerSizeBytes != null) ...[
                          const SizedBox(height: 5),
                          _infoRow(
                            label: 'Tamaño',
                            value: _formatBytes(policy.installerSizeBytes!),
                          ),
                        ],
                        const SizedBox(height: 5),
                        _infoRow(
                          label: 'Publicado',
                          value: _formatDate(policy.publishedAt),
                        ),
                        if (policy.releaseTitle.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: _cardBorder),
                          const SizedBox(height: 12),
                          Text(
                            policy.releaseTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                        if (policy.releaseNotes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final note in policy.releaseNotes)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '• ',
                                    style: TextStyle(color: _textSecondary),
                                  ),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF475569),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Progreso de descarga ──
                if (phase == AppUpdatePhase.downloading) ...[
                  _buildCompactCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _blue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Descargando actualización…',
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (state.totalBytes != null && state.totalBytes! > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value:
                                      (state.receivedBytes / state.totalBytes!)
                                          .clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE7EEF5),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        _blue,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_formatBytes(state.receivedBytes)} de ${_formatBytes(state.totalBytes!)}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          )
                        else
                          const LinearProgressIndicator(
                            minHeight: 6,
                            backgroundColor: Color(0xFFE7EEF5),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Verificando ──
                if (phase == AppUpdatePhase.verifying)
                  _buildCompactCard(
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(_blue),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Verificando archivo descargado…',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (phase == AppUpdatePhase.verifying)
                  const SizedBox(height: 14),

                // ── Error ──
                if (isError && state.message != null) ...[
                  _buildCompactCard(
                    color: const Color(0xFFFEF2F2),
                    borderColor: const Color(0xFFFECACA),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: _red,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                state.message!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF7F1D1D),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (state.supportDetails != null &&
                            state.supportDetails!.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1, color: Color(0xFFFECACA)),
                          const SizedBox(height: 10),
                          SelectableText(
                            state.supportDetails!,
                            style: textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF7F1D1D),
                              height: 1.35,
                              fontFamily: 'RobotoMono',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Sin conexión ──
                if (isOffline) ...[
                  _buildCompactCard(
                    color: const Color(0xFFFFFBEB),
                    borderColor: const Color(0xFFFDE68A),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 18,
                          color: _amber,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No se pudo verificar si hay actualizaciones. '
                            'Revisa tu conexión a internet y vuelve a intentarlo.',
                            style: textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF78350F),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Acciones ──
                _buildActions(
                  phase,
                  isUpdateAvailable,
                  isReady,
                  isError,
                  isOffline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Acciones
  // ──────────────────────────────────────────────

  Widget _buildActions(
    AppUpdatePhase phase,
    bool isUpdateAvailable,
    bool isReady,
    bool isError,
    bool isOffline,
  ) {
    // No update available or checking
    if (phase == AppUpdatePhase.current || phase == AppUpdatePhase.idle) {
      return _actionButton(
        onPressed: _isChecking ? null : _startCheck,
        isLoading: _isChecking,
        loadingLabel: 'Verificando…',
        icon: Icons.refresh_rounded,
        label: 'Buscar actualizaciones',
      );
    }

    // Update available but not downloaded
    if (isUpdateAvailable) {
      return _actionButton(
        onPressed: _isDownloading ? null : _startDownload,
        isLoading: _isDownloading,
        loadingLabel: 'Descargando…',
        icon: Icons.install_desktop_rounded,
        label: 'Instalar actualización',
      );
    }

    // Ready to install
    if (isReady) {
      return _actionButton(
        onPressed: _isInstalling ? null : _confirmAndInstall,
        isLoading: _isInstalling,
        loadingLabel: 'Instalando…',
        icon: Icons.install_desktop_rounded,
        label: 'Instalar ahora',
      );
    }

    // Error or offline - retry
    if (isError || isOffline) {
      return _actionButton(
        onPressed: _isChecking ? null : _startCheck,
        isLoading: _isChecking,
        loadingLabel: 'Verificando…',
        icon: Icons.refresh_rounded,
        label: 'Intentar de nuevo',
      );
    }

    // Downloading or verifying - show cancel if optional
    if (phase == AppUpdatePhase.downloading ||
        phase == AppUpdatePhase.verifying) {
      return SizedBox(
        width: 260,
        child: OutlinedButton.icon(
          onPressed: () => _coordinator.cancelOptionalDownload(),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Cancelar descarga'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _textSecondary,
            side: const BorderSide(color: Color(0xFFD9E3F0)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _actionButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required String loadingLabel,
    required IconData icon,
    required String label,
  }) {
    return SizedBox(
      width: 260,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(isLoading ? loadingLabel : label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Componentes reutilizables
  // ──────────────────────────────────────────────

  Widget _buildCompactCard({
    required Widget child,
    Color color = Colors.white,
    Color borderColor = _cardBorder,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: borderColor, width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionIcon(
    IconData icon, {
    required Color bgColor,
    required Color iconColor,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: iconColor.withOpacity(0.18), width: 0.9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: iconColor),
    );
  }

  Widget _statusBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.20), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: _textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              color: _textPrimary,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
