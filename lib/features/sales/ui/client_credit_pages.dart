import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../core/utils/currency_display.dart';
import '../../cash/data/cash_repository.dart' as cash_repo;
import '../../settings/data/printer_settings_repository.dart';
import '../data/credits_repository.dart';
import '../data/layaway_repository.dart';
import '../data/sales_repository.dart';

enum _AccountStatusFilter { all, pending, paid }

const Color _fullPosBlue = Color(0xFF1A56DB);
const Color _softBlue = Color(0xFFEAF2FF);
const Color _softPanel = Color(0xFFF8FAFC);
const Color _paidGreen = Color(0xFF15803D);
const Color _paidGreenBg = Color(0xFFDCFCE7);

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
      (((sale['amount_pending'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, double.infinity))
          .toDouble();

  String _formatCurrency(double value) => _currency.format(value);

  String _formatDate(int? ms) {
    if (ms == null) return '-';
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
          title: 'Registrar abono',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PaymentDialogInfo(label: 'Factura', value: saleCode),
              _PaymentDialogInfo(label: 'Cliente', value: clientName),
              _PaymentDialogInfo(label: 'Total', value: _formatCurrency(saleTotal)),
              _PaymentDialogInfo(
                label: 'Pendiente',
                value: _formatCurrency(pendingAmount),
                highlighted: true,
              ),
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

  void _showCreditDetailsSidePanel(Map<String, dynamic> sale) {
    if (!mounted) return;

    setState(() => _selectedSaleId = sale['id'] as int?);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar ficha del crédito',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 392,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
              child: _CreditSideDetailsPanel(
                sale: sale,
                formatCurrency: _formatCurrency,
                formatDate: _formatDate,
                onClose: () => Navigator.of(context).pop(),
                onRegisterPayment: () {
                  Navigator.of(context).pop();
                  final totalDue = (sale['total_due'] as num?)?.toDouble() ??
                      ((sale['total'] as num?)?.toDouble() ?? 0.0);
                  _showPaymentDialog(
                    sale['id'] as int,
                    (sale['local_code'] ?? 'N/A').toString(),
                    (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
                    totalDue,
                    _pendingAmount(sale),
                    sale['customer_id'] as int?,
                  );
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Widget _buildActionsMenu() {
    return SizedBox(
      height: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (value) {
          switch (value) {
            case 'refresh':
              _loadCredits();
              break;
            case 'details':
              final sale = _selectedSale;
              if (sale != null) _showCreditDetailsSidePanel(sale);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'refresh',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.refresh_rounded),
              title: Text('Actualizar'),
            ),
          ),
          PopupMenuItem(
            value: 'details',
            enabled: _selectedSale != null,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.visibility_outlined),
              title: Text('Abrir ficha'),
            ),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _fullPosBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _fullPosBlue),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Acciones',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeaderLine({
    required double minWidth,
  }) {
    final filteredSales = _filteredSales;
    final totalPending = filteredSales.fold<double>(
      0,
      (sum, sale) => sum + _pendingAmount(sale),
    );
    final pendingCount = filteredSales.where((sale) => _pendingAmount(sale) > 0).length;
    final paidCount = filteredSales.where((sale) => _pendingAmount(sale) <= 0).length;

    return _AccountsTopHeaderLine(
      minWidth: minWidth,
      searchController: _searchController,
      searchHint: 'Buscar cliente, teléfono o código...',
      statusFilter: _statusFilter,
      onFilterChanged: (value) => setState(() => _statusFilter = value),
      onSearchChanged: (_) => setState(() {}),
      onClearSearch: () {
        setState(() => _searchController.clear());
      },
      actionsMenu: _buildActionsMenu(),
      summaryItems: [
        _SummaryItem(label: 'Créditos', value: '${filteredSales.length}'),
        _SummaryItem(
          label: 'Pendientes',
          value: '$pendingCount',
          backgroundColor: _softBlue,
          borderColor: _fullPosBlue.withOpacity(0.26),
          textColor: _fullPosBlue,
        ),
        _SummaryItem(
          label: 'Pagados',
          value: '$paidCount',
          backgroundColor: _softPanel,
        ),
        _SummaryItem(
          label: 'Saldo pendiente',
          value: _formatCurrency(totalPending),
          backgroundColor: _softBlue,
          borderColor: _fullPosBlue.withOpacity(0.26),
          textColor: _fullPosBlue,
        ),
      ],
    );
  }

  Widget _buildListCard() {
    final filteredSales = _filteredSales;
    final selectedSale = _selectedSale;

    return _AccountsListCard(
      emptyTitle: 'No hay créditos',
      emptyMessage: _searchController.text.trim().isNotEmpty
          ? 'Intenta cambiar la búsqueda o el filtro.'
          : 'Cuando existan ventas a crédito aparecerán aquí.',
      loading: _loading,
      itemCount: filteredSales.length,
      header: const _AccountsListHeader(
        firstColumn: 'Cliente',
        codeColumn: 'Factura',
        dateColumn: 'Vence',
      ),
      itemBuilder: (context, index) {
        final sale = filteredSales[index];
        final pending = _pendingAmount(sale);
        final totalDue =
            (sale['total_due'] as num?)?.toDouble() ??
            ((sale['total'] as num?)?.toDouble() ?? 0.0);
        final isSelected = sale['id'] == (selectedSale?['id']);

        return _AccountTableRow(
          isSelected: isSelected,
          icon: Icons.receipt_long_outlined,
          title: (sale['customer_name_snapshot'] ?? 'Cliente sin nombre').toString(),
          phone: (sale['customer_phone_snapshot'] ?? '-').toString(),
          code: (sale['local_code'] ?? 'N/A').toString(),
          date: _formatDate(sale['credit_due_date_ms'] as int?),
          total: _formatCurrency(totalDue),
          pending: pending > 0 ? _formatCurrency(pending) : '-',
          statusLabel: pending > 0 ? 'Pendiente' : 'Pagado',
          isPaid: pending <= 0,
          onTap: () => _showCreditDetailsSidePanel(sale),
          menuItems: [
            PopupMenuItem<String>(
              value: 'pay',
              enabled: pending > 0,
              child: const Row(
                children: [
                  Icon(Icons.payments_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Registrar abono'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Ver ficha'),
                ],
              ),
            ),
          ],
          onMenuSelected: (value) {
            if (value == 'details') {
              _showCreditDetailsSidePanel(sale);
              return;
            }
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
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _contentPadding(constraints);
        final headerMinWidth = math
            .max(0.0, constraints.maxWidth - padding.left - padding.right)
            .toDouble();

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopHeaderLine(minWidth: headerMinWidth),
              const SizedBox(height: 18),
              Expanded(child: _buildListCard()),
            ],
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
      (((sale['amount_pending'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, double.infinity))
          .toDouble();

  String _formatCurrency(double value) => _currency.format(value);

  String _formatDate(int? ms) {
    if (ms == null) return '-';
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
          title: 'Registrar abono',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PaymentDialogInfo(label: 'Apartado', value: saleCode),
              _PaymentDialogInfo(label: 'Cliente', value: clientName),
              _PaymentDialogInfo(label: 'Total', value: _formatCurrency(saleTotal)),
              _PaymentDialogInfo(
                label: 'Pendiente',
                value: _formatCurrency(pendingAmount),
                highlighted: true,
              ),
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

  void _showLayawayDetailsSidePanel(Map<String, dynamic> sale) {
    if (!mounted) return;

    setState(() => _selectedSaleId = sale['id'] as int?);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar ficha del apartado',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 392,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
              child: _LayawaySideDetailsPanel(
                sale: sale,
                formatCurrency: _formatCurrency,
                onClose: () => Navigator.of(context).pop(),
                onRegisterPayment: () {
                  Navigator.of(context).pop();
                  final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
                  _showPaymentDialog(
                    sale['id'] as int,
                    (sale['local_code'] ?? 'N/A').toString(),
                    (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
                    total,
                    _pendingAmount(sale),
                    sale['customer_id'] as int?,
                  );
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Widget _buildActionsMenu() {
    return SizedBox(
      height: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (value) {
          switch (value) {
            case 'refresh':
              _loadLayaways();
              break;
            case 'details':
              final sale = _selectedSale;
              if (sale != null) _showLayawayDetailsSidePanel(sale);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'refresh',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.refresh_rounded),
              title: Text('Actualizar'),
            ),
          ),
          PopupMenuItem(
            value: 'details',
            enabled: _selectedSale != null,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.visibility_outlined),
              title: Text('Abrir ficha'),
            ),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _fullPosBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _fullPosBlue),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Acciones',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeaderLine({
    required double minWidth,
  }) {
    final filteredSales = _filteredSales;
    final totalPending = filteredSales.fold<double>(
      0,
      (sum, sale) => sum + _pendingAmount(sale),
    );
    final pendingCount = filteredSales.where((sale) => _pendingAmount(sale) > 0).length;
    final paidCount = filteredSales.where((sale) => _pendingAmount(sale) <= 0).length;

    return _AccountsTopHeaderLine(
      minWidth: minWidth,
      searchController: _searchController,
      searchHint: 'Buscar cliente, teléfono o código...',
      statusFilter: _statusFilter,
      onFilterChanged: (value) => setState(() => _statusFilter = value),
      onSearchChanged: (_) => setState(() {}),
      onClearSearch: () {
        setState(() => _searchController.clear());
      },
      actionsMenu: _buildActionsMenu(),
      summaryItems: [
        _SummaryItem(label: 'Apartados', value: '${filteredSales.length}'),
        _SummaryItem(
          label: 'Pendientes',
          value: '$pendingCount',
          backgroundColor: _softBlue,
          borderColor: _fullPosBlue.withOpacity(0.26),
          textColor: _fullPosBlue,
        ),
        _SummaryItem(
          label: 'Pagados',
          value: '$paidCount',
          backgroundColor: _softPanel,
        ),
        _SummaryItem(
          label: 'Saldo pendiente',
          value: _formatCurrency(totalPending),
          backgroundColor: _softBlue,
          borderColor: _fullPosBlue.withOpacity(0.26),
          textColor: _fullPosBlue,
        ),
      ],
    );
  }

  Widget _buildListCard() {
    final filteredSales = _filteredSales;
    final selectedSale = _selectedSale;

    return _AccountsListCard(
      emptyTitle: 'No hay apartados',
      emptyMessage: _searchController.text.trim().isNotEmpty
          ? 'Intenta cambiar la búsqueda o el filtro.'
          : 'Cuando existan apartados aparecerán aquí.',
      loading: _loading,
      itemCount: filteredSales.length,
      header: const _AccountsListHeader(
        firstColumn: 'Cliente',
        codeColumn: 'Apartado',
        dateColumn: 'Fecha',
      ),
      itemBuilder: (context, index) {
        final sale = filteredSales[index];
        final pending = _pendingAmount(sale);
        final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
        final isSelected = sale['id'] == (selectedSale?['id']);

        return _AccountTableRow(
          isSelected: isSelected,
          icon: Icons.bookmark_border_rounded,
          title: (sale['customer_name_snapshot'] ?? 'Cliente sin nombre').toString(),
          phone: (sale['customer_phone_snapshot'] ?? '-').toString(),
          code: (sale['local_code'] ?? 'N/A').toString(),
          date: _formatDate(sale['created_at_ms'] as int?),
          total: _formatCurrency(total),
          pending: pending > 0 ? _formatCurrency(pending) : '-',
          statusLabel: pending > 0 ? 'Pendiente' : 'Pagado',
          isPaid: pending <= 0,
          onTap: () => _showLayawayDetailsSidePanel(sale),
          menuItems: [
            PopupMenuItem<String>(
              value: 'pay',
              enabled: pending > 0,
              child: const Row(
                children: [
                  Icon(Icons.payments_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Registrar abono'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Ver ficha'),
                ],
              ),
            ),
          ],
          onMenuSelected: (value) {
            if (value == 'details') {
              _showLayawayDetailsSidePanel(sale);
              return;
            }
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
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _contentPadding(constraints);
        final headerMinWidth = math
            .max(0.0, constraints.maxWidth - padding.left - padding.right)
            .toDouble();

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopHeaderLine(minWidth: headerMinWidth),
              const SizedBox(height: 18),
              Expanded(child: _buildListCard()),
            ],
          ),
        );
      },
    );
  }
}

class _AccountsTopHeaderLine extends StatelessWidget {
  const _AccountsTopHeaderLine({
    required this.minWidth,
    required this.searchController,
    required this.searchHint,
    required this.statusFilter,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.actionsMenu,
    required this.summaryItems,
  });

  final double minWidth;
  final TextEditingController searchController;
  final String searchHint;
  final _AccountStatusFilter statusFilter;
  final ValueChanged<_AccountStatusFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final Widget actionsMenu;
  final List<_SummaryItem> summaryItems;

  String _filterLabel(_AccountStatusFilter filter) {
    switch (filter) {
      case _AccountStatusFilter.all:
        return 'Todos';
      case _AccountStatusFilter.pending:
        return 'Pendientes';
      case _AccountStatusFilter.paid:
        return 'Pagados';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget summaryBadge(_SummaryItem item) {
      return Expanded(
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: item.backgroundColor ?? Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: item.borderColor ?? scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: item.textColor ?? scheme.onSurface.withOpacity(0.72),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: item.textColor ?? scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final searchField = SizedBox(
      height: 48,
      child: TextField(
        controller: searchController,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: searchHint,
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: scheme.onSurface.withOpacity(0.48),
          ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: _fullPosBlue, width: 1.6),
          ),
          suffixIcon: searchController.text.trim().isNotEmpty
              ? IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: onClearSearch,
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              : null,
        ),
        onChanged: onSearchChanged,
      ),
    );

    final filterButton = SizedBox(
      height: 48,
      child: PopupMenuButton<_AccountStatusFilter>(
        tooltip: 'Filtros',
        initialValue: statusFilter,
        onSelected: onFilterChanged,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _AccountStatusFilter.all,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.select_all_rounded),
              title: Text('Todos'),
            ),
          ),
          PopupMenuItem(
            value: _AccountStatusFilter.pending,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.schedule_rounded),
              title: Text('Pendientes'),
            ),
          ),
          PopupMenuItem(
            value: _AccountStatusFilter.paid,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.check_circle_outline_rounded),
              title: Text('Pagados'),
            ),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: 6),
              Text(
                _filterLabel(statusFilter),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final searchRow = Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 10),
        filterButton,
        const SizedBox(width: 8),
        actionsMenu,
      ],
    );

    final summaryChildren = <Widget>[];
    for (var i = 0; i < summaryItems.length; i++) {
      if (i > 0) summaryChildren.add(const SizedBox(width: 8));
      summaryChildren.add(summaryBadge(summaryItems[i]));
    }
    final summaryRow = Row(children: summaryChildren);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, headerConstraints) {
          final stacked = headerConstraints.maxWidth < 820;

          if (stacked) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 820,
                child: Column(
                  children: [searchRow, const SizedBox(height: 10), summaryRow],
                ),
              ),
            );
          }

          return ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Column(
              children: [searchRow, const SizedBox(height: 10), summaryRow],
            ),
          );
        },
      ),
    );
  }
}

class _AccountsListCard extends StatelessWidget {
  const _AccountsListCard({
    required this.emptyTitle,
    required this.emptyMessage,
    required this.loading,
    required this.itemCount,
    required this.itemBuilder,
    required this.header,
  });

  final String emptyTitle;
  final String emptyMessage;
  final bool loading;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            if (itemCount > 0) ...[
              header,
              const SizedBox(height: 8),
            ],
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
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: itemCount,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: scheme.outlineVariant),
                          itemBuilder: itemBuilder,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountsListHeader extends StatelessWidget {
  const _AccountsListHeader({
    required this.firstColumn,
    required this.codeColumn,
    required this.dateColumn,
  });

  final String firstColumn;
  final String codeColumn;
  final String dateColumn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.70);

    Text label(String text, {TextAlign? align}) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: theme.textTheme.labelSmall?.copyWith(
          color: muted,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      height: 34,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: label(firstColumn)),
          const SizedBox(width: 14),
          Expanded(flex: 1, child: label('Teléfono')),
          const SizedBox(width: 8),
          Expanded(flex: 1, child: label(codeColumn)),
          const SizedBox(width: 8),
          Expanded(flex: 1, child: label(dateColumn)),
          const SizedBox(width: 8),
          SizedBox(width: 112, child: label('Total', align: TextAlign.right)),
          const SizedBox(width: 8),
          SizedBox(width: 112, child: label('Pendiente', align: TextAlign.right)),
          const SizedBox(width: 8),
          SizedBox(width: 86, child: label('Estado', align: TextAlign.center)),
          const SizedBox(width: 8),
          SizedBox(width: 28, child: label('', align: TextAlign.center)),
        ],
      ),
    );
  }
}

class _AccountTableRow extends StatelessWidget {
  const _AccountTableRow({
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.phone,
    required this.code,
    required this.date,
    required this.total,
    required this.pending,
    required this.statusLabel,
    required this.isPaid,
    required this.onTap,
    required this.menuItems,
    required this.onMenuSelected,
  });

  final bool isSelected;
  final IconData icon;
  final String title;
  final String phone;
  final String code;
  final String date;
  final String total;
  final String pending;
  final String statusLabel;
  final bool isPaid;
  final VoidCallback onTap;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.64);

    Text valueText(
      String text, {
      TextAlign? align,
      FontWeight fontWeight = FontWeight.w600,
      Color? color,
    }) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color ?? muted,
          fontWeight: fontWeight,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: _fullPosBlue.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _fullPosBlue.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? _fullPosBlue.withOpacity(0.62) : Colors.transparent,
              width: isSelected ? 1 : 0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? _fullPosBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 13,
                backgroundColor: _softBlue,
                foregroundColor: _fullPosBlue,
                child: Icon(icon, size: 15),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(flex: 1, child: valueText(phone)),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: valueText(
                  code,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface.withOpacity(0.72),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 1, child: valueText(date)),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: valueText(
                  total,
                  align: TextAlign.right,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: valueText(
                  pending,
                  align: TextAlign.right,
                  fontWeight: FontWeight.w800,
                  color: isPaid ? muted : _fullPosBlue,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 86,
                child: Align(
                  alignment: Alignment.center,
                  child: _StatusBadge(label: statusLabel, isPaid: isPaid),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                child: PopupMenuButton<String>(
                  tooltip: 'Acciones',
                  icon: Icon(Icons.more_vert_rounded, color: muted, size: 17),
                  padding: EdgeInsets.zero,
                  onSelected: onMenuSelected,
                  itemBuilder: (context) => menuItems,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditSideDetailsPanel extends StatelessWidget {
  const _CreditSideDetailsPanel({
    required this.sale,
    required this.formatCurrency,
    required this.formatDate,
    required this.onClose,
    required this.onRegisterPayment,
  });

  final Map<String, dynamic> sale;
  final String Function(double) formatCurrency;
  final String Function(int?) formatDate;
  final VoidCallback onClose;
  final VoidCallback onRegisterPayment;

  @override
  Widget build(BuildContext context) {
    final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
    final totalDue = (sale['total_due'] as num?)?.toDouble() ?? total;
    final pending = (((sale['amount_pending'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, double.infinity))
        .toDouble();
    final paid = (sale['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final interestRate =
        (sale['credit_interest_rate'] as num?)?.toDouble() ?? 0.0;
    final installments = sale['credit_installments'] as int?;
    final termDays = sale['credit_term_days'] as int?;
    final note = (sale['credit_note'] ?? '').toString().trim();

    return _AccountSideDetailsScaffold(
      title: 'Ficha del crédito',
      icon: Icons.receipt_long_outlined,
      label: 'Crédito seleccionado',
      headline: (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
      subheadline: (sale['local_code'] ?? 'N/A').toString(),
      isPaid: pending <= 0,
      onClose: onClose,
      actionLabel: 'Registrar abono',
      onAction: pending > 0 ? onRegisterPayment : null,
      children: [
        _DetailSectionTitle(title: 'Datos del cliente'),
        _InfoLine(
          icon: Icons.person_outline,
          label: 'Cliente',
          value: (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.phone_outlined,
          label: 'Teléfono',
          value: (sale['customer_phone_snapshot'] ?? '-').toString(),
        ),
        _DetailSectionTitle(title: 'Información del crédito'),
        _InfoLine(
          icon: Icons.receipt_long_outlined,
          label: 'Factura',
          value: (sale['local_code'] ?? 'N/A').toString(),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.calendar_month_outlined,
          label: 'Vencimiento',
          value: formatDate(sale['credit_due_date_ms'] as int?),
        ),
        if (termDays != null && termDays > 0) ...[
          const _CleanDivider(),
          _InfoLine(
            icon: Icons.timelapse_rounded,
            label: 'Plazo',
            value: '$termDays días',
          ),
        ],
        if (installments != null && installments > 0) ...[
          const _CleanDivider(),
          _InfoLine(
            icon: Icons.format_list_numbered_rounded,
            label: 'Cuotas',
            value: '$installments',
          ),
        ],
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.percent_rounded,
          label: 'Interés',
          value: '${interestRate.toStringAsFixed(2)}%',
        ),
        _DetailSectionTitle(title: 'Balance'),
        _InfoLine(
          icon: Icons.attach_money_rounded,
          label: 'Total venta',
          value: formatCurrency(total),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.request_quote_outlined,
          label: 'Total crédito',
          value: formatCurrency(totalDue),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.payments_outlined,
          label: 'Pagado',
          value: formatCurrency(paid),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Pendiente',
          value: formatCurrency(pending),
          strong: true,
        ),
        if (note.isNotEmpty) ...[
          _DetailSectionTitle(title: 'Nota'),
          _InfoNote(text: note),
        ],
      ],
    );
  }
}

class _LayawaySideDetailsPanel extends StatelessWidget {
  const _LayawaySideDetailsPanel({
    required this.sale,
    required this.formatCurrency,
    required this.onClose,
    required this.onRegisterPayment,
  });

  final Map<String, dynamic> sale;
  final String Function(double) formatCurrency;
  final VoidCallback onClose;
  final VoidCallback onRegisterPayment;

  @override
  Widget build(BuildContext context) {
    final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
    final pending = (((sale['amount_pending'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, double.infinity))
        .toDouble();
    final paid = (sale['amount_paid'] as num?)?.toDouble() ?? 0.0;

    return _AccountSideDetailsScaffold(
      title: 'Ficha del apartado',
      icon: Icons.bookmark_border_rounded,
      label: 'Apartado seleccionado',
      headline: (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
      subheadline: (sale['local_code'] ?? 'N/A').toString(),
      isPaid: pending <= 0,
      onClose: onClose,
      actionLabel: 'Registrar abono',
      onAction: pending > 0 ? onRegisterPayment : null,
      children: [
        _DetailSectionTitle(title: 'Datos del cliente'),
        _InfoLine(
          icon: Icons.person_outline,
          label: 'Cliente',
          value: (sale['customer_name_snapshot'] ?? 'Cliente').toString(),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.phone_outlined,
          label: 'Teléfono',
          value: (sale['customer_phone_snapshot'] ?? '-').toString(),
        ),
        _DetailSectionTitle(title: 'Información del apartado'),
        _InfoLine(
          icon: Icons.bookmark_border_rounded,
          label: 'Código',
          value: (sale['local_code'] ?? 'N/A').toString(),
        ),
        _DetailSectionTitle(title: 'Balance'),
        _InfoLine(
          icon: Icons.attach_money_rounded,
          label: 'Total',
          value: formatCurrency(total),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.payments_outlined,
          label: 'Pagado',
          value: formatCurrency(paid),
        ),
        const _CleanDivider(),
        _InfoLine(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Pendiente',
          value: formatCurrency(pending),
          strong: true,
        ),
      ],
    );
  }
}

class _AccountSideDetailsScaffold extends StatelessWidget {
  const _AccountSideDetailsScaffold({
    required this.title,
    required this.icon,
    required this.label,
    required this.headline,
    required this.subheadline,
    required this.isPaid,
    required this.onClose,
    required this.actionLabel,
    required this.onAction,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String label;
  final String headline;
  final String subheadline;
  final bool isPaid;
  final VoidCallback onClose;
  final String actionLabel;
  final VoidCallback? onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.62);
    final border = scheme.outlineVariant.withOpacity(0.85);

    Widget pill({
      required String text,
      required bool active,
      required IconData icon,
    }) {
      final color = active ? _fullPosBlue : scheme.onSurfaceVariant.withOpacity(0.85);

      return Expanded(
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? _softBlue : _softPanel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? const Color(0xFFBFD1F7) : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: border, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ocultar ficha',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: _softBlue,
                        foregroundColor: _fullPosBlue,
                        child: Icon(icon, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                headline,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subheadline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      pill(
                        text: isPaid ? 'Pagado' : 'Pendiente',
                        active: !isPaid,
                        icon: isPaid
                            ? Icons.check_circle_outline_rounded
                            : Icons.schedule_rounded,
                      ),
                      const SizedBox(width: 8),
                      pill(
                        text: isPaid ? 'Sin balance' : 'Con balance',
                        active: false,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ],
                  ),
                  ...children,
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(actionLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _fullPosBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: scheme.outlineVariant.withOpacity(0.5),
                        disabledForegroundColor: scheme.onSurface.withOpacity(0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSectionTitle extends StatelessWidget {
  const _DetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.62);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: _fullPosBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: strong ? _fullPosBlue : scheme.onSurface,
                    fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                    height: 1.18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CleanDivider extends StatelessWidget {
  const _CleanDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: scheme.outlineVariant.withOpacity(0.85),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.62);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _softPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.85)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: muted,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.isPaid,
  });

  final String label;
  final bool isPaid;

  @override
  Widget build(BuildContext context) {
    final bg = isPaid ? _paidGreenBg : _softBlue;
    final color = isPaid ? _paidGreen : _fullPosBlue;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isPaid ? _paidGreen.withOpacity(0.22) : _fullPosBlue.withOpacity(0.22),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: scheme.onSurface.withOpacity(0.32)),
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
    );
  }
}

class _TinyPaymentDialog extends StatelessWidget {
  const _TinyPaymentDialog({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentDialogInfo extends StatelessWidget {
  const _PaymentDialogInfo({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.62),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: highlighted ? _fullPosBlue : scheme.onSurface,
                fontWeight: highlighted ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
  });

  final String label;
  final String value;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
}
