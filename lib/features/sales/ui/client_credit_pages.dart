import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../core/utils/currency_display.dart';
import '../../../theme/app_colors.dart';
import '../../cash/data/cash_repository.dart' as cash_repo;
import '../../settings/data/printer_settings_repository.dart';
import '../data/credits_repository.dart';
import '../data/layaway_repository.dart';
import '../data/sales_repository.dart';

enum _AccountStatusFilter { all, pending, paid }

class ClientCreditsPage extends StatefulWidget {
  const ClientCreditsPage({super.key});

  @override
  State<ClientCreditsPage> createState() => _ClientCreditsPageState();
}

class _ClientCreditsPageState extends State<ClientCreditsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  int? _selectedSaleId;
  int _loadSeq = 0;
  _AccountStatusFilter _statusFilter = _AccountStatusFilter.all;

  NumberFormat get _currency => CurrencyDisplay.currency(symbol: r'$');

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCredits() async {
    final seq = ++_loadSeq;
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final sales = await CreditsRepository.listCreditSales();
      if (!mounted || seq != _loadSeq) return;

      setState(() {
        _sales = sales;
        if (_sales.isEmpty) {
          _selectedSaleId = null;
        } else {
          final match = _selectedSaleId != null
              ? _sales.firstWhere(
                  (sale) => sale['id'] == _selectedSaleId,
                  orElse: () => _sales.first,
                )
              : _sales.first;
          _selectedSaleId = match['id'] as int?;
        }
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadCredits,
        module: 'sales/credits/page_load',
      );
    }
  }

  List<Map<String, dynamic>> get _filteredSales {
    final query = _searchController.text.trim().toLowerCase();
    final filteredByQuery = query.isEmpty
        ? _sales
        : _sales.where((sale) {
            final values = [
              sale['local_code'],
              sale['customer_name_snapshot'],
              sale['customer_phone_snapshot'],
            ];
            return values.any(
              (value) => value.toString().toLowerCase().contains(query),
            );
          }).toList();

    switch (_statusFilter) {
      case _AccountStatusFilter.all:
        return filteredByQuery;
      case _AccountStatusFilter.pending:
        return filteredByQuery.where((sale) => _pendingAmount(sale) > 0).toList();
      case _AccountStatusFilter.paid:
        return filteredByQuery.where((sale) => _pendingAmount(sale) <= 0).toList();
    }
  }

  Map<String, dynamic>? get _selectedSale {
    if (_selectedSaleId == null) return null;
    for (final sale in _filteredSales) {
      if (sale['id'] == _selectedSaleId) return sale;
    }
    return _filteredSales.isEmpty ? null : _filteredSales.first;
  }

  double _pendingAmount(Map<String, dynamic> sale) =>
      ((sale['amount_pending'] as num?)?.toDouble() ?? 0.0)
          .clamp(0.0, double.infinity);

  String _formatCurrency(double value) => _currency.format(value);

  String _formatDate(int? ms) {
    if (ms == null) return 'Sin fecha';
    return DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1440.0;
    final contentWidth = math.min(constraints.maxWidth * 0.92, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(24.0, 160.0)
        .toDouble();
    return EdgeInsets.fromLTRB(side, 22, side, 24);
  }

  Future<void> _showPaymentDialog(
    int saleId,
    String saleCode,
    String clientName,
    double saleTotal,
    double pendingAmount,
    int? clientId,
  ) async {
    final amountController = TextEditingController();

    Future<void> submit(BuildContext dialogContext) async {
      final amount = double.tryParse(amountController.text) ?? 0.0;
      if (amount <= 0) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Monto inválido')),
        );
        return;
      }
      if (pendingAmount > 0 && amount > pendingAmount) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('El abono excede el saldo pendiente')),
        );
        return;
      }

      try {
        final sessionId = await cash_repo.CashRepository.getCurrentSessionId();
        final paymentResult = await CreditsRepository.registerCreditPayment(
          saleId: saleId,
          clientId: clientId ?? 0,
          amount: amount,
          method: 'cash',
          sessionId: sessionId,
        );

        try {
          final sale = await SalesRepository.getSaleById(saleId);
          final items = await SalesRepository.getItemsBySaleId(saleId);
          if (sale != null) {
            final settings = await PrinterSettingsRepository.getOrCreate();
            if (settings.selectedPrinterName != null &&
                settings.selectedPrinterName!.isNotEmpty) {
              final cashierName = await SessionManager.displayName() ?? 'Cajero';
              final pendingAfter = paymentResult.pendingAmount;
              final statusLabel = pendingAfter > 0 ? 'PENDIENTE' : 'PAGADO';
              final saleForPrint = sale.copyWith(
                paidAmount: paymentResult.totalPaid,
                changeAmount: 0.0,
              );

              await UnifiedTicketPrinter.printSaleTicket(
                sale: saleForPrint,
                items: items,
                cashierName: cashierName,
                pendingAmount: pendingAfter,
                lastPaymentAmount: amount,
                statusLabel: statusLabel,
              );
            }
          }
        } catch (e) {
          debugPrint('Error al imprimir ticket de crédito: $e');
        }

        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
        }
        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Abono registrado')));
        await _loadCredits();
      } catch (e, st) {
        if (!mounted) return;
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _showPaymentDialog(
            saleId,
            saleCode,
            clientName,
            saleTotal,
            pendingAmount,
            clientId,
          ),
          module: 'sales/credits/payment',
        );
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => DialogKeyboardShortcuts(
        onSubmit: () => submit(dialogContext),
        child: _TinyPaymentDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registrar abono',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Factura: $saleCode'),
              Text('Cliente: $clientName'),
              Text('Total: ${_formatCurrency(saleTotal)}'),
              Text('Pendiente: ${_formatCurrency(pendingAmount)}'),
              const SizedBox(height: 14),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(dialogContext),
                decoration: const InputDecoration(
                  labelText: 'Monto a abonar',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => submit(dialogContext),
                    child: const Text('Registrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filteredSales = _filteredSales;
    final selectedSale = _selectedSale;
    final totalPending = filteredSales.fold<double>(
      0,
      (sum, sale) => sum + _pendingAmount(sale),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _contentPadding(constraints);
        final isWide = constraints.maxWidth >= 1200;
        final detailWidth = (constraints.maxWidth * 0.28).clamp(340.0, 430.0);

        final header = _AccountsHeaderCard(
          eyebrow: 'Clientes',
          title: 'Créditos',
          subtitle:
              'Consulta cuentas por cobrar, revisa el estado actual y registra abonos sin salir de esta pantalla.',
          searchController: _searchController,
          searchHint: 'Buscar por cliente, teléfono o código...',
          statusFilter: _statusFilter,
          onFilterChanged: (value) => setState(() => _statusFilter = value),
          onSearchChanged: (_) => setState(() {}),
          summaryItems: [
            _SummaryItem(
              label: 'Créditos visibles',
              value: '${filteredSales.length}',
              tone: _SummaryTone.neutral,
            ),
            _SummaryItem(
              label: 'Saldo pendiente',
              value: _formatCurrency(totalPending),
              tone: _SummaryTone.primary,
            ),
          ],
        );

        final listCard = _AccountsListCard(
          title: 'Cuentas registradas',
          emptyTitle: 'No hay créditos para mostrar',
          emptyMessage: _searchController.text.trim().isNotEmpty
              ? 'Prueba ajustando la búsqueda o el filtro.'
              : 'Cuando existan ventas a crédito activas aparecerán aquí.',
          loading: _loading,
          itemCount: filteredSales.length,
          itemBuilder: (context, index) {
            final sale = filteredSales[index];
            final pending = _pendingAmount(sale);
            final totalDue =
                (sale['total_due'] as num?)?.toDouble() ??
                ((sale['total'] as num?)?.toDouble() ?? 0.0);
            final isSelected = sale['id'] == (selectedSale?['id']);

            return _AccountRow(
              isSelected: isSelected,
              icon: Icons.receipt_long_outlined,
              title: (sale['customer_name_snapshot'] ?? 'Cliente sin nombre')
                  .toString(),
              subtitle:
                  '${sale['local_code'] ?? 'N/A'} • vence ${_formatDate(sale['credit_due_date_ms'] as int?)}',
              trailingTop: _formatCurrency(totalDue),
              trailingBottom: pending > 0
                  ? 'Pendiente ${_formatCurrency(pending)}'
                  : 'Pagado',
              trailingTone: pending > 0
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF15803D),
              statusLabel: pending > 0 ? 'PENDIENTE' : 'PAGADO',
              onTap: () => setState(() => _selectedSaleId = sale['id'] as int?),
              menuItems: [
                PopupMenuItem<String>(
                  value: 'pay',
                  enabled: pending > 0,
                  child: const Text('Registrar abono'),
                ),
              ],
              onMenuSelected: (value) {
                if (value != 'pay') return;
                _showPaymentDialog(
                  sale['id'] as int,
                  (sale['local_code'] ?? 'N/A').toString(),
                  (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
                  totalDue,
                  pending,
                  sale['customer_id'] as int?,
                );
              },
            );
          },
        );

        final detailCard = _CreditDetailCard(
          sale: selectedSale,
          formatCurrency: _formatCurrency,
          formatDate: _formatDate,
          onRegisterPayment: selectedSale == null
              ? null
              : () => _showPaymentDialog(
                  selectedSale['id'] as int,
                  (selectedSale['local_code'] ?? 'N/A').toString(),
                  (selectedSale['customer_name_snapshot'] ?? 'Cliente')
                      .toString(),
                  (selectedSale['total_due'] as num?)?.toDouble() ??
                      ((selectedSale['total'] as num?)?.toDouble() ?? 0.0),
                  _pendingAmount(selectedSale),
                  selectedSale['customer_id'] as int?,
                ),
        );

        return Container(
          color: scheme.surface,
          child: Padding(
            padding: padding,
            child: Column(
              children: [
                header,
                const SizedBox(height: 18),
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: listCard),
                            const SizedBox(width: 18),
                            SizedBox(width: detailWidth, child: detailCard),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(flex: 6, child: listCard),
                            const SizedBox(height: 18),
                            Expanded(flex: 5, child: detailCard),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ClientLayawaysPage extends StatefulWidget {
  const ClientLayawaysPage({super.key});

  @override
  State<ClientLayawaysPage> createState() => _ClientLayawaysPageState();
}

class _ClientLayawaysPageState extends State<ClientLayawaysPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  int? _selectedSaleId;
  int _loadSeq = 0;
  _AccountStatusFilter _statusFilter = _AccountStatusFilter.all;

  NumberFormat get _currency => CurrencyDisplay.currency(symbol: r'$');

  @override
  void initState() {
    super.initState();
    _loadLayaways();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLayaways() async {
    final seq = ++_loadSeq;
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final sales = await LayawayRepository.listLayawaySales();
      if (!mounted || seq != _loadSeq) return;

      setState(() {
        _sales = sales;
        if (_sales.isEmpty) {
          _selectedSaleId = null;
        } else {
          final match = _selectedSaleId != null
              ? _sales.firstWhere(
                  (sale) => sale['id'] == _selectedSaleId,
                  orElse: () => _sales.first,
                )
              : _sales.first;
          _selectedSaleId = match['id'] as int?;
        }
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadLayaways,
        module: 'sales/layaways/page_load',
      );
    }
  }

  List<Map<String, dynamic>> get _filteredSales {
    final query = _searchController.text.trim().toLowerCase();
    final filteredByQuery = query.isEmpty
        ? _sales
        : _sales.where((sale) {
            final values = [
              sale['local_code'],
              sale['customer_name_snapshot'],
              sale['customer_phone_snapshot'],
            ];
            return values.any(
              (value) => value.toString().toLowerCase().contains(query),
            );
          }).toList();

    switch (_statusFilter) {
      case _AccountStatusFilter.all:
        return filteredByQuery;
      case _AccountStatusFilter.pending:
        return filteredByQuery.where((sale) => _pendingAmount(sale) > 0).toList();
      case _AccountStatusFilter.paid:
        return filteredByQuery.where((sale) => _pendingAmount(sale) <= 0).toList();
    }
  }

  Map<String, dynamic>? get _selectedSale {
    if (_selectedSaleId == null) return null;
    for (final sale in _filteredSales) {
      if (sale['id'] == _selectedSaleId) return sale;
    }
    return _filteredSales.isEmpty ? null : _filteredSales.first;
  }

  double _pendingAmount(Map<String, dynamic> sale) =>
      ((sale['amount_pending'] as num?)?.toDouble() ?? 0.0)
          .clamp(0.0, double.infinity);

  String _formatCurrency(double value) => _currency.format(value);

  Future<void> _showPaymentDialog(
    int saleId,
    String saleCode,
    String clientName,
    double saleTotal,
    double pendingAmount,
    int? clientId,
  ) async {
    final amountController = TextEditingController();

    Future<void> submit(BuildContext dialogContext) async {
      final amount = double.tryParse(amountController.text) ?? 0.0;
      if (amount <= 0) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Monto inválido')),
        );
        return;
      }
      if (pendingAmount > 0 && amount > pendingAmount) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('El abono excede el saldo pendiente')),
        );
        return;
      }

      try {
        final sessionId = await cash_repo.CashRepository.getCurrentSessionId();
        if (sessionId == null) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(
              content: Text('Debe abrir caja para registrar abonos de apartado'),
            ),
          );
          return;
        }

        final paymentResult = await LayawayRepository.registerLayawayPayment(
          saleId: saleId,
          clientId: clientId,
          amount: amount,
          method: 'cash',
          sessionId: sessionId,
        );

        try {
          final sale = await SalesRepository.getSaleById(saleId);
          final items = await SalesRepository.getItemsBySaleId(saleId);
          if (sale != null) {
            final settings = await PrinterSettingsRepository.getOrCreate();
            if (settings.selectedPrinterName != null &&
                settings.selectedPrinterName!.isNotEmpty) {
              final cashierName = await SessionManager.displayName() ?? 'Cajero';
              final pendingAfter = paymentResult.pendingAmount;
              final statusLabel = pendingAfter > 0 ? 'PENDIENTE' : 'PAGADO';
              await UnifiedTicketPrinter.printSaleTicket(
                sale: sale,
                items: items,
                cashierName: cashierName,
                isLayaway: true,
                pendingAmount: pendingAfter,
                lastPaymentAmount: amount,
                statusLabel: statusLabel,
              );
            }
          }
        } catch (e) {
          debugPrint('Error al imprimir ticket de apartado: $e');
        }

        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
        }
        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Abono registrado')));
        await _loadLayaways();
      } catch (e, st) {
        if (!mounted) return;
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _showPaymentDialog(
            saleId,
            saleCode,
            clientName,
            saleTotal,
            pendingAmount,
            clientId,
          ),
          module: 'sales/layaways/payment',
        );
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => DialogKeyboardShortcuts(
        onSubmit: () => submit(dialogContext),
        child: _TinyPaymentDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registrar abono',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Apartado: $saleCode'),
              Text('Cliente: $clientName'),
              Text('Total: ${_formatCurrency(saleTotal)}'),
              Text('Pendiente: ${_formatCurrency(pendingAmount)}'),
              const SizedBox(height: 14),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(dialogContext),
                decoration: const InputDecoration(
                  labelText: 'Monto a abonar',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => submit(dialogContext),
                    child: const Text('Registrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1440.0;
    final contentWidth = math.min(constraints.maxWidth * 0.92, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(24.0, 160.0)
        .toDouble();
    return EdgeInsets.fromLTRB(side, 22, side, 24);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filteredSales = _filteredSales;
    final selectedSale = _selectedSale;
    final totalPending = filteredSales.fold<double>(
      0,
      (sum, sale) => sum + _pendingAmount(sale),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _contentPadding(constraints);
        final isWide = constraints.maxWidth >= 1200;
        final detailWidth = (constraints.maxWidth * 0.28).clamp(340.0, 430.0);

        final header = _AccountsHeaderCard(
          eyebrow: 'Clientes',
          title: 'Apartados',
          subtitle:
              'Gestiona apartados en una pantalla dedicada, compacta y clara, con acceso directo a sus abonos.',
          searchController: _searchController,
          searchHint: 'Buscar por cliente, teléfono o código...',
          statusFilter: _statusFilter,
          onFilterChanged: (value) => setState(() => _statusFilter = value),
          onSearchChanged: (_) => setState(() {}),
          summaryItems: [
            _SummaryItem(
              label: 'Apartados visibles',
              value: '${filteredSales.length}',
              tone: _SummaryTone.neutral,
            ),
            _SummaryItem(
              label: 'Saldo pendiente',
              value: _formatCurrency(totalPending),
              tone: _SummaryTone.primary,
            ),
          ],
        );

        final listCard = _AccountsListCard(
          title: 'Apartados registrados',
          emptyTitle: 'No hay apartados para mostrar',
          emptyMessage: _searchController.text.trim().isNotEmpty
              ? 'Prueba ajustando la búsqueda o el filtro.'
              : 'Cuando existan apartados activos aparecerán aquí.',
          loading: _loading,
          itemCount: filteredSales.length,
          itemBuilder: (context, index) {
            final sale = filteredSales[index];
            final pending = _pendingAmount(sale);
            final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
            final isSelected = sale['id'] == (selectedSale?['id']);

            return _AccountRow(
              isSelected: isSelected,
              icon: Icons.bookmark_border_rounded,
              title: (sale['customer_name_snapshot'] ?? 'Cliente sin nombre')
                  .toString(),
              subtitle: '${sale['local_code'] ?? 'N/A'} • total ${_formatCurrency(total)}',
              trailingTop: _formatCurrency(total),
              trailingBottom: pending > 0
                  ? 'Pendiente ${_formatCurrency(pending)}'
                  : 'Pagado',
              trailingTone: pending > 0
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF15803D),
              statusLabel: pending > 0 ? 'PENDIENTE' : 'PAGADO',
              onTap: () => setState(() => _selectedSaleId = sale['id'] as int?),
              menuItems: [
                PopupMenuItem<String>(
                  value: 'pay',
                  enabled: pending > 0,
                  child: const Text('Registrar abono'),
                ),
              ],
              onMenuSelected: (value) {
                if (value != 'pay') return;
                _showPaymentDialog(
                  sale['id'] as int,
                  (sale['local_code'] ?? 'N/A').toString(),
                  (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
                  total,
                  pending,
                  sale['customer_id'] as int?,
                );
              },
            );
          },
        );

        final detailCard = _LayawayDetailCard(
          sale: selectedSale,
          formatCurrency: _formatCurrency,
          onRegisterPayment: selectedSale == null
              ? null
              : () => _showPaymentDialog(
                  selectedSale['id'] as int,
                  (selectedSale['local_code'] ?? 'N/A').toString(),
                  (selectedSale['customer_name_snapshot'] ?? 'Cliente')
                      .toString(),
                  (selectedSale['total'] as num?)?.toDouble() ?? 0.0,
                  _pendingAmount(selectedSale),
                  selectedSale['customer_id'] as int?,
                ),
        );

        return Container(
          color: scheme.surface,
          child: Padding(
            padding: padding,
            child: Column(
              children: [
                header,
                const SizedBox(height: 18),
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: listCard),
                            const SizedBox(width: 18),
                            SizedBox(width: detailWidth, child: detailCard),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(flex: 6, child: listCard),
                            const SizedBox(height: 18),
                            Expanded(flex: 5, child: detailCard),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AccountsHeaderCard extends StatelessWidget {
  const _AccountsHeaderCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.searchController,
    required this.searchHint,
    required this.statusFilter,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.summaryItems,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final TextEditingController searchController;
  final String searchHint;
  final _AccountStatusFilter statusFilter;
  final ValueChanged<_AccountStatusFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final List<_SummaryItem> summaryItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.66),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                searchController.clear();
                                onSearchChanged('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<_AccountStatusFilter>(
                    value: statusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _AccountStatusFilter.all,
                        child: Text('Todos'),
                      ),
                      DropdownMenuItem(
                        value: _AccountStatusFilter.pending,
                        child: Text('Pendientes'),
                      ),
                      DropdownMenuItem(
                        value: _AccountStatusFilter.paid,
                        child: Text('Pagados'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onFilterChanged(value);
                    },
                  ),
                ),
                for (final item in summaryItems) _SummaryPill(item: item),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountsListCard extends StatelessWidget {
  const _AccountsListCard({
    required this.title,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.loading,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final String emptyTitle;
  final String emptyMessage;
  final bool loading;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.75)),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : itemCount == 0
                ? _EmptyPanel(
                    title: emptyTitle,
                    message: emptyMessage,
                    icon: Icons.inbox_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    itemCount: itemCount,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: itemBuilder,
                  ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailingTop,
    required this.trailingBottom,
    required this.trailingTone,
    required this.statusLabel,
    required this.onTap,
    required this.menuItems,
    required this.onMenuSelected,
  });

  final bool isSelected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailingTop;
  final String trailingBottom;
  final Color trailingTone;
  final String statusLabel;
  final VoidCallback onTap;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? AppColors.primaryBlue.withOpacity(0.06)
          : scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryBlue.withOpacity(0.35)
                  : scheme.outlineVariant.withOpacity(0.65),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withOpacity(0.62),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailingTop,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trailingBottom,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: trailingTone,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusBadge(label: statusLabel),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                onSelected: onMenuSelected,
                itemBuilder: (context) => menuItems,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditDetailCard extends StatelessWidget {
  const _CreditDetailCard({
    required this.sale,
    required this.formatCurrency,
    required this.formatDate,
    required this.onRegisterPayment,
  });

  final Map<String, dynamic>? sale;
  final String Function(double) formatCurrency;
  final String Function(int?) formatDate;
  final VoidCallback? onRegisterPayment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sale == null) {
      return const _EmptyPanel(
        title: 'Selecciona un crédito',
        message: 'Aquí verás el detalle completo y el acceso al registro de abonos.',
        icon: Icons.receipt_long_outlined,
      );
    }

    final total = (sale!['total'] as num?)?.toDouble() ?? 0.0;
    final totalDue = (sale!['total_due'] as num?)?.toDouble() ?? total;
    final pending = ((sale!['amount_pending'] as num?)?.toDouble() ?? 0.0)
        .clamp(0.0, double.infinity);
    final paid = (sale!['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final interestRate =
        (sale!['credit_interest_rate'] as num?)?.toDouble() ?? 0.0;
    final installments = sale!['credit_installments'] as int?;
    final termDays = sale!['credit_term_days'] as int?;
    final note = (sale!['credit_note'] ?? '').toString().trim();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (sale!['local_code'] ?? 'N/A').toString(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusBadge(label: pending > 0 ? 'PENDIENTE' : 'PAGADO'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              (sale!['customer_name_snapshot'] ?? 'Cliente').toString(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if ((sale!['customer_phone_snapshot'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                sale!['customer_phone_snapshot'].toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.62),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _DetailMetric(label: 'Total venta', value: formatCurrency(total)),
            _DetailMetric(label: 'Interés', value: '${interestRate.toStringAsFixed(2)}%'),
            _DetailMetric(label: 'Total crédito', value: formatCurrency(totalDue)),
            _DetailMetric(label: 'Pagado', value: formatCurrency(paid)),
            _DetailMetric(
              label: 'Pendiente',
              value: formatCurrency(pending),
              highlighted: true,
            ),
            if (termDays != null && termDays > 0)
              _DetailMetric(label: 'Plazo', value: '$termDays días'),
            if (installments != null && installments > 0)
              _DetailMetric(label: 'Cuotas', value: '$installments'),
            if (sale!['credit_due_date_ms'] != null)
              _DetailMetric(
                label: 'Vence',
                value: formatDate(sale!['credit_due_date_ms'] as int?),
              ),
            if (note.isNotEmpty) _DetailMetric(label: 'Nota', value: note),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: pending > 0 ? onRegisterPayment : null,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Registrar abono'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayawayDetailCard extends StatelessWidget {
  const _LayawayDetailCard({
    required this.sale,
    required this.formatCurrency,
    required this.onRegisterPayment,
  });

  final Map<String, dynamic>? sale;
  final String Function(double) formatCurrency;
  final VoidCallback? onRegisterPayment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sale == null) {
      return const _EmptyPanel(
        title: 'Selecciona un apartado',
        message: 'Aquí verás el detalle completo y el acceso al registro de abonos.',
        icon: Icons.bookmark_border_rounded,
      );
    }

    final total = (sale!['total'] as num?)?.toDouble() ?? 0.0;
    final pending = ((sale!['amount_pending'] as num?)?.toDouble() ?? 0.0)
        .clamp(0.0, double.infinity);
    final paid = (sale!['amount_paid'] as num?)?.toDouble() ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (sale!['local_code'] ?? 'N/A').toString(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusBadge(label: pending > 0 ? 'PENDIENTE' : 'PAGADO'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              (sale!['customer_name_snapshot'] ?? 'Cliente').toString(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if ((sale!['customer_phone_snapshot'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                sale!['customer_phone_snapshot'].toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.62),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _DetailMetric(label: 'Total', value: formatCurrency(total)),
            _DetailMetric(label: 'Pagado', value: formatCurrency(paid)),
            _DetailMetric(
              label: 'Pendiente',
              value: formatCurrency(pending),
              highlighted: true,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: pending > 0 ? onRegisterPayment : null,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Registrar abono'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.58),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: highlighted ? AppColors.primaryBlue : scheme.onSurface,
                fontWeight: highlighted ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isPaid = label == 'PAGADO';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isPaid ? const Color(0xFF166534) : const Color(0xFF92400E),
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: scheme.onSurface.withOpacity(0.35)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.58),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.item});

  final _SummaryItem item;

  @override
  Widget build(BuildContext context) {
    final isPrimary = item.tone == _SummaryTone.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isPrimary ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPrimary
              ? AppColors.primaryBlue.withOpacity(0.18)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isPrimary ? AppColors.primaryBlue : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyPaymentDialog extends StatelessWidget {
  const _TinyPaymentDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(size.width * 0.9, 440),
        ),
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final _SummaryTone tone;
}

enum _SummaryTone { neutral, primary }
