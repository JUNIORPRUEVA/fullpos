import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/cashbox_daily_model.dart';
import '../data/operation_flow_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../settings/data/user_model.dart' show UserPermissions;
import 'cash_close_dialog.dart';
import 'cashbox_open_dialog.dart';
import 'cash_panel_sheet.dart';

/// Pagina principal de gestion de Caja
class CashBoxPage extends StatefulWidget {
  const CashBoxPage({super.key});

  @override
  State<CashBoxPage> createState() => _CashBoxPageState();
}

class _CashBoxPageState extends State<CashBoxPage> {
  CashSessionModel? _session;
  CashboxDailyModel? _cashboxToday;
  List<CashSessionModel> _history = const [];
  bool _isLoading = true;
  bool _canOpenCashbox = false;
  bool _canCloseShift = false;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final results = await Future.wait([
      OperationFlowService.loadGateState(),
      AuthRepository.getCurrentPermissions(),
      CashRepository.listClosedSessions(limit: 30),
    ]);
    final gate = results[0] as OperationGateState;
    final perms = results[1] as UserPermissions;
    final history = results[2] as List<CashSessionModel>;
    final session = gate.userOpenShift;
    if (!mounted) return;
    setState(() {
      _session = session;
      _cashboxToday = gate.cashboxToday;
      _history = history;
      _canOpenCashbox = perms.canOpenCashbox || perms.canOpenCash;
      _canCloseShift = perms.canCloseShift || perms.canCloseCash;
      _isLoading = false;
    });
  }

  Future<void> _openCashDialog() async {
    if (_cashboxToday?.isOpen == true) {
      try {
        await OperationFlowService.ensureActiveSessionForCurrentUser(
          openingAmount: 0,
          note: 'Reanudación desde módulo Caja',
        );
        if (mounted) context.go('/sales');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
      return;
    }

    final amount = await CashboxOpenDialog.show(
      context: context,
      canOpen: _canOpenCashbox,
      title: 'Abrir caja',
      subtitle: 'Registra el fondo inicial para comenzar a trabajar.',
      confirmLabel: 'Abrir caja',
      deniedMessage: 'Requiere supervisor/admin para abrir caja.',
    );
    if (amount == null) return;

    try {
      await OperationFlowService.ensureActiveSessionForCurrentUser(
        openingAmount: amount,
        note: 'Apertura manual desde módulo Caja',
      );
      if (mounted) context.go('/sales');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _closeCashDialog() async {
    if (_isMutating) return;
    final sessionId = _session?.id;
    if (sessionId == null) return;
    if (!_canCloseShift) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No tienes permiso para cerrar la sesión.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isMutating = true);
    try {
      final result = await CashCloseDialog.show(
        context,
        sessionId: sessionId,
        logoutAfterClose: false,
      );
      if (result == true && mounted) {
        setState(() => _session = null);
        await _loadData();
        return;
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _openPanel() async {
    final sessionId = _session?.id;
    if (sessionId == null) return;
    await CashPanelSheet.show(context, sessionId: sessionId);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesión de Caja'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/cash/history'),
            icon: const Icon(Icons.history),
            label: const Text('Cortes y movimientos'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_cashboxToday == null || _cashboxToday?.isOpen != true)
              _buildClosedState(context)
            else
              _buildOpenState(context),
            const SizedBox(height: 20),
            Text(
              'Historial de cortes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _history.isEmpty
                  ? Center(
                      child: Text(
                        'Sin cortes registrados',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final diff = item.difference ?? 0.0;
                        final diffColor = diff == 0
                            ? scheme.primary
                            : (diff > 0 ? scheme.tertiary : scheme.error);
                        final date = item.closedAt != null
                            ? DateFormat(
                                'dd/MM/yyyy hh:mm a',
                              ).format(item.closedAt!).toUpperCase()
                            : 'N/D';

                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.lock_clock,
                              color: scheme.primary,
                            ),
                            title: Text('Corte #${item.id ?? '-'}'),
                            subtitle: Text('Cierre: $date'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'RD\$ ${_formatAmount(item.closingAmount)}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (item.difference != null)
                                  Text(
                                    'Dif: ${_formatAmount(diff)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: diffColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedState(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.store_outlined,
                size: 64,
                color: scheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Abrir caja para trabajar',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'La caja y el turno ahora funcionan como una sola sesión. Abre caja y entra directo al POS.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _canOpenCashbox ? _openCashDialog : null,
                icon: const Icon(Icons.add),
                label: Text(
                  _canOpenCashbox
                      ? 'Abrir Caja y Entrar'
                      : 'Requiere Supervisor/Admin',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/cash/history'),
                icon: const Icon(Icons.history),
                label: const Text('Cortes y movimientos'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpenState(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = _session;
    final cashbox = _cashboxToday!;
    final openedAt = DateFormat(
      'dd/MM/yyyy hh:mm a',
    ).format(cashbox.openedAt).toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_open, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Caja activa',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(openedAt, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Fondo inicial caja: RD\$ ${_formatAmount(cashbox.initialAmount)}',
              style: theme.textTheme.bodyLarge,
            ),
            if (session != null) ...[
              const SizedBox(height: 6),
              Text(
                'Monto inicial sesión: RD\$ ${_formatAmount(session.openingAmount)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Fecha operativa: ${cashbox.businessDate}',
              style: theme.textTheme.bodyMedium,
            ),
            if (session != null) ...[
              const SizedBox(height: 6),
              Text(
                'Sesión activa: ${session.userName}',
                style: theme.textTheme.bodyMedium,
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'Caja abierta sin sesión activa. Entra al POS para restaurarla.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'La caja y el turno se manejan como una sola sesión operativa.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Al cerrar la sesión se cierra la caja, se imprime el cierre y el usuario sale del sistema.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Tooltip(
                  message: 'Abrir caja y continuar con la sesión activa',
                  child: ElevatedButton.icon(
                    onPressed: _isMutating
                        ? null
                        : session == null
                        ? _openCashDialog
                        : _openPanel,
                    icon: Icon(
                      session == null ? Icons.play_arrow : Icons.point_of_sale,
                    ),
                    label: Text(
                      session == null
                          ? (_canOpenCashbox
                                ? 'Entrar al POS'
                                : 'Sin permiso para abrir caja')
                          : 'Panel de sesión',
                    ),
                  ),
                ),
                Tooltip(
                  message:
                      'Cerrar la sesión activa, la caja y salir del sistema',
                  child: OutlinedButton.icon(
                    onPressed:
                        (_isMutating || session == null || !_canCloseShift)
                        ? null
                        : _closeCashDialog,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Cerrar sesión'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/cash/history'),
                  icon: const Icon(Icons.history),
                  label: const Text('Cortes y movimientos'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double? value) {
    final amount = value ?? 0.0;
    return amount.toStringAsFixed(2);
  }
}
