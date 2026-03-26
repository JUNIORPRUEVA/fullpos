import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../settings/providers/theme_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_session_model.dart';
import '../data/cash_summary_model.dart';
import '../data/cash_repository.dart';
import 'cash_close_dialog.dart';

/// Panel lateral de caja con resumen y opciones
class CashPanelSheet extends ConsumerStatefulWidget {
  final int sessionId;

  const CashPanelSheet({super.key, required this.sessionId});

  static Future<void> show(BuildContext context, {required int sessionId}) {
    return showDialog(
      context: context,
      builder: (context) => CashPanelSheet(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<CashPanelSheet> createState() => _CashPanelSheetState();
}

class _CashPanelSheetState extends ConsumerState<CashPanelSheet> {
  ColorScheme get scheme => Theme.of(context).colorScheme;
  AppStatusTheme get status =>
      Theme.of(context).extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: scheme.tertiary,
        warning: scheme.tertiary,
        error: scheme.error,
        info: scheme.primary,
      );
  Color readableOn(Color bg) => ColorUtils.readableTextColor(bg);

  bool _loadingSummary = true;
  bool _loadingMovements = true;
  bool _loadingSession = true;
  bool _loadingPermissions = true;
  CashSummaryModel? _summary;
  List<CashMovementModel> _movements = [];
  CashSessionModel? _session;
  bool _canCloseShift = false;

  late final DateFormat _openedAtFormat = DateFormat('dd/MM HH:mm');
  late final NumberFormat _moneyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );

  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Mantener el tiempo del turno “vivo” sin recargar data.
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadSession(),
      _loadSummary(),
      _loadMovements(),
      _loadPermissions(),
    ]);
  }

  Future<void> _loadPermissions() async {
    try {
      final perms = await AuthRepository.getCurrentPermissions();
      if (!mounted) return;
      setState(() {
        _canCloseShift = perms.canCloseShift || perms.canCloseCash;
        _loadingPermissions = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _canCloseShift = false;
          _loadingPermissions = false;
        });
      }
    }
  }

  Future<void> _loadSession() async {
    try {
      final session = await CashRepository.getSessionById(widget.sessionId);
      if (mounted) {
        setState(() {
          _session = session;
          _loadingSession = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSession = false);
    }
  }

  String _formatDuration(Duration d) {
    final totalMinutes = d.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await CashRepository.buildSummary(
        sessionId: widget.sessionId,
      );
      if (mounted) {
        setState(() {
          _summary = summary;
          _loadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _loadMovements() async {
    try {
      final movements = await CashRepository.listMovements(
        sessionId: widget.sessionId,
      );
      if (mounted) {
        setState(() {
          _movements = movements;
          _loadingMovements = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMovements = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(themeProvider);
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final safeWidth = (screenSize.width - 28).clamp(320.0, 1000.0);
    final desiredSide = (screenSize.width * 0.35).clamp(320.0, safeWidth);
    final dialogWidth = math.min(desiredSide, safeWidth);
    final availableHeight = screenSize.height - viewInsets.vertical - 28;
    final isCompact = dialogWidth < 560 || availableHeight < 590;
    final isUltraCompact = dialogWidth < 470 || availableHeight < 540;
    final sidebarColor = settings.sidebarColor;
    final sidebarAccent = settings.sidebarActiveColor;
    final sidebarText = ColorUtils.ensureReadableColor(
      settings.sidebarTextColor,
      sidebarColor,
    );

    final session = _session;
    final openedAt = session?.openedAt;
    final duration = openedAt == null
        ? null
        : DateTime.now().difference(openedAt);
    final durationText = duration == null ? null : _formatDuration(duration);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: (screenSize.width * 0.035).clamp(12.0, 52.0),
        vertical: (screenSize.height * 0.04).clamp(12.0, 42.0),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth, minWidth: 320),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isCompact ? 22 : 28),
            border: Border.all(
              color: sidebarAccent.withOpacity(0.34),
              width: 1.3,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  sidebarColor.withOpacity(0.22),
                  scheme.surface,
                ),
                Color.alphaBlend(
                  sidebarAccent.withOpacity(0.10),
                  scheme.surface,
                ),
                scheme.surface,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: sidebarColor.withOpacity(0.18),
                blurRadius: 38,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(
                theme: theme,
                session: session,
                durationText: durationText,
                isCompact: isCompact,
                isUltraCompact: isUltraCompact,
                sidebarAccent: sidebarAccent,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isUltraCompact ? 12 : (isCompact ? 14 : 18),
                  0,
                  isUltraCompact ? 12 : (isCompact ? 14 : 18),
                  isUltraCompact ? 10 : (isCompact ? 12 : 14),
                ),
                child: _buildActionBanner(
                  theme: theme,
                  isCompact: isCompact,
                  isUltraCompact: isUltraCompact,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isUltraCompact ? 12 : (isCompact ? 14 : 18),
                  0,
                  isUltraCompact ? 12 : (isCompact ? 14 : 18),
                  isUltraCompact ? 12 : (isCompact ? 14 : 16),
                ),
                child: _buildDashboard(
                  theme: theme,
                  isCompact: isCompact,
                  isUltraCompact: isUltraCompact,
                  sidebarColor: sidebarColor,
                  sidebarAccent: sidebarAccent,
                  sidebarText: sidebarText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required ThemeData theme,
    required CashSessionModel? session,
    required String? durationText,
    required bool isCompact,
    required bool isUltraCompact,
    required Color sidebarAccent,
  }) {
    final badgeColor = Color.alphaBlend(
      scheme.primary.withOpacity(0.16),
      scheme.surfaceContainerHighest,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        isUltraCompact ? 12 : (isCompact ? 14 : 18),
        isUltraCompact ? 12 : (isCompact ? 14 : 16),
        isUltraCompact ? 8 : (isCompact ? 10 : 12),
        isUltraCompact ? 10 : (isCompact ? 12 : 14),
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withOpacity(0.32)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isUltraCompact ? 36 : (isCompact ? 40 : 46),
            height: isUltraCompact ? 36 : (isCompact ? 40 : 46),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(isUltraCompact ? 12 : 14),
              border: Border.all(color: scheme.primary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: sidebarAccent,
              size: isUltraCompact ? 18 : (isCompact ? 20 : 22),
            ),
          ),
          SizedBox(width: isUltraCompact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CORTE DE TURNO',
                  style:
                      (isUltraCompact
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                            letterSpacing: 0.25,
                          ),
                ),
                SizedBox(height: isUltraCompact ? 2 : 3),
                SizedBox(height: isUltraCompact ? 6 : 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildInfoChip(
                      icon: Icons.person_outline,
                      label: _loadingSession
                          ? 'Cargando turno'
                          : (session == null
                                ? 'Sin sesión activa'
                                : session.userName),
                    ),
                    if (session != null && durationText != null)
                      _buildInfoChip(
                        icon: Icons.schedule,
                        label: '$durationText activos',
                      ),
                    if (session != null)
                      _buildInfoChip(
                        icon: Icons.event_available,
                        label: _openedAtFormat.format(session.openedAt),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: scheme.onSurface.withOpacity(0.65)),
            iconSize: isUltraCompact ? 18 : 20,
            splashRadius: 18,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withOpacity(0.06),
          scheme.surfaceContainerHighest,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withOpacity(0.78),
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBanner({
    required ThemeData theme,
    required bool isCompact,
    required bool isUltraCompact,
  }) {
    final enabled =
        !_loadingPermissions && (_session?.isOpen == true) && _canCloseShift;
    final accent = enabled ? scheme.primary : scheme.outline;
    final actionColor = enabled ? status.error : scheme.outline;

    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 10 : (isCompact ? 12 : 14)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withOpacity(0.12), scheme.surface),
            Color.alphaBlend(actionColor.withOpacity(0.08), scheme.surface),
          ],
        ),
        borderRadius: BorderRadius.circular(isUltraCompact ? 16 : 18),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildActionBannerCopy(theme, isUltraCompact)),
          const SizedBox(width: 10),
          SizedBox(
            width: isUltraCompact ? 138 : 156,
            child: _buildActionButton(
              enabled: enabled,
              actionColor: actionColor,
              isUltraCompact: isUltraCompact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBannerCopy(ThemeData theme, bool isUltraCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Aquí haces el corte',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: isUltraCompact ? 11.5 : 12.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Todo visible en una sola vista.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withOpacity(0.72),
            height: 1.1,
            fontWeight: FontWeight.w500,
            fontSize: isUltraCompact ? 9.8 : 10.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required bool enabled,
    required Color actionColor,
    required bool isUltraCompact,
  }) {
    final foreground = readableOn(actionColor);

    return ElevatedButton.icon(
      onPressed: enabled ? _showCloseDialog : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? actionColor : scheme.surfaceContainerHighest,
        foregroundColor: enabled
            ? foreground
            : scheme.onSurface.withOpacity(0.42),
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: isUltraCompact ? 10 : 12,
          vertical: isUltraCompact ? 10 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(
        enabled ? Icons.receipt_long_rounded : Icons.lock_outline,
        size: isUltraCompact ? 16 : 18,
      ),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hacer corte',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: isUltraCompact ? 11.4 : 12.4,
            ),
          ),
          Text(
            enabled ? 'Cerrar e imprimir' : 'Sin acceso',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: isUltraCompact ? 9.2 : 9.8,
              color: enabled
                  ? foreground.withOpacity(0.78)
                  : scheme.onSurface.withOpacity(0.42),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard({
    required ThemeData theme,
    required bool isCompact,
    required bool isUltraCompact,
    required Color sidebarColor,
    required Color sidebarAccent,
    required Color sidebarText,
  }) {
    if (_loadingSummary && _loadingMovements && _loadingSession) {
      return Center(child: CircularProgressIndicator(color: scheme.primary));
    }

    if (_summary == null) {
      return Center(
        child: Text(
          'No se pudo cargar el resumen del corte.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withOpacity(0.65),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = isUltraCompact ? 8.0 : (isCompact ? 10.0 : 12.0);

        final hero = _buildSummaryHero(
          theme: theme,
          isCompact: isCompact,
          isUltraCompact: isUltraCompact,
          sidebarColor: sidebarColor,
          sidebarAccent: sidebarAccent,
          sidebarText: sidebarText,
        );
        final detailsButton = _buildDetailsButton(
          theme: theme,
          isUltraCompact: isUltraCompact,
          sidebarAccent: sidebarAccent,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            SizedBox(height: gap),
            Align(alignment: Alignment.topRight, child: detailsButton),
          ],
        );
      },
    );
  }

  Widget _buildDetailsButton({
    required ThemeData theme,
    required bool isUltraCompact,
    required Color sidebarAccent,
  }) {
    return OutlinedButton.icon(
      onPressed: _showDetailsDialog,
      style: OutlinedButton.styleFrom(
        foregroundColor: sidebarAccent,
        side: BorderSide(color: sidebarAccent.withOpacity(0.28)),
        backgroundColor: Color.alphaBlend(
          sidebarAccent.withOpacity(0.06),
          scheme.surface,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isUltraCompact ? 10 : 12,
          vertical: isUltraCompact ? 8 : 9,
        ),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(Icons.visibility_outlined, size: isUltraCompact ? 14 : 16),
      label: Text(
        'Ver desglose',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: isUltraCompact ? 10.2 : 10.8,
        ),
      ),
    );
  }

  Future<void> _showDetailsDialog() async {
    if (_summary == null) return;

    final theme = Theme.of(context);
    final settings = ref.read(themeProvider);
    final scheme = theme.colorScheme;
    final sidebarAccent = settings.sidebarActiveColor;
    final sidebarColor = settings.sidebarColor;
    final sidebarText = ColorUtils.ensureReadableColor(
      settings.sidebarTextColor,
      sidebarColor,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;
        final width = (screenSize.width * 0.36).clamp(340.0, 560.0);
        final height = (screenSize.height * 0.64).clamp(420.0, 760.0);
        final isCompactDialog = width < 430;

        return DefaultTabController(
          length: 2,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width,
                maxHeight: height,
                minWidth: 340,
                minHeight: 420,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: sidebarAccent.withOpacity(0.3)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        sidebarColor.withOpacity(0.2),
                        scheme.surface,
                      ),
                      Color.alphaBlend(
                        sidebarAccent.withOpacity(0.06),
                        scheme.surface,
                      ),
                      scheme.surface,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.all(isCompactDialog ? 16 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailsDialogHeader(
                        theme: theme,
                        sidebarAccent: sidebarAccent,
                        sidebarColor: sidebarColor,
                        sidebarText: sidebarText,
                        isCompactDialog: isCompactDialog,
                        onClose: () => Navigator.pop(dialogContext),
                      ),
                      SizedBox(height: isCompactDialog ? 12 : 14),
                      _buildDetailsDialogTabBar(
                        theme: theme,
                        sidebarAccent: sidebarAccent,
                        isCompactDialog: isCompactDialog,
                      ),
                      SizedBox(height: isCompactDialog ? 12 : 14),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildBreakdownDetailsTab(
                              theme: theme,
                              isCompactDialog: isCompactDialog,
                              sidebarAccent: sidebarAccent,
                            ),
                            _buildMovementDetailsTab(
                              theme: theme,
                              isCompactDialog: isCompactDialog,
                              sidebarAccent: sidebarAccent,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailsDialogHeader({
    required ThemeData theme,
    required Color sidebarAccent,
    required Color sidebarColor,
    required Color sidebarText,
    required bool isCompactDialog,
    required VoidCallback onClose,
  }) {
    final summary = _summary!;

    return Container(
      padding: EdgeInsets.all(isCompactDialog ? 14 : 16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          sidebarColor.withOpacity(0.12),
          scheme.surfaceContainerHighest,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sidebarAccent.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isCompactDialog ? 40 : 44,
                height: isCompactDialog ? 40 : 44,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    sidebarAccent.withOpacity(0.14),
                    scheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.analytics_rounded,
                  color: sidebarAccent,
                  size: isCompactDialog ? 20 : 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detalle del turno',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: isCompactDialog ? 15.2 : 16.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Consulta ventas, movimientos y cifras del corte.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withOpacity(0.66),
                        fontWeight: FontWeight.w600,
                        fontSize: isCompactDialog ? 10.2 : 10.8,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: Icon(
                  Icons.close,
                  color: scheme.onSurface.withOpacity(0.64),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          SizedBox(height: isCompactDialog ? 12 : 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDetailsMetricChip(
                label: 'Esperado',
                value: _moneyFormat.format(summary.expectedCash),
                accent: sidebarAccent,
                textColor: sidebarText,
                icon: Icons.account_balance_wallet_rounded,
              ),
              _buildDetailsMetricChip(
                label: 'Ventas',
                value: _moneyFormat.format(summary.totalSales),
                accent: status.success,
                textColor: scheme.onSurface,
                icon: Icons.trending_up_rounded,
              ),
              _buildDetailsMetricChip(
                label: 'Tickets',
                value: '${summary.totalTickets}',
                accent: scheme.secondary,
                textColor: scheme.onSurface,
                icon: Icons.receipt_long_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsMetricChip({
    required String label,
    required String value,
    required Color accent,
    required Color textColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), scheme.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.58),
                  fontWeight: FontWeight.w700,
                  fontSize: 9.6,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsDialogTabBar({
    required ThemeData theme,
    required Color sidebarAccent,
    required bool isCompactDialog,
  }) {
    return Container(
      height: isCompactDialog ? 42 : 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.32)),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: Color.alphaBlend(
            sidebarAccent.withOpacity(0.16),
            scheme.surface,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: sidebarAccent,
        unselectedLabelColor: scheme.onSurface.withOpacity(0.62),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: isCompactDialog ? 11.2 : 11.8,
        ),
        unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: isCompactDialog ? 11.2 : 11.8,
        ),
        tabs: const [
          Tab(text: 'Ventas'),
          Tab(text: 'Movimientos'),
        ],
      ),
    );
  }

  Widget _buildBreakdownDetailsTab({
    required ThemeData theme,
    required bool isCompactDialog,
    required Color sidebarAccent,
  }) {
    final summary = _summary!;
    final items = <({IconData icon, String label, double amount, Color color})>[
      (
        icon: Icons.payments_rounded,
        label: 'Ventas efectivo',
        amount: summary.salesCashTotal,
        color: status.success,
      ),
      (
        icon: Icons.credit_card_rounded,
        label: 'Ventas tarjeta',
        amount: summary.salesCardTotal,
        color: sidebarAccent,
      ),
      (
        icon: Icons.swap_horiz_rounded,
        label: 'Transferencias',
        amount: summary.salesTransferTotal,
        color: scheme.secondary,
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: 'Créditos',
        amount: summary.salesCreditTotal,
        color: status.warning,
      ),
      (
        icon: Icons.add_circle_rounded,
        label: 'Entradas manuales',
        amount: summary.cashInManual,
        color: status.success,
      ),
      (
        icon: Icons.remove_circle_rounded,
        label: 'Retiros manuales',
        amount: summary.cashOutManual,
        color: status.error,
      ),
      if (summary.refundsCash > 0)
        (
          icon: Icons.undo_rounded,
          label: 'Devoluciones',
          amount: summary.refundsCash,
          color: status.error,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.36)),
      ),
      child: ListView(
        padding: EdgeInsets.all(isCompactDialog ? 12 : 14),
        children: [
          Text(
            'Composición del corte',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cada cifra que participa en el total esperado del turno.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withOpacity(0.64),
              fontWeight: FontWeight.w600,
              fontSize: isCompactDialog ? 10.0 : 10.4,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < items.length; index++) ...[
            _buildBreakdownTile(
              icon: items[index].icon,
              label: items[index].label,
              amount: items[index].amount,
              color: items[index].color,
              isUltraCompact: false,
            ),
            if (index != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildMovementDetailsTab({
    required ThemeData theme,
    required bool isCompactDialog,
    required Color sidebarAccent,
  }) {
    final dateFormat = DateFormat('dd/MM HH:mm');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.36)),
      ),
      child: _loadingMovements
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : _movements.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          sidebarAccent.withOpacity(0.12),
                          scheme.surface,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.inbox_outlined,
                        color: sidebarAccent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No hay movimientos manuales',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cuando se registren entradas o retiros, aparecerán aquí.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withOpacity(0.62),
                        fontWeight: FontWeight.w600,
                        fontSize: isCompactDialog ? 10.0 : 10.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.all(isCompactDialog ? 12 : 14),
              itemCount: _movements.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Historial de movimientos',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_movements.length} registros dentro del turno actual.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withOpacity(0.64),
                          fontWeight: FontWeight.w600,
                          fontSize: isCompactDialog ? 10.0 : 10.4,
                        ),
                      ),
                    ],
                  );
                }

                final movement = _movements[index - 1];
                return _buildMovementTile(
                  movement: movement,
                  timeLabel: dateFormat.format(movement.createdAt),
                  isUltraCompact: false,
                );
              },
            ),
    );
  }

  Widget _buildSummaryHero({
    required ThemeData theme,
    required bool isCompact,
    required bool isUltraCompact,
    required Color sidebarColor,
    required Color sidebarAccent,
    required Color sidebarText,
  }) {
    final summary = _summary!;

    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 12 : (isCompact ? 14 : 16)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(sidebarColor.withOpacity(0.18), scheme.surface),
            Color.alphaBlend(sidebarAccent.withOpacity(0.08), scheme.surface),
            scheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(isUltraCompact ? 16 : 18),
        border: Border.all(color: sidebarAccent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'EFECTIVO ESPERADO',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.74),
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  fontSize: isUltraCompact ? 10.4 : 11,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _loadData,
                style: FilledButton.styleFrom(
                  backgroundColor: Color.alphaBlend(
                    sidebarColor.withOpacity(0.18),
                    scheme.surface,
                  ),
                  foregroundColor: sidebarText,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                icon: Icon(
                  Icons.refresh_rounded,
                  size: isUltraCompact ? 14 : 16,
                ),
                label: Text(
                  'Actualizar',
                  style: TextStyle(fontSize: isUltraCompact ? 10 : 10.8),
                ),
              ),
            ],
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _moneyFormat.format(summary.expectedCash),
                style:
                    (isUltraCompact
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineLarge)
                        ?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: isUltraCompact ? 24 : (isCompact ? 28 : 30),
                        ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    scheme.primary.withOpacity(0.12),
                    scheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: sidebarAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Listo para corte',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: sidebarAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: isUltraCompact ? 10 : 10.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          Row(
            children: [
              Expanded(
                child: _buildMiniStatCard(
                  label: 'Apertura',
                  value: _moneyFormat.format(summary.openingAmount),
                  color: scheme.primary,
                  icon: Icons.play_circle_outline_rounded,
                  isUltraCompact: isUltraCompact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStatCard(
                  label: 'Tickets',
                  value: '${summary.totalTickets}',
                  color: scheme.secondary,
                  icon: Icons.receipt_long_rounded,
                  isUltraCompact: isUltraCompact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStatCard(
                  label: 'Ventas',
                  value: _moneyFormat.format(summary.totalSales),
                  color: status.success,
                  icon: Icons.trending_up_rounded,
                  isUltraCompact: isUltraCompact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required bool isUltraCompact,
  }) {
    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 8 : 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.08), scheme.surface),
        borderRadius: BorderRadius.circular(isUltraCompact ? 12 : 14),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: isUltraCompact ? 14 : 16, color: color),
          SizedBox(height: isUltraCompact ? 4 : 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: isUltraCompact ? 12.2 : 13.4,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withOpacity(0.62),
              fontWeight: FontWeight.w600,
              fontSize: isUltraCompact ? 9.4 : 10,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSalesBreakdown({
    required ThemeData theme,
    required bool compact,
    required bool isUltraCompact,
    required Color sidebarAccent,
  }) {
    final summary = _summary!;
    final items = <({IconData icon, String label, double amount, Color color})>[
      (
        icon: Icons.payments_rounded,
        label: 'Ventas efectivo',
        amount: summary.salesCashTotal,
        color: status.success,
      ),
      (
        icon: Icons.credit_card_rounded,
        label: 'Ventas tarjeta',
        amount: summary.salesCardTotal,
        color: sidebarAccent,
      ),
      (
        icon: Icons.swap_horiz_rounded,
        label: 'Transferencias',
        amount: summary.salesTransferTotal,
        color: scheme.secondary,
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: 'Créditos',
        amount: summary.salesCreditTotal,
        color: status.warning,
      ),
      (
        icon: Icons.add_circle_rounded,
        label: 'Entradas manuales',
        amount: summary.cashInManual,
        color: status.success,
      ),
      (
        icon: Icons.remove_circle_rounded,
        label: 'Retiros manuales',
        amount: summary.cashOutManual,
        color: status.error,
      ),
      if (summary.refundsCash > 0)
        (
          icon: Icons.undo_rounded,
          label: 'Devoluciones',
          amount: summary.refundsCash,
          color: status.error,
        ),
    ];

    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 10 : (compact ? 12 : 14)),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(isUltraCompact ? 16 : 18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DESGLOSE DEL TURNO',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withOpacity(0.72),
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w900,
                    fontSize: isUltraCompact ? 10.8 : 11.4,
                  ),
                ),
              ),
              Text(
                '${items.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.52),
                  fontWeight: FontWeight.w700,
                  fontSize: isUltraCompact ? 10 : 10.4,
                ),
              ),
            ],
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (
                              var index = 0;
                              index < items.length;
                              index++
                            ) ...[
                              _buildBreakdownTile(
                                icon: items[index].icon,
                                label: items[index].label,
                                amount: items[index].amount,
                                color: items[index].color,
                                isUltraCompact: isUltraCompact,
                              ),
                              if (index != items.length - 1)
                                SizedBox(height: isUltraCompact ? 6 : 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownTile({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
    required bool isUltraCompact,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isUltraCompact ? 8 : 10,
        vertical: isUltraCompact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.08), scheme.surface),
        borderRadius: BorderRadius.circular(isUltraCompact ? 12 : 14),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: isUltraCompact ? 24 : 28,
            height: isUltraCompact ? 24 : 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: isUltraCompact ? 13 : 15),
          ),
          SizedBox(width: isUltraCompact ? 8 : 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: isUltraCompact ? 10.2 : 10.8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _moneyFormat.format(amount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: isUltraCompact ? 10.4 : 11.2,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMovementsCard({
    required ThemeData theme,
    required bool compact,
    required bool isUltraCompact,
    required Color sidebarText,
    required Color sidebarAccent,
  }) {
    final recentMovements = _movements.take(isUltraCompact ? 2 : 3).toList();
    final dateFormat = DateFormat('HH:mm');

    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 10 : (compact ? 12 : 14)),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(isUltraCompact ? 16 : 18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MOVIMIENTOS RECIENTES',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withOpacity(0.72),
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w900,
                    fontSize: isUltraCompact ? 10.8 : 11.4,
                  ),
                ),
              ),
              if (!_loadingMovements)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      scheme.primary.withOpacity(0.08),
                      scheme.surface,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_movements.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: sidebarAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: isUltraCompact ? 10 : 10.4,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_loadingMovements) {
                  return Center(
                    child: CircularProgressIndicator(color: scheme.primary),
                  );
                }

                final content = recentMovements.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              color: scheme.onSurface.withOpacity(0.4),
                              size: isUltraCompact ? 28 : 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sin movimientos manuales.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface.withOpacity(0.6),
                                fontSize: isUltraCompact ? 10 : 10.4,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var index = 0;
                            index < recentMovements.length;
                            index++
                          ) ...[
                            _buildMovementTile(
                              movement: recentMovements[index],
                              timeLabel: dateFormat.format(
                                recentMovements[index].createdAt,
                              ),
                              isUltraCompact: isUltraCompact,
                            ),
                            if (index != recentMovements.length - 1)
                              SizedBox(height: isUltraCompact ? 6 : 8),
                          ],
                          if (_movements.length > recentMovements.length)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${recentMovements.length} de ${_movements.length} visibles',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface.withOpacity(0.52),
                                    fontWeight: FontWeight.w700,
                                    fontSize: isUltraCompact ? 9.8 : 10.2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );

                return ClipRect(
                  child: Align(
                    alignment: recentMovements.isEmpty
                        ? Alignment.center
                        : Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: recentMovements.isEmpty
                          ? Alignment.center
                          : Alignment.topCenter,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: content,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementTile({
    required CashMovementModel movement,
    required String timeLabel,
    required bool isUltraCompact,
  }) {
    final isIncome = movement.isIn;
    final movementColor = isIncome ? status.success : status.error;

    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 8 : 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          movementColor.withOpacity(0.08),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(isUltraCompact ? 12 : 14),
        border: Border.all(color: movementColor.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: isUltraCompact ? 24 : 28,
            height: isUltraCompact ? 24 : 28,
            decoration: BoxDecoration(
              color: movementColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: movementColor,
              size: isUltraCompact ? 13 : 15,
            ),
          ),
          SizedBox(width: isUltraCompact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: isUltraCompact ? 10.1 : 10.6,
                  ),
                ),
                Text(
                  timeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.58),
                    fontWeight: FontWeight.w600,
                    fontSize: isUltraCompact ? 9.2 : 9.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${isIncome ? '+' : '-'}${_moneyFormat.format(movement.amount)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: movementColor,
              fontWeight: FontWeight.w900,
              fontSize: isUltraCompact ? 10 : 10.6,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCloseDialog() async {
    if (_session?.isOpen != true) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('La sesión ya está cerrada.')),
      );
      return;
    }

    if (!_canCloseShift) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para cerrar la sesión.'),
        ),
      );
      return;
    }

    final result = await CashCloseDialog.show(
      context,
      sessionId: widget.sessionId,
      logoutAfterClose: false,
      initialSummary: _summary,
      initialSession: _session,
      initialMovements: _movements,
    );

    if (result == true && mounted) {
      await _loadData();
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (rootNavigator.canPop()) {
          rootNavigator.pop();
        }
      });
    }
  }
}
