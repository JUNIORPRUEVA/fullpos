// ignore_for_file: unused_element

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_gradient_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/printing/models/company_info.dart';
import '../../../core/printing/models/receipt_text_utils.dart';
import '../../../core/printing/models/ticket_layout_config.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authz/authz_service.dart';
import '../../../core/security/authz/permission.dart' as authz_perm;
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/data/sales_model.dart' show SaleModel, SaleItemModel;
import '../../settings/data/printer_settings_repository.dart';
import '../../settings/providers/theme_provider.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_summary_model.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/cashbox_daily_model.dart';
import '../data/operation_flow_service.dart';
import '../providers/cash_providers.dart';

enum _SelectionKind { refund, movement }

/// Diálogo para cerrar caja
class CashCloseDialog extends ConsumerStatefulWidget {
  final int sessionId;

  const CashCloseDialog({super.key, required this.sessionId});

  static Future<bool?> show(BuildContext context, {required int sessionId}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CashCloseDialog(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<CashCloseDialog> createState() => _CashCloseDialogState();
}

class _CashCloseDialogState extends ConsumerState<CashCloseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _closingAmountController = TextEditingController();
  final _noteController = TextEditingController();

  // Cache de formateadores/regex para evitar recrearlos en cada build.
  late final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  late final DateFormat _timeOnlyFormat = DateFormat('HH:mm');
  late final DateFormat _dateTimeShortFormat = DateFormat('dd/MM HH:mm');
  static final RegExp _ticketSanitizeRegExp = RegExp(
    r'''[^A-Za-z0-9\s\-_/.:,()#%+*&@'"'>$<]+''',
  );

  bool _isLoading = false;
  CashSummaryModel? _summary;
  bool _loadingSummary = true;
  CashSessionModel? _session;
  CashboxDailyModel? _cashboxDaily;
  bool _loadingSession = true;
  List<Map<String, dynamic>> _refunds = [];
  bool _loadingRefunds = true;
  int? _selectedRefundIndex;

  List<CashMovementModel> _movements = [];
  bool _loadingMovements = true;
  int? _selectedMovementIndex;
  _SelectionKind? _selectedKind;
  List<CategoryCashSummary> _categorySummary = [];
  List<RefundItemByCategory> _refundItemsByCategory = [];
  bool _loadingCategorySummary = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadSession();
    _loadRefunds();
    _loadMovements();
    _loadCategorySummary();
  }

  Future<void> _loadSession() async {
    try {
      final session = await CashRepository.getSessionById(widget.sessionId);
      final cashboxDaily = await OperationFlowService.getDailyCashboxById(
        session?.cashboxDailyId,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _cashboxDaily = cashboxDaily;
        _loadingSession = false;
      });
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
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loadingSummary = false;
        // El efectivo contado es opcional: no prellenar para que el usuario
        // pueda dejarlo vacío y usar el efectivo esperado.
        if (_closingAmountController.text.trim().isEmpty) {
          _closingAmountController.text = '';
        }
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingSummary = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadSummary,
        module: 'cash/summary',
      );
    }
  }

  Future<void> _loadRefunds() async {
    try {
      final refunds = await CashRepository.listRefundsForSession(
        widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _refunds = refunds;
        if (refunds.isEmpty) {
          _selectedRefundIndex = null;
          if (_selectedKind == _SelectionKind.refund) {
            _selectedKind = null;
          }
        } else {
          final current = _selectedRefundIndex;
          _selectedRefundIndex = (current != null && current < refunds.length)
              ? current
              : 0;

          // Si no hay selección, por defecto selecciona la primera devolución.
          _selectedKind ??= _SelectionKind.refund;
        }
        _loadingRefunds = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingRefunds = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadRefunds,
        module: 'cash/refunds',
      );
    }
  }

  Future<void> _loadMovements() async {
    try {
      final movements = await CashRepository.listMovements(
        sessionId: widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _movements = movements;
        if (movements.isEmpty) {
          _selectedMovementIndex = null;
          if (_selectedKind == _SelectionKind.movement) {
            _selectedKind = null;
          }
        } else {
          final current = _selectedMovementIndex;
          _selectedMovementIndex =
              (current != null && current < movements.length) ? current : 0;

          // Si no hay selección y no hay devoluciones, selecciona movimientos.
          _selectedKind ??= _SelectionKind.movement;
        }
        _loadingMovements = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingMovements = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadMovements,
        module: 'cash/movements',
      );
    }
  }

  Future<void> _loadCategorySummary() async {
    try {
      final results = await Future.wait([
        CashRepository.listCategorySummaryForSession(widget.sessionId),
        CashRepository.listRefundItemsByCategoryForSession(widget.sessionId),
      ]);
      final summary = results[0] as List<CategoryCashSummary>;
      final refundItems = results[1] as List<RefundItemByCategory>;
      if (!mounted) return;
      setState(() {
        _categorySummary = summary;
        _refundItemsByCategory = refundItems;
        _loadingCategorySummary = false;
      });
    } catch (e, st) {
      if (mounted) {
        setState(() => _loadingCategorySummary = false);
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _loadCategorySummary,
          module: 'cash/category_summary',
        );
      }
    }
  }

  @override
  void dispose() {
    _closingAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get _closingAmount {
    final raw = _closingAmountController.text.trim();
    final parsed = raw.isEmpty ? null : double.tryParse(raw);
    if (parsed != null) return parsed;
    // Si el usuario deja vacío (opcional), usar el efectivo esperado.
    return _summary?.expectedCash ?? 0.0;
  }

  double get _difference {
    if (_summary == null) return 0.0;
    return _closingAmount - _summary!.expectedCash;
  }

  Future<void> _closeCash() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await AuthzService.runGuardedCurrent<bool>(
      context,
      authz_perm.Permission.action(AppActions.closeShift),
      () async => true,
      reason: 'Cerrar turno',
      resourceType: 'cash_session',
      resourceId: widget.sessionId.toString(),
    );
    if (ok != true) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      await ref
          .read(cashSessionControllerProvider.notifier)
          .closeSession(
            sessionId: widget.sessionId,
            closingAmount: _closingAmount,
            note: _noteController.text.trim(),
          );

      // Imprimir ticket automáticamente al hacer el corte.
      // Importante: un fallo de impresión NO debe impedir que el corte se complete.
      try {
        final summaryForPrint =
            _summary ??
            await CashRepository.buildSummary(sessionId: widget.sessionId);

        await _printClosingTicket(
          summary: summaryForPrint,
          closingAmount: _closingAmount,
          note: _noteController.text.trim(),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Corte hecho, pero no se pudo imprimir: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }

      if (mounted) {
        final rootContext = Navigator.of(context, rootNavigator: true).context;
        final messenger = ScaffoldMessenger.of(rootContext);
        Navigator.of(context).pop(true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Corte de caja realizado correctamente'),
              backgroundColor: Theme.of(rootContext).colorScheme.primary,
            ),
          );
        });
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _closeCash,
          module: 'cash/close',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printClosingTicket({
    required CashSummaryModel summary,
    required double closingAmount,
    required String note,
  }) async {
    final session = await CashRepository.getSessionById(widget.sessionId);
    if (session == null) return;

    final sales = await SalesRepository.listSalesBySession(widget.sessionId);
    final saleItemsBySaleId = <int, List<SaleItemModel>>{};
    for (final sale in sales) {
      final saleId = sale.id;
      if (saleId == null) continue;
      saleItemsBySaleId[saleId] = await SalesRepository.getItemsBySaleId(
        saleId,
      );
    }
    final movements = await CashRepository.listMovements(
      sessionId: widget.sessionId,
    );
    final refunds = await CashRepository.listRefundsForSession(
      widget.sessionId,
    );
    final categorySummary = _categorySummary.isNotEmpty
        ? _categorySummary
        : await CashRepository.listCategorySummaryForSession(widget.sessionId);
    final refundItemsByCategory = _refundItemsByCategory.isNotEmpty
        ? _refundItemsByCategory
        : await CashRepository.listRefundItemsByCategoryForSession(
            widget.sessionId,
          );
    final settings = await PrinterSettingsRepository.getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final company = await CompanyInfoRepository.getCurrentCompanyInfo();

    final lines = _buildClosingTicketLines(
      layout: layout,
      companyName: company.name,
      companyRnc: company.rnc,
      companyPhone: company.primaryPhone,
      session: session,
      summary: summary,
      closingAmount: closingAmount,
      note: note,
      sales: sales,
      saleItemsBySaleId: saleItemsBySaleId,
      movements: movements,
      refunds: refunds,
      categorySummary: categorySummary,
      refundItemsByCategory: refundItemsByCategory,
      cashboxInitialAmount: _cashboxDaily?.initialAmount,
    );

    final result = await UnifiedTicketPrinter.printCustomLines(
      lines: lines,
      ticketNumber: 'CASH-${widget.sessionId}',
      includeLogo: true,
      overrideCopies: settings.copies,
    );

    if (!result.success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo imprimir el ticket: ${result.message}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  List<String> _buildClosingTicketLines({
    required TicketLayoutConfig layout,
    required String companyName,
    required String? companyRnc,
    required String? companyPhone,
    required CashSessionModel session,
    required CashSummaryModel summary,
    required double closingAmount,
    required String note,
    required List<SaleModel> sales,
    required Map<int, List<SaleItemModel>> saleItemsBySaleId,
    required List<CashMovementModel> movements,
    required List<Map<String, dynamic>> refunds,
    required List<CategoryCashSummary> categorySummary,
    required List<RefundItemByCategory> refundItemsByCategory,
    double? cashboxInitialAmount,
  }) {
    final w = layout.maxCharsPerLine;
    final lines = <String>[];
    final fmt = _dateTimeFormat;

    String sanitize(String text) => _sanitizeTicketText(text);
    String fit(String text) => ReceiptText.fitText(sanitize(text), w);
    String line() => ReceiptText.line(width: w);

    String center(String text) {
      final cleaned = sanitize(text);
      if (cleaned.length >= w) return cleaned.substring(0, w);
      final left = ((w - cleaned.length) / 2).floor();
      final right = w - cleaned.length - left;
      return ' ' * left + cleaned + ' ' * right;
    }

    String twoCols(String left, String right) {
      final rightWidth = 14.clamp(6, w - 2);
      final leftWidth = (w - rightWidth - 1).clamp(0, w);
      final leftText = ReceiptText.padRight(sanitize(left), leftWidth);
      final rightText = ReceiptText.padLeft(sanitize(right), rightWidth);
      return ReceiptText.fitText('$leftText $rightText', w);
    }

    String money(double value) => 'RD\$ ${ReceiptText.money(value)}';

    String fmtDuration(Duration d) {
      final totalMinutes = d.inMinutes;
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours <= 0) return '${minutes}m';
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }

    if (companyName.trim().isNotEmpty) {
      lines.add('<H2C>${sanitize(companyName)}');
    }
    final headerParts = <String>[];
    if ((companyRnc ?? '').trim().isNotEmpty) {
      headerParts.add('RNC: ${companyRnc!.trim()}');
    }
    if ((companyPhone ?? '').trim().isNotEmpty) {
      headerParts.add('TEL: ${companyPhone!.trim()}');
    }
    if (headerParts.isNotEmpty) {
      lines.add(center(headerParts.join('  ')));
    }

    lines.add(line());
    lines.add('<H2C>CORTE DE CAJA');
    lines.add(line());
    lines.add('<BL>${twoCols('Sesion', '#${session.id ?? ''}')}');
    lines.add('<BL>${twoCols('Cajero', session.userName)}');
    lines.add('<BL>${twoCols('Apertura', fmt.format(session.openedAt))}');
    if (session.closedAt != null) {
      lines.add('<BL>${twoCols('Cierre', fmt.format(session.closedAt!))}');
    }
    final end = session.closedAt ?? DateTime.now();
    final duration = end.difference(session.openedAt);
    if (duration.inMinutes >= 1) {
      lines.add('<BL>${twoCols('Duracion', fmtDuration(duration))}');
    }
    lines.add(line());

    if (cashboxInitialAmount != null) {
      lines.add('<BL>${twoCols('Apertura caja', money(cashboxInitialAmount))}');
    }
    lines.add('<BL>${twoCols('Apertura turno', money(summary.openingAmount))}');
    lines.add(
      '<BL>${twoCols('Ventas efectivo', money(summary.salesCashTotal))}',
    );
    lines.add(
      '<BL>${twoCols('Ventas tarjeta', money(summary.salesCardTotal))}',
    );
    lines.add(
      '<BL>${twoCols('Ventas transferencia', money(summary.salesTransferTotal))}',
    );
    lines.add(
      '<BL>${twoCols('Ventas credito', money(summary.salesCreditTotal))}',
    );
    if (summary.refundsCash > 0) {
      lines.add('<BL>${twoCols('Devoluciones', money(summary.refundsCash))}');
    }
    if (summary.creditAbonos > 0) {
      lines.add(
        '<BL>${twoCols('Abonos crédito', money(summary.creditAbonos))}',
      );
    }
    if (summary.layawayAbonos > 0) {
      lines.add(
        '<BL>${twoCols('Abonos apartado', money(summary.layawayAbonos))}',
      );
    }
    final manualNoAbonos =
        (summary.cashInManual - summary.creditAbonos - summary.layawayAbonos)
            .clamp(0.0, double.infinity);
    lines.add('<BL>${twoCols('Entradas manuales', money(manualNoAbonos))}');
    lines.add(
      '<BL>${twoCols('Retiros manuales', money(summary.cashOutManual))}',
    );
    lines.add(line());
    lines.add(
      '<BL>${twoCols('Efectivo esperado', money(summary.expectedCash))}',
    );
    lines.add('<BL>${twoCols('Efectivo contado', money(closingAmount))}');
    lines.add(
      '<BL>${twoCols('Diferencia', money(closingAmount - summary.expectedCash))}',
    );
    lines.add(line());

    if (note.trim().isNotEmpty) {
      lines.add(fit('Nota:'));
      final wrapped = ReceiptText.wrapText(
        sanitize(note.trim()),
        (w - 2).clamp(1, w),
      );
      for (final lineText in wrapped) {
        lines.add(fit('  $lineText'));
      }
      lines.add(line());
    }

    lines.add('<H2C>MOVIMIENTOS DEL TURNO');
    lines.add(line());
    if (movements.isEmpty) {
      lines.add(center('Sin movimientos'));
    } else {
      final timeFmt = _timeOnlyFormat;
      for (final m in movements) {
        final sign = m.isIn ? '+' : '-';
        final right = '$sign${money(m.amount)}';
        final left = '${timeFmt.format(m.createdAt)} ${m.reason}';
        lines.add(twoCols(left, right));
      }
      lines.add(line());
      lines.add(
        '<BL>${twoCols('Total entradas', money(summary.cashInManual))}',
      );
      lines.add(
        '<BL>${twoCols('Total retiros', money(summary.cashOutManual))}',
      );
    }

    String methodAbbr(String? method) {
      final m = (method ?? '').trim().toLowerCase();
      switch (m) {
        case 'cash':
        case 'efectivo':
          return 'EFE';
        case 'card':
        case 'tarjeta':
          return 'TAR';
        case 'transfer':
        case 'transferencia':
          return 'TRF';
        case 'credit':
        case 'credito':
          return 'CRE';
        case 'mixed':
        case 'mixto':
          return 'MIX';
        default:
          if (m.isEmpty) return '---';
          final up = sanitize(m.toUpperCase());
          return up.substring(0, math.min(3, up.length));
      }
    }

    String saleRow({
      required String time,
      required String name,
      required String method,
      required String total,
    }) {
      // Formato: HH:mm  NOMBRE...............  MET  RD$ 000.00
      final timeWidth = 5;
      final methodWidth = 3;
      final int totalWidth = (14).clamp(10, w - 10).toInt();
      final int nameWidth = (w - timeWidth - methodWidth - totalWidth - 3)
          .clamp(8, w)
          .toInt();

      final t = ReceiptText.padRight(sanitize(time), timeWidth);
      final c = ReceiptText.padRight(sanitize(name), nameWidth);
      final m = ReceiptText.padRight(sanitize(method), methodWidth);
      final a = ReceiptText.padLeft(sanitize(total), totalWidth);
      return ReceiptText.fitText('$t $c $m $a', w);
    }

    void addRefundsSection() {
      if (refunds.isEmpty) return;
      lines.add('<H2C>DEVOLUCIONES');
      lines.add(line());
      final timeFmt = _timeOnlyFormat;
      for (final refund in refunds) {
        final when = DateTime.fromMillisecondsSinceEpoch(
          refund['created_at_ms'] as int,
        );
        const previewLimit = 3;
        final productsPreview =
            (refund['products_preview'] as String?)?.trim() ?? '';
        final firstProductName =
            (refund['first_product_name'] as String?)?.trim() ?? '';
        final itemCount = (refund['item_count'] as int?) ?? 0;
        final amount = (refund['total'] as num?)?.toDouble().abs() ?? 0.0;
        final reason = (refund['note'] as String?)?.trim() ?? '';
        final customerName = (refund['customer_name'] as String?)?.trim() ?? '';
        final customerPhone =
            (refund['customer_phone'] as String?)?.trim() ?? '';
        final customerRnc = (refund['customer_rnc'] as String?)?.trim() ?? '';
        final originalNcf = (refund['original_ncf'] as String?)?.trim() ?? '';

        final productLabel = productsPreview.isNotEmpty
            ? productsPreview
            : (firstProductName.isNotEmpty ? firstProductName : 'Devolución');
        final remaining = productsPreview.isNotEmpty
            ? (itemCount - previewLimit)
            : (itemCount - 1);
        final suffix = remaining > 0 ? ' (+$remaining)' : '';
        final left = '${timeFmt.format(when)} $productLabel$suffix';
        lines.add(twoCols(left, money(amount)));

        final customerParts = [
          if (customerName.isNotEmpty) customerName,
          if (customerPhone.isNotEmpty) customerPhone,
          if (customerRnc.isNotEmpty) customerRnc,
        ];
        if (customerParts.isNotEmpty) {
          final wrapped = ReceiptText.wrapText(
            sanitize('Cliente: ${customerParts.join(' / ')}'),
            (w - 4).clamp(6, w),
          );
          for (final r in wrapped.take(2)) {
            lines.add(fit('  * $r'));
          }
        }
        if (originalNcf.isNotEmpty) {
          final wrapped = ReceiptText.wrapText(
            sanitize('NCF: $originalNcf'),
            (w - 4).clamp(6, w),
          );
          for (final r in wrapped.take(2)) {
            lines.add(fit('  * $r'));
          }
        }

        if (reason.isNotEmpty) {
          final wrapped = ReceiptText.wrapText(
            sanitize(reason),
            (w - 4).clamp(6, w),
          );
          for (final r in wrapped.take(3)) {
            lines.add(fit('  • $r'));
          }
        }
      }
      lines.add(line());
    }

    lines.add('<H2C>VENTAS DEL TURNO');
    lines.add(line());
    if (sales.isEmpty) {
      lines.add(center('Sin ventas registradas'));
    } else {
      final sorted = [...sales]
        ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));

      lines.add(
        '<BL>${saleRow(time: 'HORA', name: 'PRODUCTO', method: 'MET', total: 'TOTAL')}',
      );
      lines.add(ReceiptText.line(char: '=', width: w));

      final timeFmt = _timeOnlyFormat;
      for (final sale in sorted) {
        final when = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
        final items = saleItemsBySaleId[sale.id ?? -1];
        final firstItemName = (items != null && items.isNotEmpty)
            ? items.first.productNameSnapshot.trim()
            : '';
        final customerName = (sale.customerNameSnapshot ?? '').trim();
        final displayName = firstItemName.isNotEmpty
            ? firstItemName
            : customerName;
        lines.add(
          saleRow(
            time: timeFmt.format(when),
            name: displayName.isNotEmpty ? displayName : 'Venta',
            method: methodAbbr(sale.paymentMethod),
            total: money(sale.total),
          ),
        );
      }
    }
    lines.add(line());

    addRefundsSection();

    if (categorySummary.isNotEmpty) {
      final refundMap = <String, List<RefundItemByCategory>>{};
      for (final item in refundItemsByCategory) {
        refundMap.putIfAbsent(item.category, () => []).add(item);
      }

      String qtyText(double qty) {
        final isWhole = (qty - qty.roundToDouble()).abs() < 0.001;
        return isWhole ? qty.toInt().toString() : qty.toStringAsFixed(2);
      }

      lines.add('<H2C>CIERRE POR CATEGORIA');
      lines.add(line());
      for (final cat in categorySummary) {
        lines.add(fit(cat.category));
        lines.add(twoCols('Ventas', money(cat.salesTotal)));
        if (cat.refundTotal > 0) {
          lines.add(twoCols('Devoluciones', money(cat.refundTotal)));
        }
        lines.add(twoCols('Neto', money(cat.netTotal)));
        lines.add(twoCols('Items vendidos', qtyText(cat.itemsSold)));
        if (cat.itemsRefunded > 0) {
          lines.add(twoCols('Items devueltos', qtyText(cat.itemsRefunded)));
        }

        final refundItems = refundMap[cat.category];
        if (refundItems != null && refundItems.isNotEmpty) {
          lines.add(fit('Reembolsos:'));
          for (final item in refundItems) {
            final label = '${item.productName} x${qtyText(item.qty)}';
            lines.add(twoCols('  $label', money(item.total.abs())));
          }
        }
        lines.add(line());
      }
    }

    // Totales grandes (más legibles)
    lines.add('<H2C>TOTALES');
    lines.add(line());
    lines.add('<BL>${twoCols('Tickets', summary.totalTickets.toString())}');
    lines.add('<BL>${twoCols('Total ventas', money(summary.totalSales))}');
    lines.add('');
    lines.add('<H2C>TOTAL VENTAS');
    lines.add('<H1C>${money(summary.totalSales)}');
    lines.add('');
    lines.add('<H2C>EFECTIVO ESPERADO');
    lines.add('<H1C>${money(summary.expectedCash)}');
    lines.add('');
    lines.add('<H2C>EFECTIVO CONTADO');
    lines.add('<H1C>${money(closingAmount)}');
    lines.add('');
    lines.add('<H2C>DIFERENCIA');
    lines.add('<H1C>${money(closingAmount - summary.expectedCash)}');

    lines.add(line());
    lines.add(fit('Firma cajero: _______________________'));

    if (layout.autoCut) {
      lines.add('');
      lines.add('');
      lines.add('');
    }

    // Importante: no volver a aplicar fitText aquí porque algunas líneas usan tags
    // como <H1C> / <H2C> (no cuentan como caracteres imprimibles).
    return lines;
  }

  String _sanitizeTicketText(String input) {
    final s = input
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C');

    final filtered = s.replaceAll(_ticketSanitizeRegExp, '');
    return filtered.trim();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(themeProvider);
    final viewInsets = MediaQuery.of(context).viewInsets;
    const targetWidth = 980.0;
    const targetHeight = 740.0;
    final safeWidth = (screenSize.width - 32).clamp(360.0, 1600.0);
    final safeHeight = (screenSize.height - viewInsets.vertical - 32).clamp(
      560.0,
      1200.0,
    );
    final dialogWidth = targetWidth.clamp(360.0, safeWidth);
    final dialogHeight = targetHeight.clamp(560.0, safeHeight);
    final outerPad = (math.min(dialogWidth, dialogHeight) * 0.03).clamp(
      16.0,
      26.0,
    );

    final gradientTheme = theme.extension<AppGradientTheme>();
    final headerGradient =
        gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [scheme.error, scheme.errorContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    final headerText = ColorUtils.ensureReadableColor(
      scheme.onError,
      scheme.errorContainer,
    );
    Color readableOn(Color bg) => ColorUtils.readableTextColor(bg);

    return DialogKeyboardShortcuts(
      onSubmit: _isLoading ? null : _closeCash,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: (screenSize.width * 0.05).clamp(16.0, 56.0),
          vertical: (screenSize.height * 0.05).clamp(16.0, 56.0),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: dialogHeight,
            minWidth: math.min(360.0, dialogWidth),
            minHeight: math.min(560.0, dialogHeight),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withOpacity(0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
                  decoration: BoxDecoration(gradient: headerGradient),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: headerText.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: headerText.withOpacity(0.18),
                          ),
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          color: headerText,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Corte de caja',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: headerText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Cerrar turno, revisar resumen e imprimir comprobante',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: headerText.withOpacity(0.82),
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: headerText),
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.all(outerPad),
                    child: _loadingSummary
                        ? Center(
                            child: CircularProgressIndicator(
                              color: scheme.error,
                            ),
                          )
                        : Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Info del turno
                                Builder(
                                  builder: (context) {
                                    if (_loadingSession) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: Text(
                                          'Cargando información del turno…',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurface
                                                    .withOpacity(0.65),
                                              ),
                                        ),
                                      );
                                    }

                                    final s = _session;
                                    if (s == null) {
                                      return const SizedBox(height: 0);
                                    }

                                    final end = s.closedAt ?? DateTime.now();
                                    final duration = end.difference(s.openedAt);
                                    final fmt = _dateTimeFormat;

                                    return Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: scheme.outlineVariant
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Cajero: ${s.userName}',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Apertura: ${fmt.format(s.openedAt)}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.onSurface
                                                      .withOpacity(0.7),
                                                ),
                                          ),
                                          Text(
                                            'Tiempo con caja abierta: ${_formatDuration(duration)}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.onSurface
                                                      .withOpacity(0.7),
                                                ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isWide =
                                          constraints.maxWidth >= 860;
                                      final gap = (outerPad * 0.65).clamp(
                                        12.0,
                                        18.0,
                                      );

                                      final summary = _buildSummarySection(
                                        fontFamily: settings.fontFamily,
                                      );
                                      final closing = _buildClosingSection(
                                        fontFamily: settings.fontFamily,
                                      );

                                      if (!isWide) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            summary,
                                            SizedBox(height: gap),
                                            closing,
                                          ],
                                        );
                                      }

                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(flex: 6, child: summary),
                                          SizedBox(width: gap),
                                          Expanded(flex: 5, child: closing),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceVariant.withOpacity(0.25),
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withOpacity(0.55),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.onSurface,
                            side: BorderSide(color: scheme.outlineVariant),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _closeCash,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: readableOn(scheme.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isLoading
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      readableOn(scheme.error),
                                    ),
                                  ),
                                )
                              : const Icon(Icons.lock, size: 18),
                          label: const Text(
                            'Hacer corte',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummarySection({String? fontFamily}) {
    if (_summary == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = _summary!;
    final bg = scheme.surfaceContainerHighest;
    final fg = ColorUtils.ensureReadableColor(scheme.onSurface, bg);
    final titleColor = ColorUtils.ensureReadableColor(scheme.primary, bg);

    Widget row(String label, double value, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg.withOpacity(0.72),
                  fontWeight: FontWeight.w600,
                  fontFamily: fontFamily,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'RD\$ ${value.toStringAsFixed(2)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color ?? fg,
                fontWeight: FontWeight.w800,
                fontFamily: fontFamily,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESUMEN',
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: titleColor,
              fontFamily: fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          row('Apertura turno', summary.openingAmount, color: fg),
          row('Ventas efectivo', summary.salesCashTotal, color: fg),
          row('Entradas manuales', summary.cashInManual, color: fg),
          row('Retiros manuales', summary.cashOutManual, color: scheme.error),
          if (summary.refundsCash > 0)
            row('Devoluciones', summary.refundsCash, color: scheme.error),
          const Divider(height: 14),
          row(
            'Efectivo esperado',
            summary.expectedCash,
            color: ColorUtils.ensureReadableColor(scheme.primary, bg),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatChip(
                '${summary.totalTickets}',
                'Tickets',
                scheme.primary,
                fg: fg,
                fontFamily: fontFamily,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                'RD\$ ${summary.totalSales.toStringAsFixed(2)}',
                'Total ventas',
                scheme.secondary,
                fg: fg,
                fontFamily: fontFamily,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRefundsSection({String? fontFamily}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bg = scheme.surfaceContainerHighest;
    final fg = ColorUtils.ensureReadableColor(scheme.onSurface, bg);
    final accent = ColorUtils.ensureReadableColor(scheme.error, bg);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DEVOLUCIONES DEL TURNO',
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
              if (!_loadingRefunds)
                Text(
                  '${_refunds.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                    fontFamily: fontFamily,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingRefunds)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: accent),
              ),
            )
          else if (_refunds.isEmpty)
            Text(
              'No hay devoluciones registradas en este turno.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg.withOpacity(0.7),
                fontFamily: fontFamily,
              ),
            )
          else
            _buildRefundsList(
              bg: bg,
              fg: fg,
              accent: accent,
              fontFamily: fontFamily,
            ),
        ],
      ),
    );
  }

  Widget _buildMovementsSection({String? fontFamily}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bg = scheme.surfaceContainerHighest;
    final fg = ColorUtils.ensureReadableColor(scheme.onSurface, bg);
    final accent = ColorUtils.ensureReadableColor(scheme.primary, bg);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MOVIMIENTOS DEL TURNO',
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
              if (!_loadingMovements)
                Text(
                  '${_movements.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                    fontFamily: fontFamily,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingMovements)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: accent),
              ),
            )
          else if (_movements.isEmpty)
            Text(
              'No hay movimientos (entradas/retiros) en este turno.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg.withOpacity(0.7),
                fontFamily: fontFamily,
              ),
            )
          else
            _buildMovementsList(
              bg: bg,
              fg: fg,
              accent: accent,
              fontFamily: fontFamily,
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySummarySection({String? fontFamily}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final bg = scheme.surfaceContainerHighest;
    final fg = ColorUtils.ensureReadableColor(scheme.onSurface, bg);
    final accent = ColorUtils.ensureReadableColor(scheme.primary, bg);

    if (_loadingCategorySummary) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'CIERRE POR CATEGORIA',
                style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  fontFamily: fontFamily,
                ),
              ),
            ),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
          ],
        ),
      );
    }

    if (_categorySummary.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        child: Text(
          'No hay datos por categoria en este turno.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: fg.withOpacity(0.7),
            fontFamily: fontFamily,
          ),
        ),
      );
    }

    final refundMap = <String, List<RefundItemByCategory>>{};
    for (final item in _refundItemsByCategory) {
      refundMap.putIfAbsent(item.category, () => []).add(item);
    }

    String qtyText(double qty) {
      final isWhole = (qty - qty.roundToDouble()).abs() < 0.001;
      return isWhole ? qty.toInt().toString() : qty.toStringAsFixed(2);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CIERRE POR CATEGORIA',
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: accent,
              fontFamily: fontFamily,
            ),
          ),
          const SizedBox(height: 10),
          ..._categorySummary.map((cat) {
            final refunds = refundMap[cat.category] ?? const [];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat.category,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontFamily: fontFamily,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildCategoryRow(
                    label: 'Ventas',
                    value: currency.format(cat.salesTotal),
                    color: fg,
                    fontFamily: fontFamily,
                  ),
                  _buildCategoryRow(
                    label: 'Devoluciones',
                    value: currency.format(cat.refundTotal),
                    color: fg,
                    fontFamily: fontFamily,
                  ),
                  _buildCategoryRow(
                    label: 'Neto',
                    value: currency.format(cat.netTotal),
                    color: accent,
                    fontFamily: fontFamily,
                    bold: true,
                  ),
                  _buildCategoryRow(
                    label: 'Items vendidos',
                    value: qtyText(cat.itemsSold),
                    color: fg,
                    fontFamily: fontFamily,
                  ),
                  if (cat.itemsRefunded > 0)
                    _buildCategoryRow(
                      label: 'Items devueltos',
                      value: qtyText(cat.itemsRefunded),
                      color: fg,
                      fontFamily: fontFamily,
                    ),
                  if (refunds.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Reembolsos:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: fg.withOpacity(0.75),
                        fontWeight: FontWeight.w700,
                        fontFamily: fontFamily,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...refunds.map(
                      (item) => _buildCategoryRow(
                        label: '${item.productName} x${qtyText(item.qty)}',
                        value: currency.format(item.total.abs()),
                        color: fg.withOpacity(0.9),
                        fontFamily: fontFamily,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryRow({
    required String label,
    required String value,
    required Color color,
    String? fontFamily,
    bool bold = false,
  }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: color,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      fontFamily: fontFamily,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textStyle)),
          Text(value, style: textStyle),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(
    String label,
    double amount,
    Color color,
    double width,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurface.withOpacity(0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    String value,
    String label,
    Color color, {
    Color? fg,
    String? fontFamily,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: fontFamily,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: (fg ?? color).withOpacity(0.7),
              fontSize: 10,
              fontFamily: fontFamily,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingSection({String? fontFamily}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diffColor = _difference == 0
        ? scheme.primary
        : (_difference > 0 ? scheme.tertiary : scheme.error);
    final diffBg = diffColor.withOpacity(0.12);
    final diffBorder = diffColor.withOpacity(0.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CORTE',
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 1,
            fontWeight: FontWeight.bold,
            color: scheme.primary,
            fontFamily: fontFamily,
          ),
        ),
        const SizedBox(height: 10),

        // Efectivo contado (opcional)
        Text(
          'Efectivo contado (opcional)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _closingAmountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: theme.textTheme.titleMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
            hintText: 'Opcional',
            helperText: null,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: scheme.primary, width: 1),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final amount = double.tryParse(value.trim());
            if (amount == null || amount < 0) return 'Monto inválido';
            return null;
          },
        ),
        const SizedBox(height: 10),

        // Diferencia
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: diffBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: diffBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Diferencia:',
                style: TextStyle(
                  color: scheme.onSurface.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              Text(
                '${_difference >= 0 ? '+' : ''}\$${_difference.toStringAsFixed(2)}',
                style: TextStyle(
                  color: diffColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Nota
        Text(
          'Nota del cierre',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _noteController,
          maxLines: 2,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Observaciones del cierre...',
            hintStyle: TextStyle(color: scheme.onSurface.withOpacity(0.5)),
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  void _selectKind(_SelectionKind kind) {
    setState(() {
      _selectedKind = kind;
      if (kind == _SelectionKind.refund) {
        if (_refunds.isNotEmpty) {
          _selectedRefundIndex ??= 0;
          if (_selectedRefundIndex! >= _refunds.length) {
            _selectedRefundIndex = 0;
          }
        } else {
          _selectedRefundIndex = null;
        }
      } else {
        if (_movements.isNotEmpty) {
          _selectedMovementIndex ??= 0;
          if (_selectedMovementIndex! >= _movements.length) {
            _selectedMovementIndex = 0;
          }
        } else {
          _selectedMovementIndex = null;
        }
      }
    });
  }

  Widget _buildDetailSegmentedToggle({
    required Color bg,
    required Color fg,
    String? fontFamily,
  }) {
    final scheme = Theme.of(context).colorScheme;

    final hasRefunds = _refunds.isNotEmpty;
    final hasMovements = _movements.isNotEmpty;
    if (!(hasRefunds && hasMovements)) return const SizedBox.shrink();

    final current = _selectedKind ?? _SelectionKind.refund;
    final trackBg = Color.alphaBlend(scheme.surface.withOpacity(0.65), bg);
    final border = scheme.outlineVariant.withOpacity(0.35);

    Widget seg({
      required _SelectionKind kind,
      required String label,
      required IconData icon,
    }) {
      final selected = current == kind;
      final selBg = Color.alphaBlend(scheme.primary.withOpacity(0.18), bg);
      final selBorder = scheme.primary.withOpacity(0.45);
      final segBg = selected ? selBg : Colors.transparent;
      final segBorder = selected ? selBorder : Colors.transparent;
      final segFg = selected
          ? ColorUtils.ensureReadableColor(scheme.primary, segBg)
          : fg.withOpacity(0.85);

      return Expanded(
        child: InkWell(
          onTap: () => _selectKind(kind),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: segBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: segBorder, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: segFg),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: segFg,
                    fontWeight: FontWeight.w800,
                    fontFamily: fontFamily,
                    letterSpacing: 0.2,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        children: [
          seg(
            kind: _SelectionKind.refund,
            label: 'Devoluciones',
            icon: Icons.receipt_long,
          ),
          const SizedBox(width: 6),
          seg(
            kind: _SelectionKind.movement,
            label: 'Movimientos',
            icon: Icons.swap_horiz,
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? get _selectedRefund {
    if (_selectedKind != _SelectionKind.refund) return null;
    final idx = _selectedRefundIndex;
    if (idx == null) return null;
    if (idx < 0 || idx >= _refunds.length) return null;
    return _refunds[idx];
  }

  CashMovementModel? get _selectedMovement {
    if (_selectedKind != _SelectionKind.movement) return null;
    final idx = _selectedMovementIndex;
    if (idx == null) return null;
    if (idx < 0 || idx >= _movements.length) return null;
    return _movements[idx];
  }

  Widget _buildRefundsList({
    required Color bg,
    required Color fg,
    required Color accent,
    String? fontFamily,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final dateFormat = _dateTimeShortFormat;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _refunds.length,
      separatorBuilder: (_, index) => Divider(
        height: 10,
        thickness: 1,
        color: scheme.outlineVariant.withOpacity(0.35),
      ),
      itemBuilder: (context, index) {
        final refund = _refunds[index];
        final selected =
            _selectedKind == _SelectionKind.refund &&
            _selectedRefundIndex == index;

        final amount = (refund['total'] as num?)?.toDouble().abs() ?? 0.0;
        const previewLimit = 3;
        final productsPreview =
            (refund['products_preview'] as String?)?.trim() ?? '';
        final firstProductName =
            (refund['first_product_name'] as String?)?.trim() ?? '';
        final itemCount = (refund['item_count'] as int?) ?? 0;
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          refund['created_at_ms'] as int,
        );
        final returnCode = (refund['return_code'] as String?)?.trim() ?? '';

        final productLabel = productsPreview.isNotEmpty
            ? productsPreview
            : (firstProductName.isNotEmpty ? firstProductName : 'Devolución');
        final remaining = productsPreview.isNotEmpty
            ? (itemCount - previewLimit)
            : (itemCount - 1);
        final suffix = remaining > 0 ? ' (+$remaining)' : '';

        final tileBg = selected
            ? Color.alphaBlend(scheme.primary.withOpacity(0.14), bg)
            : bg;
        final tileBorder = selected
            ? scheme.primary.withOpacity(0.55)
            : scheme.outlineVariant.withOpacity(0.25);
        final tileFg = ColorUtils.ensureReadableColor(fg, tileBg);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedKind = _SelectionKind.refund;
                _selectedRefundIndex = index;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tileBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$productLabel$suffix',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tileFg,
                              fontWeight: FontWeight.w800,
                              fontFamily: fontFamily,
                              height: 1.05,
                            ),
                          ),
                          TextSpan(
                            text: '  •  ${dateFormat.format(createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tileFg.withOpacity(0.75),
                              fontFamily: fontFamily,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                            ),
                          ),
                          if (returnCode.isNotEmpty)
                            TextSpan(
                              text: '  •  Ref: $returnCode',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tileFg.withOpacity(0.75),
                                fontFamily: fontFamily,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withOpacity(0.18)),
                    ),
                    child: Text(
                      currency.format(amount),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        fontFamily: fontFamily,
                        letterSpacing: 0.2,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMovementsList({
    required Color bg,
    required Color fg,
    required Color accent,
    String? fontFamily,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final timeFormat = _dateTimeShortFormat;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _movements.length,
      separatorBuilder: (_, index) => Divider(
        height: 10,
        thickness: 1,
        color: scheme.outlineVariant.withOpacity(0.35),
      ),
      itemBuilder: (context, index) {
        final m = _movements[index];
        final selected =
            _selectedKind == _SelectionKind.movement &&
            _selectedMovementIndex == index;

        final movementColor = m.isIn
            ? (scheme.tertiary)
            : ColorUtils.ensureReadableColor(scheme.error, bg);

        final tileBg = selected
            ? Color.alphaBlend(scheme.primary.withOpacity(0.14), bg)
            : bg;
        final tileBorder = selected
            ? scheme.primary.withOpacity(0.55)
            : scheme.outlineVariant.withOpacity(0.25);
        final tileFg = ColorUtils.ensureReadableColor(fg, tileBg);

        final sign = m.isIn ? '+' : '-';
        final amountText = '$sign${currency.format(m.amount)}';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedKind = _SelectionKind.movement;
                _selectedMovementIndex = index;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tileBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: movementColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: (m.reason.trim().isEmpty
                                ? 'Movimiento'
                                : m.reason.trim()),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tileFg,
                              fontWeight: FontWeight.w800,
                              fontFamily: fontFamily,
                              height: 1.05,
                            ),
                          ),
                          TextSpan(
                            text: '  •  ${timeFormat.format(m.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tileFg.withOpacity(0.75),
                              fontFamily: fontFamily,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: movementColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: movementColor.withOpacity(0.18),
                      ),
                    ),
                    child: Text(
                      amountText,
                      style: TextStyle(
                        color: movementColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        fontFamily: fontFamily,
                        letterSpacing: 0.2,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectionDetailsPanel({String? fontFamily}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _selectedRefund;
    final selectedMovement = _selectedMovement;

    final bg = scheme.surfaceContainerHighest;
    final fg = ColorUtils.ensureReadableColor(scheme.onSurface, bg);
    final accent = ColorUtils.ensureReadableColor(scheme.error, bg);

    if (selected == null && selectedMovement == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DETALLE',
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
                color: fg,
                fontFamily: fontFamily,
              ),
            ),
            const SizedBox(height: 10),
            _buildDetailSegmentedToggle(bg: bg, fg: fg, fontFamily: fontFamily),
            const SizedBox(height: 10),
            Text(
              'Selecciona una devolución o movimiento para ver el detalle aquí.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg.withOpacity(0.7),
                fontFamily: fontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (selectedMovement != null) {
      final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
      final dateFormat = _dateTimeFormat;
      final m = selectedMovement;

      final movementColor = m.isIn
          ? scheme.tertiary
          : ColorUtils.ensureReadableColor(scheme.error, bg);
      final sign = m.isIn ? '+' : '-';

      Widget kv(String k, String v) {
        if (v.trim().isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  k,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fg.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  v,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailSegmentedToggle(bg: bg, fg: fg, fontFamily: fontFamily),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: movementColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: movementColor.withOpacity(0.18)),
                  ),
                  child: Icon(
                    m.isIn
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: movementColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'DETALLE DE MOVIMIENTO',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w900,
                      color: fg,
                      fontFamily: fontFamily,
                    ),
                  ),
                ),
                Text(
                  '$sign${currency.format(m.amount)}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: movementColor,
                    fontWeight: FontWeight.w900,
                    fontFamily: fontFamily,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            kv('Fecha', dateFormat.format(m.createdAt)),
            kv('Tipo', m.isIn ? 'Entrada' : 'Retiro'),
            kv('Motivo', m.reason),
            kv('Usuario ID', m.userId.toString()),
          ],
        ),
      );
    }

    final selectedRefund = selected;
    if (selectedRefund == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        child: Text(
          'Selecciona una devolución o movimiento para ver el detalle aquí.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: fg.withOpacity(0.7),
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final dateFormat = _dateTimeFormat;
    final amount = (selectedRefund['total'] as num?)?.toDouble().abs() ?? 0.0;
    final note = (selectedRefund['note'] as String?)?.trim() ?? '';
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      selectedRefund['created_at_ms'] as int,
    );
    final returnCode = (selectedRefund['return_code'] as String?)?.trim() ?? '';
    final originalCode =
        (selectedRefund['original_code'] as String?)?.trim() ?? '';
    final originalNcf =
        (selectedRefund['original_ncf'] as String?)?.trim() ?? '';
    final itemCount = (selectedRefund['item_count'] as int?) ?? 0;
    final productsPreview =
        (selectedRefund['products_preview'] as String?)?.trim() ?? '';
    final firstProductName =
        (selectedRefund['first_product_name'] as String?)?.trim() ?? '';
    final customerName =
        (selectedRefund['customer_name'] as String?)?.trim() ?? '';
    final customerPhone =
        (selectedRefund['customer_phone'] as String?)?.trim() ?? '';
    final customerRnc =
        (selectedRefund['customer_rnc'] as String?)?.trim() ?? '';

    final productLabel = productsPreview.isNotEmpty
        ? productsPreview
        : (firstProductName.isNotEmpty ? firstProductName : 'Devolución');

    Widget kv(String k, String v) {
      if (v.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(
                k,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg.withOpacity(0.7),
                  fontWeight: FontWeight.w700,
                  fontFamily: fontFamily,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontFamily: fontFamily,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailSegmentedToggle(bg: bg, fg: fg, fontFamily: fontFamily),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.18)),
                ),
                child: Icon(Icons.receipt_long, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'DETALLE DE DEVOLUCIÓN',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w900,
                    color: fg,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
              Text(
                currency.format(amount),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontFamily: fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            productLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
              fontFamily: fontFamily,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          kv('Fecha', dateFormat.format(createdAt)),
          kv('Código', returnCode.isNotEmpty ? returnCode : ''),
          kv('Items', itemCount > 0 ? itemCount.toString() : ''),
          kv('Ticket orig.', originalCode),
          kv('NCF orig.', originalNcf),
          if (customerName.isNotEmpty ||
              customerPhone.isNotEmpty ||
              customerRnc.isNotEmpty)
            kv(
              'Cliente',
              [
                if (customerName.isNotEmpty) customerName,
                if (customerPhone.isNotEmpty) customerPhone,
                if (customerRnc.isNotEmpty) customerRnc,
              ].join('  •  '),
            ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Motivo / Nota',
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg.withOpacity(0.7),
                fontWeight: FontWeight.w800,
                fontFamily: fontFamily,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.3),
                ),
              ),
              child: Text(
                note,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontFamily: fontFamily,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryMetric {
  final String label;
  final double amount;
  final Color color;

  const _SummaryMetric(this.label, this.amount, this.color);
}
