import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import 'cash_close_dialog.dart';
import 'cash_open_dialog.dart';
import 'cash_panel_sheet.dart';

/// Pagina principal de gestion de Caja
class CashBoxPage extends StatefulWidget {
  const CashBoxPage({super.key});

  @override
  State<CashBoxPage> createState() => _CashBoxPageState();
}

class _CashBoxPageState extends State<CashBoxPage> {
  CashSessionModel? _session;
  List<CashSessionModel> _history = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final session = await CashRepository.getOpenSession();
    final history = await CashRepository.listClosedSessions(limit: 30);
    if (!mounted) return;
    setState(() {
      _session = session;
      _history = history;
      _isLoading = false;
    });
  }

  Future<void> _openCashDialog() async {
    final result = await CashOpenDialog.show(context);
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _closeCashDialog() async {
    final sessionId = _session?.id;
    if (sessionId == null) return;
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
        title: const Text('Gestion de Caja'),
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
            if (_session == null)
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
              Text('No hay caja abierta', style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openCashDialog,
                icon: const Icon(Icons.add),
                label: const Text('Abrir Caja'),
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
    final session = _session!;
    final openedAt = DateFormat('dd/MM/yyyy HH:mm').format(session.openedAt);

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
                  'Caja abierta',
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
              'Saldo inicial: RD\$ ${_formatAmount(session.openingAmount)}',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Cajero: ${session.userName}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _openPanel,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Panel de caja'),
                ),
                OutlinedButton.icon(
                  onPressed: _closeCashDialog,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Hacer corte'),
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
