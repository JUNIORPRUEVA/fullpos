import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_session_model.dart';
import '../data/cash_summary_model.dart';
import '../data/cash_repository.dart';
import '../data/daily_cash_close_ticket_printer.dart';
import '../data/operation_flow_service.dart';
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
  bool _canCloseCashbox = false;
  bool _closingCashbox = false;

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
        _canCloseCashbox = perms.canCloseCashbox;
        _loadingPermissions = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _canCloseShift = false;
          _canCloseCashbox = false;
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
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    const targetWidth = 560.0;
    const targetHeight = 720.0;
    final safeWidth = (screenSize.width - 48).clamp(320.0, 1200.0);
    final safeHeight = (screenSize.height - viewInsets.vertical - 48).clamp(
      520.0,
      1200.0,
    );
    final dialogWidth = targetWidth.clamp(320.0, safeWidth);
    final dialogHeight = targetHeight.clamp(520.0, safeHeight);

    final session = _session;
    final openedAt = session?.openedAt;
    final duration = openedAt == null
        ? null
        : DateTime.now().difference(openedAt);
    final durationText = duration == null ? null : _formatDuration(duration);

    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
          minWidth: 320,
          minHeight: 520,
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.point_of_sale,
                      color: scheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PANEL DE CAJA',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        _loadingSession
                            ? 'Cargando turno…'
                            : (session == null
                                  ? 'Caja abierta'
                                  : 'Cajero: ${session.userName}'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: session == null
                              ? status.success
                              : scheme.onSurface.withOpacity(0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (session != null && durationText != null)
                        Text(
                          'Tiempo: $durationText  •  Apertura: ${DateFormat('dd/MM HH:mm').format(session.openedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: scheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: scheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

            // Acciones de cierre
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.lock_outline,
                      label: 'Hacer cortes de turno',
                      color: status.error,
                      enabled:
                          !_loadingPermissions &&
                          (_session?.isOpen == true) &&
                          _canCloseShift,
                      onTap: _showCloseDialog,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                'Este panel es informativo del usuario actual. Aquí haces cortes de turno.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.62),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Contenido con tabs
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      indicatorColor: scheme.primary,
                      labelColor: scheme.primary,
                      unselectedLabelColor: scheme.onSurface.withOpacity(0.6),
                      tabs: const [
                        Tab(text: 'RESUMEN'),
                        Tab(text: 'MOVIMIENTOS'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [_buildSummaryTab(), _buildMovementsTab()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: (enabled ? color : scheme.outline).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (enabled ? color : scheme.outline).withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: enabled ? color : scheme.onSurface.withOpacity(0.45),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: enabled ? color : scheme.onSurface.withOpacity(0.45),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_loadingSummary) {
      return Center(child: CircularProgressIndicator(color: scheme.primary));
    }

    if (_summary == null) {
      return Center(
        child: Text(
          'No se pudo cargar el resumen',
          style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 16),
          _buildSalesBreakdown(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withOpacity(0.18),
            scheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EFECTIVO ESPERADO',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              IconButton(
                onPressed: _loadData,
                icon: Icon(
                  Icons.refresh,
                  color: scheme.onSurface.withOpacity(0.6),
                  size: 20,
                ),
                splashRadius: 18,
              ),
            ],
          ),
          Text(
            '\$${_summary!.expectedCash.toStringAsFixed(2)}',
            style: TextStyle(
              color: scheme.primary,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMiniStat(
                'Apertura',
                '\$${_summary!.openingAmount.toStringAsFixed(2)}',
                scheme.onSurface,
              ),
              _buildMiniStat(
                'Tickets',
                '${_summary!.totalTickets}',
                scheme.primary,
              ),
              _buildMiniStat(
                'Ventas',
                '\$${_summary!.totalSales.toStringAsFixed(2)}',
                status.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurface.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesBreakdown() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DESGLOSE',
            style: TextStyle(
              color: scheme.onSurface.withOpacity(0.6),
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _buildBreakdownRow(
            Icons.payments,
            'Ventas Efectivo',
            _summary!.salesCashTotal,
            status.success,
          ),
          _buildBreakdownRow(
            Icons.credit_card,
            'Ventas Tarjeta',
            _summary!.salesCardTotal,
            scheme.primary,
          ),
          _buildBreakdownRow(
            Icons.swap_horiz,
            'Transferencias',
            _summary!.salesTransferTotal,
            scheme.secondary,
          ),
          _buildBreakdownRow(
            Icons.schedule,
            'Créditos',
            _summary!.salesCreditTotal,
            status.warning,
          ),
          Divider(color: scheme.outlineVariant, height: 20),
          _buildBreakdownRow(
            Icons.add_circle,
            'Entradas manuales',
            _summary!.cashInManual,
            status.success,
          ),
          _buildBreakdownRow(
            Icons.remove_circle,
            'Retiros manuales',
            _summary!.cashOutManual,
            status.error,
          ),
          if (_summary!.refundsCash > 0)
            _buildBreakdownRow(
              Icons.undo,
              'Devoluciones',
              _summary!.refundsCash,
              status.error,
            ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(
    IconData icon,
    String label,
    double amount,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurface, fontSize: 13),
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    if (_loadingMovements) {
      return Center(child: CircularProgressIndicator(color: scheme.primary));
    }

    if (_movements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              color: scheme.onSurface.withOpacity(0.6),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No hay movimientos registrados',
              style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _movements.length,
      itemBuilder: (context, index) {
        final movement = _movements[index];
        final isIncome = movement.isIn;
        final movementColor = isIncome ? status.success : status.error;
        final dateFormat = DateFormat('HH:mm');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: movementColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isIncome ? Icons.add : Icons.remove,
                  color: movementColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.reason,
                      style: TextStyle(color: scheme.onSurface, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      dateFormat.format(movement.createdAt),
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${isIncome ? '+' : '-'}\$${movement.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: movementColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCloseDialog() async {
    if (_session?.isOpen != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu turno ya está cerrado.')),
      );
      return;
    }

    if (!_canCloseShift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para hacer cortes de turno.'),
        ),
      );
      return;
    }

    final result = await CashCloseDialog.show(
      context,
      sessionId: widget.sessionId,
    );

    if (result == true && mounted) {
      await _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turno cerrado correctamente.')),
      );

      // Evitar _debugLocked: cerrar rutas/navegar en el siguiente frame.
      // (Cerrar el panel y luego enviar al flujo de operación.)
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      final rootContext = rootNavigator.context;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Cerrar el panel (Dialog)
        if (rootNavigator.canPop()) {
          rootNavigator.pop();
        }
        // Navegar en el frame siguiente para no competir con el pop.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          rootContext.go('/operation-start');
        });
      });
    }
  }

  Future<void> _showCloseCashbox() async {
    if (_closingCashbox) return;
    if (!_canCloseCashbox) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para cerrar caja del día.'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar caja (fin del día)'),
        content: const Text(
          'Este proceso cierra la caja del día y bloquea operar hasta abrir una nueva caja. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final shouldPrint = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Imprimir ticket'),
        content: const Text(
          '¿Deseas imprimir el ticket de cierre de caja del día?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No imprimir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Imprimir'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    final businessDate = OperationFlowService.businessDateOf();
    final cashboxBefore = await OperationFlowService.getDailyCashbox(
      businessDate,
    );
    final cashboxId = cashboxBefore?.id;

    if (!mounted) return;

    setState(() => _closingCashbox = true);
    try {
      await OperationFlowService.closeDailyCashboxToday(
        note: 'Cierre diario ejecutado desde Panel de caja',
      );

      if (shouldPrint == true && cashboxId != null) {
        try {
          await DailyCashCloseTicketPrinter.printDailyCloseTicket(
            cashboxDailyId: cashboxId,
            businessDate: businessDate,
            note: 'Cierre diario ejecutado desde Panel de caja',
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Caja cerrada, pero no se pudo imprimir: $e'),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja del día cerrada correctamente.')),
      );
      await _loadData();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _closingCashbox = false);
    }
  }
}
