import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/cashbox_daily_model.dart';
import '../data/operation_flow_service.dart';
import '../../auth/data/auth_repository.dart';
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
  bool _canCloseCashbox = false;
  bool _canOpenShift = false;
  bool _canCloseShift = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final gate = await OperationFlowService.loadGateState();
    final perms = await AuthRepository.getCurrentPermissions();
    final session = gate.userOpenShift;
    final history = await CashRepository.listClosedSessions(limit: 30);
    if (!mounted) return;
    setState(() {
      _session = session;
      _cashboxToday = gate.cashboxToday;
      _history = history;
      _canOpenCashbox = perms.canOpenCashbox || perms.canOpenCash;
      _canCloseCashbox = perms.canCloseCashbox;
      _canOpenShift = perms.canOpenShift || perms.canOpenCash;
      _canCloseShift = perms.canCloseShift || perms.canCloseCash;
      _isLoading = false;
    });
  }

  Future<void> _openCashDialog() async {
    final amount = await CashboxOpenDialog.show(
      context: context,
      canOpen: _canOpenCashbox,
      title: 'Abrir caja del día',
      subtitle: 'Registra el fondo inicial para habilitar los turnos de trabajo.',
      confirmLabel: 'Abrir caja',
      deniedMessage: 'Requiere supervisor/admin para abrir caja.',
    );
    if (amount == null) return;

    try {
      await OperationFlowService.openDailyCashboxToday(
        openingAmount: amount,
        note: 'Apertura manual desde módulo Caja',
      );
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _closeDailyCashbox() async {
    try {
      await OperationFlowService.closeDailyCashboxToday(
        note: 'Cierre diario desde módulo Caja',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caja diaria cerrada correctamente.')),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _openShiftDialog() async {
    final amountCtrl = TextEditingController(text: '0.00');
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Abrir turno'),
          content: TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monto inicial turno',
              prefixText: 'RD\$ ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: _canOpenShift
                  ? () async {
                      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      await OperationFlowService.openShiftForCurrentUser(
                        openingAmount: amount,
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    }
                  : null,
              child: const Text('Iniciar turno'),
            ),
          ],
        ),
      );
      if (result == true) {
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      amountCtrl.dispose();
    }
  }

  Future<void> _closeCashDialog() async {
    final sessionId = _session?.id;
    if (sessionId == null) return;
    if (!_canCloseShift) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tienes permiso para hacer corte de turno.')),
        );
      }
      return;
    }
    final result = await CashCloseDialog.show(context, sessionId: sessionId);
    if (result == true) {
      await _loadData();
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
        title: const Text('Caja y Corte'),
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
                                'dd/MM/yyyy HH:mm',
                              ).format(item.closedAt!)
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
              Text('Paso 1: abrir caja diaria', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Primero abre la caja del día para habilitar la apertura de turno y el corte.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _canOpenCashbox ? _openCashDialog : null,
                icon: const Icon(Icons.add),
                label: Text(
                  _canOpenCashbox ? 'Abrir Caja del Día' : 'Requiere Supervisor/Admin',
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
    final openedAt = DateFormat('dd/MM/yyyy HH:mm').format(cashbox.openedAt);

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
                  'Caja diaria abierta',
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
            const SizedBox(height: 6),
            Text('Fecha operativa: ${cashbox.businessDate}', style: theme.textTheme.bodyMedium),
            if (session != null) ...[
              const SizedBox(height: 6),
              Text(
                'Turno activo: ${session.userName}',
                style: theme.textTheme.bodyMedium,
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'Paso 2: no hay turno abierto. Abre un turno para vender.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: session == null
                      ? (_canOpenShift ? _openShiftDialog : null)
                      : _openPanel,
                  icon: Icon(session == null ? Icons.play_arrow : Icons.point_of_sale),
                  label: Text(
                    session == null
                        ? (_canOpenShift ? 'Abrir turno' : 'Sin permiso para abrir turno')
                        : 'Panel de turno',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: (session == null || !_canCloseShift) ? null : _closeCashDialog,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Hacer corte de turno'),
                ),
                OutlinedButton.icon(
                  onPressed: (_canCloseCashbox && session == null)
                      ? _closeDailyCashbox
                      : null,
                  icon: const Icon(Icons.lock_clock),
                  label: const Text('Cerrar caja del día'),
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
