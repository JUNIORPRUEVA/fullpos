import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../clients/data/client_model.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

enum PaymentMethod { cash, card, transfer, mixed, credit, layaway }

/// Diálogo de pago profesional
class PaymentDialog extends StatefulWidget {
  final double total;
  final bool initialPrintTicket;
  final bool allowInvoicePdfDownload;
  final ClientModel? selectedClient;
  final Future<ClientModel?> Function() onSelectClient;
  final Future<ClientModel?> Function(ClientModel client)? onEditClient;

  const PaymentDialog({
    super.key,
    required this.total,
    this.initialPrintTicket = true,
    this.allowInvoicePdfDownload = true,
    this.selectedClient,
    required this.onSelectClient,
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
  bool _printTicket = true; // Por defecto imprimir
  bool _downloadInvoicePdf = false;
  ClientModel? _selectedClient;
  bool _isSubmitting = false;
  bool _hasRequestedClose = false;

  bool _handleKeyEvent(KeyEvent event) {
    // En Windows, algunos Function keys no siempre pasan por Shortcuts cuando
    // hay un TextField enfocado. Capturamos F9 aquí para que siempre confirme.
    assert(() {
      // ignore: avoid_print
      debugPrint(
        '[PAYMENT] key=${event.logicalKey.keyLabel} logical=${event.logicalKey} physical=${event.physicalKey}',
      );
      return true;
    }());

    if (event.logicalKey == LogicalKeyboardKey.f9 ||
        event.physicalKey == PhysicalKeyboardKey.f9) {
      // Evitar que el autorepeat provoque cobros dobles.
      if (event is KeyRepeatEvent) return true;
      if (event is KeyDownEvent) {
        // Ignorar clicks dobles: _submitPayment ya tiene guard.
        _submitPayment();
      }
      return true;
    }
    return false;
  }

  Future<void> _submitPayment() async {
    if (_isSubmitting) return;
    if (!mounted) return;

    // En desktop, el primer click/tecla a veces solo cambia el foco.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isSubmitting = true);
    await Future<void>.delayed(Duration.zero);
    try {
      await _processPayment();
    } catch (e) {
      if (!mounted) return;
      _showError('Error al cobrar: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _selectPrint() {
    setState(() {
      _printTicket = true;
      _downloadInvoicePdf = false;
    });
  }

  void _selectDownloadInvoicePdf() {
    if (!widget.allowInvoicePdfDownload) return;
    setState(() {
      _downloadInvoicePdf = true;
      _printTicket = false;
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _printTicket = true;
    _downloadInvoicePdf = false;
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

  Future<void> _processPayment() async {
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
          'El abono inicial debe ser al menos el 30% (${minLayaway.toStringAsFixed(2)})',
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
      'method': _selectedMethod,
      'cash': double.tryParse(_cashController.text) ?? 0,
      'card': double.tryParse(_cardController.text) ?? 0,
      'transfer': double.tryParse(_transferController.text) ?? 0,
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
      'downloadInvoicePdf':
          widget.allowInvoicePdfDownload ? _downloadInvoicePdf : false,
    };
    _closeDialog(result);
  }

  void _closeDialog(Map<String, dynamic> result) {
    if (_hasRequestedClose) return;
    _hasRequestedClose = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: scheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DialogKeyboardShortcuts(
      onSubmit: _submitPayment,
      child: Dialog(
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.payment,
                            color: scheme.onPrimary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PROCESAR PAGO',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                                Text(
                                  'SELECCIONE EL MÉTODO DE PAGO',
                                  style: TextStyle(
                                    color: scheme.onPrimary.withAlpha(179),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(Icons.close, color: scheme.onPrimary),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Total a pagar
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.secondary,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.attach_money,
                                        color: scheme.secondary,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'TOTAL A PAGAR:',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '\$${widget.total.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Sección de Recibido y Devuelta
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Campo de monto recibido
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.payments,
                                        color: scheme.primary,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          _selectedMethod ==
                                                  PaymentMethod.layaway
                                              ? 'ABONO INICIAL:'
                                              : 'CLIENTE PAGA CON:',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: _receivedController,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: scheme.primary,
                                          ),
                                          decoration: InputDecoration(
                                            hintText:
                                                widget.total.toStringAsFixed(2),
                                            hintStyle: TextStyle(
                                              color: scheme.onSurface.withAlpha(102),
                                            ),
                                            prefixText: '\$ ',
                                            prefixStyle: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: scheme.primary,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: scheme.primary,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'^\d+\.?\d{0,2}'),
                                            ),
                                          ],
                                          onSubmitted: (_) => _submitPayment(),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  // Devuelta
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _change > 0
                                          ? status.success.withAlpha(51)
                                          : (_change < 0
                                                ? status.error.withAlpha(51)
                                                : scheme
                                                      .surfaceContainerHighest),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _change >= 0
                                                  ? Icons.arrow_back
                                                  : Icons.warning,
                                              color: _change > 0
                                                  ? status.success
                                                  : (_change < 0
                                                        ? status.error
                                                        : scheme.onSurface
                                                              .withAlpha(153)),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _change >= 0
                                                  ? 'DEVUELTA:'
                                                  : 'FALTA:',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: _change > 0
                                                    ? status.success
                                                    : (_change < 0
                                                          ? status.error
                                                          : scheme.onSurface
                                                                .withAlpha(
                                                                  153,
                                                                )),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '\$${_change.abs().toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: _change > 0
                                                ? status.success
                                                : (_change < 0
                                                      ? status.error
                                                      : scheme.onSurface
                                                            .withAlpha(153)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Método de pago
                            const Text(
                              'MÉTODO DE PAGO',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildMethodChip(
                                  PaymentMethod.cash,
                                  'EFECTIVO',
                                  Icons.money,
                                ),
                                _buildMethodChip(
                                  PaymentMethod.card,
                                  'TARJETA',
                                  Icons.credit_card,
                                ),
                                _buildMethodChip(
                                  PaymentMethod.transfer,
                                  'TRANSFERENCIA',
                                  Icons.account_balance,
                                ),
                                _buildMethodChip(
                                  PaymentMethod.mixed,
                                  'MIXTO',
                                  Icons.payments,
                                ),
                                _buildMethodChip(
                                  PaymentMethod.credit,
                                  'CRÉDITO',
                                  Icons.request_quote,
                                ),
                                _buildMethodChip(
                                  PaymentMethod.layaway,
                                  'APARTADO',
                                  Icons.bookmark,
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Campos según método
                            if (_selectedMethod == PaymentMethod.cash) ...[
                              // Solo el efectivo, la devuelta ya se muestra arriba
                              const SizedBox.shrink(),
                            ] else if (_selectedMethod ==
                                PaymentMethod.card) ...[
                              _buildAmountField(
                                'MONTO CON TARJETA',
                                _cardController,
                                Icons.credit_card,
                              ),
                            ] else if (_selectedMethod ==
                                PaymentMethod.transfer) ...[
                              _buildAmountField(
                                'MONTO TRANSFERIDO',
                                _transferController,
                                Icons.account_balance,
                              ),
                            ] else if (_selectedMethod ==
                                PaymentMethod.mixed) ...[
                              _buildAmountField(
                                'EFECTIVO',
                                _cashController,
                                Icons.money,
                              ),
                              const SizedBox(height: 12),
                              _buildAmountField(
                                'TARJETA',
                                _cardController,
                                Icons.credit_card,
                              ),
                              const SizedBox(height: 12),
                              _buildAmountField(
                                'TRANSFERENCIA',
                                _transferController,
                                Icons.account_balance,
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _change.abs() < 0.01
                                      ? status.success.withAlpha(31)
                                      : status.warning.withAlpha(31),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _change.abs() < 0.01
                                        ? status.success
                                        : status.warning,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'DIFERENCIA:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '\$${_change.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _change.abs() < 0.01
                                            ? status.success
                                            : status.warning,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (_selectedMethod ==
                                PaymentMethod.credit) ...[
                              // Cliente
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.person, color: scheme.primary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'CLIENTE',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.onSurface.withAlpha(
                                                153,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            (_selectedClient?.nombre ??
                                                    'NINGUNO')
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_selectedClient == null)
                                      ElevatedButton(
                                        onPressed: _ensureClientSelected,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: scheme.primary,
                                          foregroundColor: scheme.onPrimary,
                                        ),
                                        child: const Text('SELECCIONAR'),
                                      ),
                                    if (_selectedClient != null &&
                                        !_isClientComplete(_selectedClient) &&
                                        widget.onEditClient != null)
                                      OutlinedButton(
                                        onPressed: () => _ensureClientCompleted(
                                          _selectedClient!,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: scheme.primary,
                                        ),
                                        child: const Text('COMPLETAR'),
                                      ),
                                  ],
                                ),
                              ),
                              if (_selectedClient != null &&
                                  !_isClientComplete(_selectedClient))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Faltan datos del cliente (telefono, direccion y RNC/cedula)',
                                    style: TextStyle(
                                      color: status.warning,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),

                              // Plazo y cuotas
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _termDaysController,
                                      decoration: const InputDecoration(
                                        labelText: 'PLAZO (DIAS)',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.timer_outlined),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _installmentsController,
                                      decoration: const InputDecoration(
                                        labelText: 'CUOTAS',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(
                                          Icons.stacked_line_chart,
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Fecha de vencimiento
                              InkWell(
                                onTap: _selectDueDate,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'FECHA DE VENCIMIENTO',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.onSurface
                                                    .withAlpha(153),
                                              ),
                                            ),
                                            Text(
                                              _dueDate != null
                                                  ? '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}'
                                                  : 'SELECCIONAR FECHA',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Interés
                              TextFormField(
                                controller: _interestController,
                                decoration: const InputDecoration(
                                  labelText: 'INTERÉS (%)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.percent),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d+\.?\d{0,2}'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Nota
                              TextFormField(
                                controller: _noteController,
                                decoration: const InputDecoration(
                                  labelText: 'NOTA / CONDICIONES',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.note),
                                ),
                                maxLines: 2,
                              ),
                            ] else if (_selectedMethod ==
                                PaymentMethod.layaway) ...[
                              // Cliente (apartado)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.person, color: scheme.primary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'CLIENTE',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.onSurface.withAlpha(
                                                153,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            (_selectedClient?.nombre ??
                                                    'SIN SELECCIONAR')
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: _ensureClientSelected,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: scheme.primary,
                                        foregroundColor: scheme.onPrimary,
                                      ),
                                      child: const Text('SELECCIONAR'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _layawayNameController,
                                decoration: const InputDecoration(
                                  labelText: 'NOMBRE (APARTADO)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _layawayPhoneController,
                                decoration: const InputDecoration(
                                  labelText: 'TELÉFONO (APARTADO)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.phone),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _noteController,
                                decoration: const InputDecoration(
                                  labelText: 'NOTA (APARTADO)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.note),
                                ),
                                maxLines: 2,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Footer
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Opción de imprimir ticket
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _printTicket
                                      ? Icons.print
                                      : Icons.print_disabled,
                                  color: _printTicket
                                      ? scheme.primary
                                      : scheme.onSurface.withAlpha(153),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'IMPRIMIR TICKET',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch(
                                  value: _printTicket,
                                  onChanged: (value) {
                                    _selectPrint();
                                  },
                                  activeThumbColor: scheme.primary,
                                ),
                              ],
                            ),
                          ),

                          if (widget.allowInvoicePdfDownload)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.download,
                                    color: _downloadInvoicePdf
                                        ? scheme.primary
                                        : scheme.onSurface.withAlpha(153),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'DESCARGAR FACTURA (PDF)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: _downloadInvoicePdf,
                                    onChanged: (value) {
                                      _selectDownloadInvoicePdf();
                                    },
                                    activeThumbColor: scheme.primary,
                                  ),
                                ],
                              ),
                            ),

                          // Botones
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('CANCELAR'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed:
                                    _isSubmitting ? null : _submitPayment,
                                icon: Icon(
                                  _printTicket ? Icons.print : Icons.download,
                                ),
                                label: Text(
                                  _printTicket
                                      ? 'COBRAR E IMPRIMIR'
                                      : 'COBRAR Y DESCARGAR',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: scheme.primary,
                                  foregroundColor: scheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMethodChip(PaymentMethod method, String label, IconData icon) {
    final isSelected = _selectedMethod == method;
    return ChoiceChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected ? scheme.onPrimary : scheme.primary,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedMethod = method;
            _change = 0;
            // Resetear campos
            if (method != PaymentMethod.cash && method != PaymentMethod.mixed) {
              _cashController.clear();
            }
            if (method != PaymentMethod.card && method != PaymentMethod.mixed) {
              _cardController.clear();
            }
            if (method != PaymentMethod.transfer &&
                method != PaymentMethod.mixed) {
              _transferController.clear();
            }
            // Pre-llenar según método
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
          });
        }
      },
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? scheme.onPrimary : scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildAmountField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
    );
  }
}
