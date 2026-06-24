import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../clients/data/client_model.dart';
import '../../../../core/utils/currency_display.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/update/update_shutdown_coordinator.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../../theme/app_colors.dart';

enum PaymentMethod { cash, card, transfer, mixed, credit, layaway }

enum PaymentOutputMode { ticket, pdf, none }

/// Diálogo de pago profesional con identidad de marca
class PaymentDialog extends StatefulWidget {
  final double total;
  final bool initialPrintTicket;
  final bool allowInvoicePdfDownload;
  final String? initialChargeOutputMode;
  final String? cartFingerprint;
  final ClientModel? selectedClient;
  final Future<ClientModel?> Function() onSelectClient;
  final Future<ClientModel?> Function()? onCreateClient;
  final Future<ClientModel?> Function(ClientModel client)? onEditClient;

  const PaymentDialog({
    super.key,
    required this.total,
    this.initialPrintTicket = true,
    this.allowInvoicePdfDownload = true,
    this.initialChargeOutputMode,
    this.cartFingerprint,
    this.selectedClient,
    required this.onSelectClient,
    this.onCreateClient,
    this.onEditClient,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  ColorScheme get scheme => Theme.of(context).colorScheme;
  AppStatusTheme get status =>
      Theme.of(context).extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: scheme.tertiary,
        warning: scheme.tertiary,
        error: scheme.error,
        info: scheme.primary,
      );
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  final _cashController = TextEditingController();
  final _cardController = TextEditingController();
  final _transferController = TextEditingController();
  final _interestController = TextEditingController(text: '0');
  final _termDaysController = TextEditingController(text: '30');
  final _installmentsController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  final _layawayNameController = TextEditingController();
  final _layawayPhoneController = TextEditingController();
  final _receivedController = TextEditingController();
  DateTime? _dueDate;
  double _change = 0.0;
  PaymentOutputMode _outputMode = PaymentOutputMode.ticket;
  ClientModel? _selectedClient;
  bool _isProcessingPayment = false;
  bool _hasRequestedClose = false;
  String? _activePaymentRequestId;
  late final String _paymentAttemptId;
  String _lastTriggerSource = 'unknown';
  int _lastSubmitAtMs = 0;

  bool get _printTicket => _outputMode == PaymentOutputMode.ticket;
  bool get _downloadInvoicePdf => _outputMode == PaymentOutputMode.pdf;

  bool _handleKeyEvent(KeyEvent event) {
    assert(() {
      // ignore: avoid_print
      debugPrint(
        '[PAYMENT] key=${event.logicalKey.keyLabel} logical=${event.logicalKey} physical=${event.physicalKey}',
      );
      return true;
    }());

    final isConfirmKey =
        event.logicalKey == LogicalKeyboardKey.f9 ||
        event.physicalKey == PhysicalKeyboardKey.f9;

    if (isConfirmKey) {
      if (event is KeyRepeatEvent) return true;
      if (event is KeyDownEvent) {
        _submitPayment(source: 'keyboard_f9');
      }
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyRepeatEvent) return true;
      if (event is KeyDownEvent && mounted && !_isProcessingPayment) {
        Navigator.of(context).maybePop();
      }
      return true;
    }
    return false;
  }

  Future<void> _submitPayment({required String source}) async {
    if (_isProcessingPayment) return;
    if (!mounted) return;
    if (SafeUpdateCoordinator.blocksCriticalOperations) {
      _showError(
        'FullPOS se está preparando para actualizar. Espera a que el sistema se cierre y vuelva a abrir.',
      );
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if ((nowMs - _lastSubmitAtMs) < 450) return;
    _lastSubmitAtMs = nowMs;
    _lastTriggerSource = source;

    final paymentRequestId = _paymentAttemptId;
    if (_activePaymentRequestId == paymentRequestId) return;
    _activePaymentRequestId = paymentRequestId;

    debugPrint(
      'PAYMENT_TRIGGER source=$source time=$nowMs cart=${widget.cartFingerprint ?? 'na'} request=$paymentRequestId stack=${StackTrace.current.toString().split('\n').take(3).join(' | ')}',
    );

    // En desktop, el primer click/tecla a veces solo cambia el foco.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isProcessingPayment = true);
    await Future<void>.delayed(Duration.zero);
    try {
      await _processPayment(paymentRequestId);
    } catch (e) {
      if (!mounted) return;
      _showError('Error al cobrar: $e');
    } finally {
      _activePaymentRequestId = null;
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  String _buildPaymentRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 32);
    return 'pay-$now-$random';
  }

  void _selectPrint() {
    setState(() {
      _outputMode = PaymentOutputMode.ticket;
    });
  }

  void _selectDownloadInvoicePdf() {
    if (!widget.allowInvoicePdfDownload) return;
    setState(() {
      _outputMode = PaymentOutputMode.pdf;
    });
  }

  void _selectWithoutPrinting() {
    setState(() {
      _outputMode = PaymentOutputMode.none;
    });
  }

  PaymentOutputMode _resolveInitialOutputMode() {
    final configured = (widget.initialChargeOutputMode ?? '')
        .trim()
        .toLowerCase();
    if (configured == 'pdf' && widget.allowInvoicePdfDownload) {
      return PaymentOutputMode.pdf;
    }
    if (configured == 'none') {
      return PaymentOutputMode.none;
    }
    if (configured == 'ticket') {
      return PaymentOutputMode.ticket;
    }
    return widget.initialPrintTicket
        ? PaymentOutputMode.ticket
        : (widget.allowInvoicePdfDownload
              ? PaymentOutputMode.pdf
              : PaymentOutputMode.none);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _paymentAttemptId = _buildPaymentRequestId();
    _outputMode = _resolveInitialOutputMode();
    _selectedClient = widget.selectedClient;
    if (_selectedClient != null) {
      _syncLayawayFromClient(_selectedClient!);
    }
    _cashController.text = widget.total.toStringAsFixed(2);
    _receivedController.text = widget.total.toStringAsFixed(2);
    _cashController.addListener(_calculateChange);
    _cardController.addListener(_calculateChange);
    _transferController.addListener(_calculateChange);
    _receivedController.addListener(_calculateReceivedChange);
    _termDaysController.addListener(_syncDueDateFromTerm);
    _calculateReceivedChange();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _cashController.dispose();
    _cardController.dispose();
    _transferController.dispose();
    _interestController.dispose();
    _termDaysController.dispose();
    _installmentsController.dispose();
    _noteController.dispose();
    _layawayNameController.dispose();
    _layawayPhoneController.dispose();
    _receivedController.dispose();
    super.dispose();
  }

  void _calculateReceivedChange() {
    final received = double.tryParse(_receivedController.text) ?? widget.total;
    setState(() {
      _change = received - widget.total;
    });
  }

  void _calculateChange() {
    if (_selectedMethod == PaymentMethod.cash) {
      final cash = double.tryParse(_cashController.text) ?? 0;
      setState(() {
        _change = cash - widget.total;
      });
    } else if (_selectedMethod == PaymentMethod.mixed) {
      final cash = double.tryParse(_cashController.text) ?? 0;
      final card = double.tryParse(_cardController.text) ?? 0;
      final transfer = double.tryParse(_transferController.text) ?? 0;
      final total = cash + card + transfer;
      setState(() {
        _change = total - widget.total;
      });
    } else {
      setState(() {
        _change = 0;
      });
    }
  }

  void _syncDueDateFromTerm() {
    if (_selectedMethod != PaymentMethod.credit) return;
    final days = int.tryParse(_termDaysController.text);
    if (days == null || days <= 0) return;
    setState(() {
      _dueDate = DateTime.now().add(Duration(days: days));
    });
  }

  Future<void> _selectDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final diff = date.difference(DateTime.now()).inDays;
    setState(() {
      _dueDate = date;
      if (diff > 0) {
        _termDaysController.text = diff.toString();
      }
    });
  }

  bool _isClientComplete(ClientModel? client) {
    if (client == null) return false;
    final phone = (client.telefono ?? '').trim();
    final address = (client.direccion ?? '').trim();
    final rnc = (client.rnc ?? '').trim();
    final cedula = (client.cedula ?? '').trim();
    return phone.isNotEmpty &&
        address.isNotEmpty &&
        (rnc.isNotEmpty || cedula.isNotEmpty);
  }

  Future<void> _ensureClientSelected() async {
    final picked = await widget.onSelectClient();
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedClient = picked;
        _syncLayawayFromClient(picked);
      });
    }
  }

  void _syncLayawayFromClient(ClientModel client) {
    if (client.nombre.trim().isNotEmpty) {
      _layawayNameController.text = client.nombre.trim();
    }
    if ((client.telefono ?? '').trim().isNotEmpty) {
      _layawayPhoneController.text = client.telefono!.trim();
    }
  }

  String _resolveLayawayName() {
    final manual = _layawayNameController.text.trim();
    if (manual.isNotEmpty) return manual;
    return _selectedClient?.nombre.trim() ?? '';
  }

  String _resolveLayawayPhone() {
    final manual = _layawayPhoneController.text.trim();
    if (manual.isNotEmpty) return manual;
    return (_selectedClient?.telefono ?? '').trim();
  }

  Future<void> _ensureClientCompleted(ClientModel client) async {
    if (widget.onEditClient == null) return;
    final updated = await widget.onEditClient!(client);
    if (!mounted) return;
    if (updated != null) {
      setState(() => _selectedClient = updated);
    }
  }

  Future<void> _processPayment(String paymentRequestId) async {
    debugPrint(
      'PAYMENT_EXECUTE source=$_lastTriggerSource time=${DateTime.now().millisecondsSinceEpoch} cart=${widget.cartFingerprint ?? 'na'} request=$paymentRequestId',
    );

    final cashAmount = double.tryParse(_cashController.text) ?? 0.0;
    final cardAmount = double.tryParse(_cardController.text) ?? 0.0;
    final transferAmount = double.tryParse(_transferController.text) ?? 0.0;
    final mixedTotal = cashAmount + cardAmount + transferAmount;

    if (_selectedMethod == PaymentMethod.cash && _change < -0.009) {
      _showError('El efectivo recibido no cubre el total de la venta');
      return;
    }

    if (_selectedMethod == PaymentMethod.card) {
      if (cardAmount <= 0) {
        _showError('Debe indicar el monto cobrado con tarjeta');
        return;
      }
      if ((cardAmount - widget.total).abs() > 0.009) {
        _showError('El pago con tarjeta debe cubrir exactamente el total');
        return;
      }
    }

    if (_selectedMethod == PaymentMethod.transfer) {
      if (transferAmount <= 0) {
        _showError('Debe indicar el monto transferido');
        return;
      }
      if ((transferAmount - widget.total).abs() > 0.009) {
        _showError(
          'El pago por transferencia debe cubrir exactamente el total',
        );
        return;
      }
    }

    if (_selectedMethod == PaymentMethod.mixed) {
      final hasCard = cardAmount > 0.009;
      final hasTransfer = transferAmount > 0.009;

      if (cashAmount <= 0.009) {
        _showError('El pago mixto debe incluir una parte en efectivo');
        return;
      }
      if (hasCard == hasTransfer) {
        _showError(
          'El pago mixto solo permite efectivo con tarjeta o efectivo con transferencia',
        );
        return;
      }
      if ((mixedTotal - widget.total).abs() > 0.009) {
        _showError('El pago mixto debe cuadrar exactamente con el total');
        return;
      }
    }

    // Si el usuario eligió descargar factura PDF, obligar a seleccionar cliente
    // para poder nombrar el archivo de forma profesional.
    if (_downloadInvoicePdf) {
      if (_selectedClient == null) {
        _showError('Debe seleccionar un cliente para descargar la factura');
        await _ensureClientSelected();
        return;
      }
      final name = _selectedClient?.nombre.trim() ?? '';
      if (name.isEmpty) {
        _showError(
          'Debe completar el nombre del cliente para descargar la factura',
        );
        return;
      }
    }

    // Validar según método
    if (_selectedMethod == PaymentMethod.credit) {
      if (_selectedClient == null) {
        _showError('Debe seleccionar un cliente para vender a crédito');
        await _ensureClientSelected();
        return;
      }
      if (!_isClientComplete(_selectedClient)) {
        _showError('Complete los datos del cliente para crédito');
        await _ensureClientCompleted(_selectedClient!);
        return;
      }
      final termDays = int.tryParse(_termDaysController.text) ?? 0;
      if (termDays <= 0) {
        _showError('Debe indicar el plazo del crédito');
        return;
      }
      final installments = int.tryParse(_installmentsController.text) ?? 0;
      if (installments <= 0) {
        _showError('Debe indicar la cantidad de cuotas');
        return;
      }
      if (_dueDate == null) {
        _showError('Debe seleccionar una fecha de vencimiento');
        return;
      }
    }

    if (_selectedMethod == PaymentMethod.layaway) {
      if (_selectedClient == null) {
        _showError('Debe seleccionar un cliente para apartado');
        await _ensureClientSelected();
        return;
      }
      final name = _resolveLayawayName();
      final phone = _resolveLayawayPhone();
      if (name.isEmpty || phone.isEmpty) {
        _showError('Debe indicar nombre y teléfono para apartado');
        return;
      }
      final received = double.tryParse(_receivedController.text) ?? 0.0;
      final minLayaway = (widget.total * 0.30).clamp(0, double.infinity);
      if (received + 1e-6 < minLayaway) {
        _showError(
          'El abono inicial debe ser al menos el 30% (${CurrencyDisplay.format(minLayaway)})',
        );
        return;
      }
      if (received < 0) {
        _showError('El abono inicial no puede ser negativo');
        return;
      }
      if (received > widget.total) {
        _showError('El abono inicial no puede exceder el total');
        return;
      }
    }

    // Retornar resultado (cerrar el diálogo que lo presentó)
    final result = {
      'paymentRequestId': paymentRequestId,
      'triggerSource': _lastTriggerSource,
      'selectedClient': _selectedClient,
      'method': _selectedMethod,
      'cash': cashAmount,
      'card': cardAmount,
      'transfer': transferAmount,
      'received': double.tryParse(_receivedController.text) ?? widget.total,
      'change': _change > 0 ? _change : 0,
      'dueDate': _dueDate,
      'interest': double.tryParse(_interestController.text) ?? 0,
      'termDays': int.tryParse(_termDaysController.text) ?? 0,
      'installments': int.tryParse(_installmentsController.text) ?? 0,
      'note': _noteController.text.trim(),
      'layawayName': _resolveLayawayName(),
      'layawayPhone': _resolveLayawayPhone(),
      'printTicket': _printTicket,
      'downloadInvoicePdf': widget.allowInvoicePdfDownload
          ? _downloadInvoicePdf
          : false,
    };
    _closeDialog(result);
  }

  void _closeDialog(Map<String, dynamic> result) {
    if (_hasRequestedClose) return;
    _hasRequestedClose = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (!navigator.canPop()) return;
      navigator.pop(result);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: scheme.error),
    );
  }
  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width * 0.66).clamp(620.0, 820.0);
    final dialogMaxHeight = (viewport.height * 0.90).clamp(600.0, 860.0);

    return DialogKeyboardShortcuts(
      onSubmit: () => _submitPayment(source: 'keyboard_enter'),
      enableSubmitShortcuts: true,
      enableDismissShortcut: false,
      child: Dialog(
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        backgroundColor: Colors.transparent,
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: dialogMaxHeight),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFD),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDDE3EC)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(45),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMainSummary(),
                      const SizedBox(height: 18),

                      _buildPaymentMethodSelector(),
                      const SizedBox(height: 16),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: KeyedSubtree(
                          key: ValueKey(_selectedMethod),
                          child: _buildMethodFields(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 74,
      padding: const EdgeInsets.fromLTRB(24, 0, 14, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5EAF1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              size: 21,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cobrar venta',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.25,
                    height: 1,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Confirma el pago y genera el comprobante',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _isProcessingPayment
                ? null
                : () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.close_rounded,
              size: 22,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainSummary() {
    final isLayaway = _selectedMethod == PaymentMethod.layaway;
    final payController = isLayaway ? _receivedController : _cashController;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total a pagar',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              Text(
                CurrencyDisplay.format(widget.total),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE5EAF1)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  isLayaway ? 'Abono inicial' : 'Cliente paga con',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.15,
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                height: 48,
                child: TextField(
                  controller: payController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryBlue,
                    letterSpacing: -0.25,
                  ),
                  decoration: _cleanInputDecoration(
                    hintText: widget.total.toStringAsFixed(2),
                    prefixText: r'$ ',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _buildChangeLine(),
        ],
      ),
    );
  }

  Widget _buildChangeLine() {
    final isPositive = _change > 0.009;
    final isNegative = _change < -0.009;

    final color = isPositive
        ? status.success
        : isNegative
            ? status.error
            : const Color(0xFF64748B);

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isNegative
            ? status.error.withAlpha(14)
            : isPositive
                ? status.success.withAlpha(14)
                : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isNegative
                ? Icons.warning_amber_rounded
                : Icons.keyboard_return_rounded,
            size: 19,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              isNegative ? 'Falta' : 'Devuelta',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          Text(
            CurrencyDisplay.format(_change.abs()),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    final items = [
      _PaymentMethodView(PaymentMethod.cash, 'Efectivo', Icons.money_rounded),
      _PaymentMethodView(PaymentMethod.card, 'Tarjeta', Icons.credit_card),
      _PaymentMethodView(
        PaymentMethod.transfer,
        'Transferencia',
        Icons.account_balance_rounded,
      ),
      _PaymentMethodView(PaymentMethod.mixed, 'Mixto', Icons.payments_rounded),
      _PaymentMethodView(
        PaymentMethod.credit,
        'Crédito',
        Icons.request_quote_rounded,
      ),
      _PaymentMethodView(
        PaymentMethod.layaway,
        'Apartado',
        Icons.bookmark_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Método de pago',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            letterSpacing: -0.15,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth >= 650
                ? (constraints.maxWidth - 14) / 3
                : (constraints.maxWidth - 7) / 2;

            return Wrap(
              spacing: 7,
              runSpacing: 8,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: _buildMethodButton(
                      item.method,
                      item.label,
                      item.icon,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMethodButton(PaymentMethod method, String label, IconData icon) {
    final isSelected = _selectedMethod == method;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _selectPaymentMethod(method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryBlue
                  : const Color(0xFFDDE3EC),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: isSelected ? Colors.white : AppColors.primaryBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectPaymentMethod(PaymentMethod method) {
    setState(() {
      _selectedMethod = method;
      _change = 0;

      if (method != PaymentMethod.cash && method != PaymentMethod.mixed) {
        _cashController.clear();
      }
      if (method != PaymentMethod.card && method != PaymentMethod.mixed) {
        _cardController.clear();
      }
      if (method != PaymentMethod.transfer && method != PaymentMethod.mixed) {
        _transferController.clear();
      }

      if (method == PaymentMethod.card) {
        _cardController.text = widget.total.toStringAsFixed(2);
      } else if (method == PaymentMethod.transfer) {
        _transferController.text = widget.total.toStringAsFixed(2);
      } else if (method == PaymentMethod.cash) {
        _cashController.text = widget.total.toStringAsFixed(2);
      } else if (method == PaymentMethod.layaway) {
        _receivedController.text = (widget.total * 0.30)
            .clamp(0, widget.total)
            .toStringAsFixed(2);
      } else if (method == PaymentMethod.credit) {
        final days = int.tryParse(_termDaysController.text) ?? 0;
        if (days > 0) {
          _dueDate = DateTime.now().add(Duration(days: days));
        }
      }

      _calculateChange();
      _calculateReceivedChange();
    });
  }

  Widget _buildMethodFields() {
    if (_selectedMethod == PaymentMethod.cash) {
      return const SizedBox.shrink();
    }

    if (_selectedMethod == PaymentMethod.card) {
      return _buildAmountField(
        'Monto con tarjeta',
        _cardController,
        Icons.credit_card,
      );
    }

    if (_selectedMethod == PaymentMethod.transfer) {
      return _buildAmountField(
        'Monto transferido',
        _transferController,
        Icons.account_balance_rounded,
      );
    }

    if (_selectedMethod == PaymentMethod.mixed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildAmountField(
                  'Efectivo',
                  _cashController,
                  Icons.money_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildAmountField(
                  'Tarjeta',
                  _cardController,
                  Icons.credit_card,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAmountField(
            'Transferencia',
            _transferController,
            Icons.account_balance_rounded,
          ),
          const SizedBox(height: 8),
          Text(
            'Solo efectivo + tarjeta o efectivo + transferencia.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withAlpha(150),
            ),
          ),
          const SizedBox(height: 10),
          _buildDifferenceLine(),
        ],
      );
    }

    if (_selectedMethod == PaymentMethod.credit) {
      return _buildCreditFields();
    }

    if (_selectedMethod == PaymentMethod.layaway) {
      return _buildLayawayFields();
    }

    return const SizedBox.shrink();
  }

  Widget _buildDifferenceLine() {
    final isOk = _change.abs() < 0.01;
    final color = isOk ? status.success : status.warning;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            'Diferencia',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            CurrencyDisplay.format(_change),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildClientLine(
          title: 'Cliente para crédito',
          emptyText: 'Sin seleccionar',
          actionText: _selectedClient == null ? 'Seleccionar' : 'Completar',
          onPressed: _selectedClient == null
              ? _ensureClientSelected
              : (!_isClientComplete(_selectedClient) &&
                      widget.onEditClient != null)
                  ? () => _ensureClientCompleted(_selectedClient!)
                  : null,
        ),
        if (_selectedClient != null && !_isClientComplete(_selectedClient)) ...[
          const SizedBox(height: 8),
          Text(
            'Faltan datos: teléfono, dirección y RNC/cédula.',
            style: TextStyle(
              color: status.warning,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSmallTextField(
                controller: _termDaysController,
                label: 'Plazo',
                suffixText: 'días',
                icon: Icons.timer_outlined,
                digitsOnly: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSmallTextField(
                controller: _installmentsController,
                label: 'Cuotas',
                icon: Icons.stacked_line_chart_rounded,
                digitsOnly: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildDueDateSelector(),
        const SizedBox(height: 10),
        _buildSmallTextField(
          controller: _interestController,
          label: 'Interés',
          suffixText: '%',
          icon: Icons.percent_rounded,
        ),
        const SizedBox(height: 10),
        _buildSmallTextField(
          controller: _noteController,
          label: 'Nota / condiciones',
          icon: Icons.notes_rounded,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildLayawayFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildClientLine(
          title: 'Cliente para apartado',
          emptyText: 'Sin seleccionar',
          actionText: 'Seleccionar',
          onPressed: _ensureClientSelected,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSmallTextField(
                controller: _layawayNameController,
                label: 'Nombre',
                icon: Icons.badge_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSmallTextField(
                controller: _layawayPhoneController,
                label: 'Teléfono',
                icon: Icons.phone_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildSmallTextField(
          controller: _noteController,
          label: 'Nota del apartado',
          icon: Icons.notes_rounded,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildClientLine({
    required String title,
    required String emptyText,
    required String actionText,
    required VoidCallback? onPressed,
  }) {
    final clientName = (_selectedClient?.nombre.trim().isNotEmpty ?? false)
        ? _selectedClient!.nombre.trim()
        : emptyText;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFDDE3EC)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_outline_rounded,
            color: AppColors.primaryBlue,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title  ',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  TextSpan(
                    text: clientName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              side: const BorderSide(color: Color(0xFFC9DAFF)),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateSelector() {
    final label = _dueDate != null
        ? '${_dueDate!.day.toString().padLeft(2, '0')}/${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.year}'
        : 'Seleccionar fecha';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: _selectDueDate,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFDDE3EC)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: AppColors.primaryBlue,
                size: 19,
              ),
              const SizedBox(width: 10),
              const Text(
                'Vencimiento',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 17),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border(
          top: BorderSide(color: Color(0xFFE5EAF1)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOutputSelector(),
          const SizedBox(height: 15),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Enter/F9 para cobrar · Esc para salir',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              TextButton(
                onPressed: _isProcessingPayment
                    ? null
                    : () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isProcessingPayment
                      ? null
                      : () => _submitPayment(source: 'mouse_click'),
                  icon: _isProcessingPayment
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_chargeActionIcon(), size: 20),
                  label: Text(
                    _isProcessingPayment
                        ? 'Procesando...'
                        : _chargeActionLabel(),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.15,
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

  Widget _buildOutputSelector() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildOutputOption(
              label: 'Ticket',
              icon: Icons.print_rounded,
              selected: _outputMode == PaymentOutputMode.ticket,
              onTap: _selectPrint,
            ),
          ),
          Expanded(
            child: _buildOutputOption(
              label: 'PDF',
              icon: Icons.download_rounded,
              selected: _outputMode == PaymentOutputMode.pdf,
              enabled: widget.allowInvoicePdfDownload,
              onTap: _selectDownloadInvoicePdf,
            ),
          ),
          Expanded(
            child: _buildOutputOption(
              label: 'Sin imprimir',
              icon: Icons.block_rounded,
              selected: _outputMode == PaymentOutputMode.none,
              onTap: _selectWithoutPrinting,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final color = selected ? AppColors.primaryBlue : const Color(0xFF334155);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 38,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: enabled ? color : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: enabled ? color : const Color(0xFF94A3B8),
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _chargeActionLabel() {
    switch (_outputMode) {
      case PaymentOutputMode.ticket:
        return 'Cobrar e imprimir';
      case PaymentOutputMode.pdf:
        return 'Cobrar y descargar';
      case PaymentOutputMode.none:
        return 'Cobrar';
    }
  }

  IconData _chargeActionIcon() {
    switch (_outputMode) {
      case PaymentOutputMode.ticket:
        return Icons.print_rounded;
      case PaymentOutputMode.pdf:
        return Icons.download_rounded;
      case PaymentOutputMode.none:
        return Icons.check_circle_outline_rounded;
    }
  }

  Widget _buildAmountField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return SizedBox(
      height: 50,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: Color(0xFF0F172A),
        ),
        decoration: _cleanInputDecoration(
          labelText: label,
          icon: icon,
          prefixText: r'$ ',
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
      ),
    );
  }

  Widget _buildSmallTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? suffixText,
    bool digitsOnly = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: digitsOnly ? TextInputType.number : TextInputType.text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: Color(0xFF0F172A),
      ),
      decoration: _cleanInputDecoration(
        labelText: label,
        icon: icon,
        suffixText: suffixText,
      ),
      inputFormatters: [
        if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
      ],
    );
  }

  InputDecoration _cleanInputDecoration({
    String? labelText,
    String? hintText,
    String? prefixText,
    String? suffixText,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      suffixText: suffixText,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: icon == null
          ? null
          : Icon(
              icon,
              size: 19,
              color: AppColors.primaryBlue,
            ),
      prefixIconConstraints: const BoxConstraints(
        minWidth: 42,
        minHeight: 42,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF64748B),
      ),
      hintStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF94A3B8),
      ),
      prefixStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF64748B),
      ),
      suffixStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF64748B),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFDDE3EC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFDDE3EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(
          color: AppColors.primaryBlue,
          width: 1.5,
        ),
      ),
    );
  }
}

class _PaymentMethodView {
  final PaymentMethod method;
  final String label;
  final IconData icon;

  const _PaymentMethodView(this.method, this.label, this.icon);
}
