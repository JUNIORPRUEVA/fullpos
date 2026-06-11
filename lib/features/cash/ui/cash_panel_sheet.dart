import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/utils/currency_display.dart';
import '../../settings/providers/theme_provider.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_session_model.dart';
import '../data/cash_summary_model.dart';
import '../data/cash_repository.dart';
import 'cash_close_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Brand palette
// ─────────────────────────────────────────────────────────────────────────────
const Color _primaryBlue = Color(0xFF1A56DB);
const Color _softBg = Color(0xFFF2F6F9);
const Color _surface = Colors.white;
const Color _softBorder = Color(0xFFE2E8F0);
const Color _darkText = Color(0xFF0F172A);
const Color _mutedText = Color(0xFF64748B);
const Color _successGreen = Color(0xFF16A34A);
const Color _warningAmber = Color(0xFFD97706);
const Color _dangerRed = Color(0xFFDC2626);
const Color _infoBlue = Color(0xFF2563EB);

/// Panel lateral de caja con resumen y opciones
class CashPanelSheet extends ConsumerStatefulWidget {
  final int sessionId;

  const CashPanelSheet({super.key, required this.sessionId});

  static Future<void> show(BuildContext context, {required int sessionId}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
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
  CashSummaryModel? _summary;
  List<CashMovementModel> _movements = [];
  CashSessionModel? _session;

  late final DateFormat _openedAtFormat = DateFormat('dd/MM HH:mm');
  late final NumberFormat _moneyFormat = CurrencyDisplay.currency();

  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Mantener el tiempo del turno "vivo" sin recargar data.
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
    await Future.wait([_loadSession(), _loadSummary(), _loadMovements()]);
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

  void _openCloseDialog() {
    Navigator.pop(context);
    CashCloseDialog.show(
      context,
      sessionId: widget.sessionId,
      logoutAfterClose: true,
      initialSummary: _summary,
      initialSession: _session,
      initialMovements: _movements,
    );
  }

  void _openCurrentCutView() {
    // Already viewing the current cut - just close and reopen the close dialog
    Navigator.pop(context);
    CashCloseDialog.show(
      context,
      sessionId: widget.sessionId,
      logoutAfterClose: false,
      initialSummary: _summary,
      initialSession: _session,
      initialMovements: _movements,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(themeProvider);
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final safeWidth = (screenSize.width - 24).clamp(360.0, 620.0);
    final dialogWidth = math.min(
      (screenSize.width * 0.34).clamp(420.0, 540.0),
      safeWidth,
    );
    final availableHeight = math.min(
      (screenSize.height - viewInsets.vertical - 12).clamp(
        640.0,
        screenSize.height,
      ),
      screenSize.height - 4,
    );
    final isCompact = dialogWidth < 620 || availableHeight < 760;
    final isUltraCompact = dialogWidth < 500 || availableHeight < 640;
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

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Fondo semitransparente
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.black.withOpacity(0.15)),
            ),
          ),
          // Panel pegado a la derecha, centrado verticalmente
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: dialogWidth,
            child: Center(
              child: SizedBox(
                width: dialogWidth,
                height: availableHeight,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(isCompact ? 14 : 16),
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
                    children: [
                      _buildShiftHeader(
                        theme: theme,
                        session: session,
                        durationText: durationText,
                        isCompact: isCompact,
                        isUltraCompact: isUltraCompact,
                        sidebarAccent: sidebarAccent,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            isUltraCompact ? 12 : (isCompact ? 14 : 18),
                            isUltraCompact ? 10 : 6,
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildShiftHeader({
    required ThemeData theme,
    required CashSessionModel? session,
    required String? durationText,
    required bool isCompact,
    required bool isUltraCompact,
    required Color sidebarAccent,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isUltraCompact ? 12 : (isCompact ? 14 : 16),
        isUltraCompact ? 10 : (isCompact ? 12 : 14),
        isUltraCompact ? 8 : (isCompact ? 10 : 12),
        isUltraCompact ? 8 : (isCompact ? 10 : 12),
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _softBorder.withOpacity(0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon + title + close
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon block
              Container(
                width: isUltraCompact ? 34 : (isCompact ? 38 : 42),
                height: isUltraCompact ? 34 : (isCompact ? 38 : 42),
                decoration: BoxDecoration(
                  color: _primaryBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: _primaryBlue,
                  size: isUltraCompact ? 17 : (isCompact ? 19 : 20),
                ),
              ),
              SizedBox(width: isUltraCompact ? 10 : 12),
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Corte actual',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isUltraCompact ? 16 : (isCompact ? 18 : 20),
                        color: _darkText,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Resumen del turno activo',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: isUltraCompact ? 10.5 : 11.5,
                        color: _mutedText,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              // Close button
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: _mutedText),
                iconSize: isUltraCompact ? 18 : 20,
                splashRadius: 18,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          // Badges row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildBadge(
                icon: Icons.person_outline,
                label: _loadingSession
                    ? 'Cargando turno'
                    : (session == null
                          ? 'Sin sesión activa'
                          : session.userName),
              ),
              if (session != null && durationText != null)
                _buildBadge(
                  icon: Icons.schedule,
                  label: '$durationText activos',
                ),
              if (session != null)
                _buildBadge(
                  icon: Icons.event_available,
                  label: _openedAtFormat.format(session.openedAt),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _softBorder.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _primaryBlue),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: _darkText.withOpacity(0.75),
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DASHBOARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDashboard({
    required ThemeData theme,
    required bool isCompact,
    required bool isUltraCompact,
    required Color sidebarColor,
    required Color sidebarAccent,
    required Color sidebarText,
  }) {
    if (_loadingSummary && _loadingMovements && _loadingSession) {
      return Center(child: CircularProgressIndicator(color: _primaryBlue));
    }

    if (_summary == null) {
      return Center(
        child: Text(
          'No se pudo cargar el resumen del corte.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _mutedText,
          ),
        ),
      );
    }

    final gap = isUltraCompact ? 10.0 : (isCompact ? 12.0 : 14.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Main total card
        _buildMainTotalCard(
          theme: theme,
          isCompact: isCompact,
          isUltraCompact: isUltraCompact,
          sidebarAccent: sidebarAccent,
        ),
        SizedBox(height: gap),
        // 2. Metric cards row
        _buildMetricCardsRow(
          theme: theme,
          isUltraCompact: isUltraCompact,
        ),
        SizedBox(height: gap),
        // 3. Closing action card
        _buildClosingStatusCard(
          theme: theme,
          isCompact: isCompact,
          isUltraCompact: isUltraCompact,
        ),
        SizedBox(height: gap),
        // 4. Composition card
        _buildCompositionCard(
          theme: theme,
          isUltraCompact: isUltraCompact,
          sidebarAccent: sidebarAccent,
        ),
        SizedBox(height: gap),
        // 5. Movements / empty state
        _buildMovementsSection(
          theme: theme,
          isUltraCompact: isUltraCompact,
          sidebarAccent: sidebarAccent,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN TOTAL CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMainTotalCard({
    required ThemeData theme,
    required bool isCompact,
    required bool isUltraCompact,
    required Color sidebarAccent,
  }) {
    final summary = _summary!;
    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 14 : 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _softBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row + refresh
          Row(
            children: [
              Text(
                'Total vendido',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: isUltraCompact ? 11.5 : 12.5,
                  color: _mutedText,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              _buildRefreshButton(isUltraCompact: isUltraCompact),
            ],
          ),
          SizedBox(height: isUltraCompact ? 6 : 8),
          // Big amount
          Text(
            _moneyFormat.format(summary.totalSold),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: isUltraCompact ? 26 : (isCompact ? 30 : 34),
              color: _darkText,
              height: 1.1,
            ),
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          // Expected cash chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _primaryBlue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 14,
                  color: _primaryBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  'Efectivo esperado  ${_moneyFormat.format(summary.expectedCash)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: isUltraCompact ? 10.5 : 11.5,
                    color: _primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshButton({required bool isUltraCompact}) {
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: _loadData,
        style: OutlinedButton.styleFrom(
          backgroundColor: _softBg,
          foregroundColor: _primaryBlue,
          side: BorderSide(color: _softBorder),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(Icons.refresh_rounded, size: isUltraCompact ? 13 : 14),
        label: Text(
          'Actualizar',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: isUltraCompact ? 10 : 10.5,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // METRIC CARDS ROW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMetricCardsRow({
    required ThemeData theme,
    required bool isUltraCompact,
  }) {
    final summary = _summary!;
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.play_circle_outline_rounded,
            label: 'Base inicial',
            value: _moneyFormat.format(summary.openingAmount),
            color: _infoBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Efectivo esperado',
            value: _moneyFormat.format(summary.expectedCash),
            color: _primaryBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.receipt_long_rounded,
            label: 'Tickets',
            value: '${summary.totalTickets}',
            color: _successGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: _darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
              color: _mutedText,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLOSING STATUS CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildClosingStatusCard({
    required ThemeData theme,
    required bool isCompact,
    required bool isUltraCompact,
  }) {
    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 12 : 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Cierre del turno',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isUltraCompact ? 12.5 : 13.5,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Resumen y movimientos en una misma vista.',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: isUltraCompact ? 10 : 11,
                        color: _mutedText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _softBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _softBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 15,
                      color: _mutedText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Solo vista',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: isUltraCompact ? 10 : 11,
                        color: _mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: _openCurrentCutView,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryBlue,
                      side: BorderSide(color: _primaryBlue.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 15),
                    label: Text(
                      'Ver corte actual',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: isUltraCompact ? 10 : 11,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _openCloseDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.lock_outline, size: 15),
                    label: Text(
                      'Cerrar turno',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: isUltraCompact ? 10 : 11,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPOSITION CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCompositionCard({
    required ThemeData theme,
    required bool isUltraCompact,
    required Color sidebarAccent,
  }) {
    final summary = _summary!;
    final items = <({IconData icon, String label, double amount, Color color})>[
      (
        icon: Icons.payments_rounded,
        label: 'Ventas efectivo',
        amount: summary.salesCashTotal,
        color: _successGreen,
      ),
      (
        icon: Icons.credit_card_rounded,
        label: 'Ventas tarjeta',
        amount: summary.salesCardTotal,
        color: _infoBlue,
      ),
      (
        icon: Icons.swap_horiz_rounded,
        label: 'Transferencias',
        amount: summary.salesTransferTotal,
        color: _primaryBlue,
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: 'Créditos',
        amount: summary.salesCreditTotal,
        color: _warningAmber,
      ),
      (
        icon: Icons.add_circle_rounded,
        label: 'Entradas manuales',
        amount: summary.cashInManual,
        color: _successGreen,
      ),
      (
        icon: Icons.remove_circle_rounded,
        label: 'Salidas de caja',
        amount: summary.cashOutManual,
        color: _dangerRed,
      ),
      if (summary.refundsCash > 0)
        (
          icon: Icons.undo_rounded,
          label: 'Devoluciones',
          amount: summary.refundsCash,
          color: _dangerRed,
        ),
    ];

    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 12 : 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Composición del corte',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isUltraCompact ? 12.5 : 13.5,
                    color: _darkText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _softBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: isUltraCompact ? 10 : 11,
                    color: _mutedText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total vendido incluye todos los métodos; efectivo esperado es solo lo que debe estar en gaveta.',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: isUltraCompact ? 9.5 : 10.5,
              color: _mutedText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          // Rows
          for (var index = 0; index < items.length; index++) ...[
            _buildCompositionRow(
              icon: items[index].icon,
              label: items[index].label,
              amount: items[index].amount,
              color: items[index].color,
            ),
            if (index != items.length - 1)
              Padding(
                padding: EdgeInsets.only(top: isUltraCompact ? 4 : 6),
                child: Divider(height: 1, color: _softBorder.withOpacity(0.5)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompositionRow({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: _darkText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _moneyFormat.format(amount),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOVEMENTS SECTION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMovementsSection({
    required ThemeData theme,
    required bool isUltraCompact,
    required Color sidebarAccent,
  }) {
    if (_loadingMovements) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _softBorder),
        ),
        child: Center(
          child: CircularProgressIndicator(color: _primaryBlue),
        ),
      );
    }

    if (_movements.isEmpty) {
      return _buildEmptyMovementsState(isUltraCompact: isUltraCompact);
    }

    // Movements list
    final dateFormat = DateFormat('dd/MM HH:mm');
    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 12 : 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Historial de movimientos',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isUltraCompact ? 12.5 : 13.5,
                    color: _darkText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _softBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_movements.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: isUltraCompact ? 10 : 11,
                    color: _mutedText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_movements.length} registros dentro del turno actual.',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: isUltraCompact ? 9.5 : 10.5,
              color: _mutedText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isUltraCompact ? 8 : 10),
          for (var index = 0; index < _movements.length; index++) ...[
            _buildMovementTile(
              movement: _movements[index],
              timeLabel: dateFormat.format(_movements[index].createdAt),
            ),
            if (index != _movements.length - 1)
              Padding(
                padding: EdgeInsets.only(top: isUltraCompact ? 4 : 6),
                child: Divider(height: 1, color: _softBorder.withOpacity(0.5)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyMovementsState({required bool isUltraCompact}) {
    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 14 : 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _softBorder,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _softBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.inbox_outlined,
              color: _mutedText,
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No hay movimientos manuales',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isUltraCompact ? 12 : 13,
              color: _darkText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Cuando se registren entradas o retiros, aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: isUltraCompact ? 10 : 11,
              color: _mutedText,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOVEMENT TILE
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMovementTile({
    required CashMovementModel movement,
    required String timeLabel,
  }) {
    final isIncome = movement.isIn;
    final movementColor = isIncome ? _successGreen : _dangerRed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: movementColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: movementColor,
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: _darkText,
                  ),
                ),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                    color: _mutedText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIncome ? '+' : '-'}${_moneyFormat.format(movement.amount)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: movementColor,
            ),
          ),
        ],
      ),
    );
  }
}
