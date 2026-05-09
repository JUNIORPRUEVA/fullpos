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
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 6, 10, 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: dialogWidth,
            height: availableHeight,
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
                children: [
                  _buildHeader(
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
        isUltraCompact ? 12 : (isCompact ? 14 : 16),
        isUltraCompact ? 10 : (isCompact ? 12 : 14),
        isUltraCompact ? 8 : (isCompact ? 10 : 12),
        isUltraCompact ? 8 : (isCompact ? 10 : 12),
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
            width: isUltraCompact ? 34 : (isCompact ? 38 : 42),
            height: isUltraCompact ? 34 : (isCompact ? 38 : 42),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(isUltraCompact ? 11 : 13),
              border: Border.all(color: scheme.primary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: sidebarAccent,
              size: isUltraCompact ? 17 : (isCompact ? 19 : 20),
            ),
          ),
          SizedBox(width: isUltraCompact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CORTE ACTUAL',
                  style:
                      (isUltraCompact
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                            letterSpacing: 0.15,
                          ),
                ),
                SizedBox(height: isUltraCompact ? 5 : 7),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
              fontSize: 10,
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
    final accent = scheme.primary;
    final actionColor = scheme.outline;

    return Container(
      padding: EdgeInsets.all(isUltraCompact ? 9 : (isCompact ? 11 : 12)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withOpacity(0.12), scheme.surface),
            Color.alphaBlend(actionColor.withOpacity(0.08), scheme.surface),
          ],
        ),
        borderRadius: BorderRadius.circular(isUltraCompact ? 14 : 16),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildActionBannerCopy(theme, isUltraCompact)),
          SizedBox(width: isUltraCompact ? 8 : 10),
          SizedBox(
            width: isUltraCompact ? 132 : 144,
            child: _buildViewOnlyBadge(
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
          'Cierre del turno',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: isUltraCompact ? 11.0 : 11.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Resumen y movimientos en la misma vista.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withOpacity(0.72),
            height: 1.1,
            fontWeight: FontWeight.w500,
            fontSize: isUltraCompact ? 9.3 : 9.7,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildViewOnlyBadge({
    required Color actionColor,
    required bool isUltraCompact,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isUltraCompact ? 10 : 12,
        vertical: isUltraCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: actionColor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: isUltraCompact ? 15 : 16,
            color: scheme.onSurface.withOpacity(0.58),
          ),
          SizedBox(width: isUltraCompact ? 6 : 8),
          Text(
            'Solo vista',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: isUltraCompact ? 9.8 : 10.4,
              color: scheme.onSurface.withOpacity(0.66),
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
        final gap = isUltraCompact ? 8.0 : (isCompact ? 9.0 : 10.0);

        final hero = _buildSummaryHero(
          theme: theme,
          isCompact: isCompact,
          isUltraCompact: isUltraCompact,
          sidebarColor: sidebarColor,
          sidebarAccent: sidebarAccent,
          sidebarText: sidebarText,
        );
        final breakdown = _buildBreakdownDetailsTab(
          theme: theme,
          isCompactDialog: isUltraCompact,
          sidebarAccent: sidebarAccent,
        );
        final movements = _buildMovementDetailsTab(
          theme: theme,
          isCompactDialog: isUltraCompact,
          sidebarAccent: sidebarAccent,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            SizedBox(height: gap),
            _buildActionBanner(
              theme: theme,
              isCompact: isCompact,
              isUltraCompact: isUltraCompact,
            ),
            SizedBox(height: gap),
            if (constraints.maxWidth >= 940)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: breakdown),
                  SizedBox(width: gap),
                  Expanded(child: movements),
                ],
              )
            else ...[
              breakdown,
              SizedBox(height: gap),
              movements,
            ],
          ],
        );
      },
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
        label: 'Salidas de caja',
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.36)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isCompactDialog ? 11 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Composición del corte',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: isCompactDialog ? 12.4 : 13,
                    ),
                  ),
                ),
                Text(
                  '${items.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withOpacity(0.48),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Total vendido incluye todos los métodos; efectivo esperado es solo lo que debe estar en gaveta.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.64),
                fontWeight: FontWeight.w600,
                fontSize: isCompactDialog ? 9.6 : 10.0,
              ),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < items.length; index++) ...[
              _buildBreakdownTile(
                icon: items[index].icon,
                label: items[index].label,
                amount: items[index].amount,
                color: items[index].color,
                isUltraCompact: false,
              ),
              if (index != items.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.36)),
      ),
      child: _loadingMovements
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: scheme.primary),
              ),
            )
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
          : Padding(
              padding: EdgeInsets.all(isCompactDialog ? 11 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Historial de movimientos',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: isCompactDialog ? 12.4 : 13,
                          ),
                        ),
                      ),
                      Text(
                        '${_movements.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface.withOpacity(0.48),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_movements.length} registros dentro del turno actual.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.64),
                      fontWeight: FontWeight.w600,
                      fontSize: isCompactDialog ? 9.6 : 10.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var index = 0; index < _movements.length; index++) ...[
                    _buildMovementTile(
                      movement: _movements[index],
                      timeLabel: dateFormat.format(_movements[index].createdAt),
                      isUltraCompact: false,
                    ),
                    if (index != _movements.length - 1)
                      const SizedBox(height: 8),
                  ],
                ],
              ),
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
      padding: EdgeInsets.all(isUltraCompact ? 10 : (isCompact ? 12 : 13)),
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
        borderRadius: BorderRadius.circular(isUltraCompact ? 14 : 16),
        border: Border.all(color: sidebarAccent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TOTAL VENDIDO',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.74),
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w800,
                  fontSize: isUltraCompact ? 10.0 : 10.4,
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
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                icon: Icon(
                  Icons.refresh_rounded,
                  size: isUltraCompact ? 13 : 14,
                ),
                label: Text(
                  'Actualizar',
                  style: TextStyle(fontSize: isUltraCompact ? 9.6 : 10),
                ),
              ),
            ],
          ),
          SizedBox(height: isUltraCompact ? 6 : 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _moneyFormat.format(summary.totalSold),
                style:
                    (isUltraCompact
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineLarge)
                        ?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: isUltraCompact ? 21 : (isCompact ? 24 : 26),
                        ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                      'Efectivo esperado: ${_moneyFormat.format(summary.expectedCash)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: sidebarAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: isUltraCompact ? 9.4 : 9.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isUltraCompact ? 6 : 8),
          Row(
            children: [
              Expanded(
                child: _buildMiniStatCard(
                  label: 'Base inicial',
                  value: _moneyFormat.format(summary.openingAmount),
                  color: scheme.primary,
                  icon: Icons.play_circle_outline_rounded,
                  isUltraCompact: isUltraCompact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStatCard(
                  label: 'Efectivo esperado',
                  value: _moneyFormat.format(summary.expectedCash),
                  color: scheme.secondary,
                  icon: Icons.account_balance_wallet_rounded,
                  isUltraCompact: isUltraCompact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStatCard(
                  label: 'Tickets',
                  value: '${summary.totalTickets}',
                  color: status.success,
                  icon: Icons.receipt_long_rounded,
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
      padding: EdgeInsets.all(isUltraCompact ? 7 : 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.08), scheme.surface),
        borderRadius: BorderRadius.circular(isUltraCompact ? 10 : 12),
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
              fontSize: isUltraCompact ? 11.4 : 12.4,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withOpacity(0.62),
              fontWeight: FontWeight.w600,
              fontSize: isUltraCompact ? 8.8 : 9.2,
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
        horizontal: isUltraCompact ? 8 : 9,
        vertical: isUltraCompact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.08), scheme.surface),
        borderRadius: BorderRadius.circular(isUltraCompact ? 10 : 12),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: isUltraCompact ? 22 : 24,
            height: isUltraCompact ? 22 : 24,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: isUltraCompact ? 12 : 13),
          ),
          SizedBox(width: isUltraCompact ? 7 : 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: isUltraCompact ? 9.8 : 10.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: isUltraCompact ? 92 : 104,
            child: Text(
              _moneyFormat.format(amount),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: isUltraCompact ? 9.8 : 10.4,
              ),
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
      padding: EdgeInsets.all(isUltraCompact ? 7 : 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          movementColor.withOpacity(0.08),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(isUltraCompact ? 10 : 12),
        border: Border.all(color: movementColor.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: isUltraCompact ? 22 : 24,
            height: isUltraCompact ? 22 : 24,
            decoration: BoxDecoration(
              color: movementColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: movementColor,
              size: isUltraCompact ? 12 : 13,
            ),
          ),
          SizedBox(width: isUltraCompact ? 7 : 8),
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
                    fontSize: isUltraCompact ? 9.8 : 10.1,
                  ),
                ),
                Text(
                  timeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.58),
                    fontWeight: FontWeight.w600,
                    fontSize: isUltraCompact ? 8.8 : 9.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: isUltraCompact ? 92 : 104,
            child: Text(
              '${isIncome ? '+' : '-'}${_moneyFormat.format(movement.amount)}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: movementColor,
                fontWeight: FontWeight.w900,
                fontSize: isUltraCompact ? 9.6 : 10.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
