import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/cashbox_daily_model.dart';
import '../data/daily_cash_close_ticket_printer.dart';
import '../data/operation_flow_service.dart';
import '../../auth/data/auth_repository.dart';
import 'cash_close_dialog.dart';
import 'cashbox_open_dialog.dart';
import 'cash_panel_sheet.dart';

/// Pagina principal de gestion de Caja
class CashBoxPage extends StatefulWidget {
  const CashBoxPage({super.key, this.autoOpenShiftCut = false});

  /// Si es true, al entrar a la pantalla intentará abrir automáticamente
  /// el diálogo de "Corte" (cierre de turno) cuando exista un turno abierto.
  final bool autoOpenShiftCut;

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
  bool _isMutating = false;

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

    // Si esta pantalla fue abierta específicamente para hacer el corte,
    // abrir el diálogo automáticamente (post-frame) para llevar al usuario
    // directo al flujo correcto.
    if (!mounted) return;
    if (widget.autoOpenShiftCut && !_isMutating) {
      final sessionId = _session?.id;
      if (sessionId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_isMutating) return;
          // Solo si todavía hay sesión abierta.
          if (_session?.id != sessionId) return;
          unawaited(_closeCashDialog());
        });
      }
    }
  }

  Future<void> _openCashDialog() async {
    final amount = await CashboxOpenDialog.show(
      context: context,
      canOpen: _canOpenCashbox,
      title: 'Abrir caja del día',
      subtitle:
          'Registra el fondo inicial para habilitar los turnos de trabajo.',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _closeDailyCashbox() async {
    if (_isMutating) return;
    if (!mounted) return;

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

    setState(() => _isMutating = true);
    try {
      await OperationFlowService.closeDailyCashboxToday(
        note: 'Cierre diario desde módulo Caja',
      );

      if (shouldPrint == true && cashboxId != null) {
        try {
          await DailyCashCloseTicketPrinter.printDailyCloseTicket(
            cashboxDailyId: cashboxId,
            businessDate: businessDate,
            note: 'Cierre diario desde módulo Caja',
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

      if (mounted) {
        setState(() {
          _session = null;
          _cashboxToday = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caja diaria cerrada correctamente.')),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
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
                      final amount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      amountCtrl.dispose();
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
            content: Text('No tienes permiso para hacer corte de turno.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isMutating = true);
    try {
      final result = await CashCloseDialog.show(context, sessionId: sessionId);
      if (result == true && mounted) {
        setState(() => _session = null);
        await _loadData();

        // Si el usuario llegó aquí desde "Iniciar operación" por un corte forzado,
        // al completar el corte regresamos automáticamente a esa pantalla.
        if (widget.autoOpenShiftCut && mounted) {
          context.go('/operation-start');
          return;
        }

        // UX: al cerrar el turno, no volver a mostrar el cuadro de “Abrir turno”.
        // Redirigir al flujo oficial de “Iniciar operación”.
        if (mounted) {
          context.go('/operation-start');
          return;
        }
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
                'Paso 1: abrir caja diaria',
                style: theme.textTheme.titleMedium,
              ),
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
                  _canOpenCashbox
                      ? 'Abrir Caja del Día'
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
            if (session != null) ...[
              const SizedBox(height: 6),
              Text(
                'Monto inicial turno: RD\$ ${_formatAmount(session.openingAmount)}',
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
            const SizedBox(height: 12),
            Text(
              'Turno (Corte cajero): abrir/cerrar turno del usuario actual.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Caja (Fin del día): solo supervisor/admin y únicamente sin turnos abiertos.',
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
                  message: 'Turno: iniciar o gestionar corte del cajero actual',
                  child: ElevatedButton.icon(
                    onPressed: _isMutating
                        ? null
                        : session == null
                        ? (_canOpenShift ? _openShiftDialog : null)
                        : _openPanel,
                    icon: Icon(
                      session == null ? Icons.play_arrow : Icons.point_of_sale,
                    ),
                    label: Text(
                      session == null
                          ? (_canOpenShift
                                ? 'Abrir turno'
                                : 'Sin permiso para abrir turno')
                          : 'Panel de turno',
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Turno: registrar cierre del turno del cajero',
                  child: OutlinedButton.icon(
                    onPressed:
                        (_isMutating || session == null || !_canCloseShift)
                        ? null
                        : _closeCashDialog,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Hacer corte de turno'),
                  ),
                ),
                Tooltip(
                  message:
                      'Caja diaria: cierre de fin de día (sin turnos abiertos)',
                  child: OutlinedButton.icon(
                    onPressed:
                        (_isMutating || !(_canCloseCashbox && session == null))
                        ? null
                        : _closeDailyCashbox,
                    icon: const Icon(Icons.lock_clock),
                    label: Text(
                      _isMutating ? 'Procesando...' : 'Cerrar caja del día',
                    ),
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
