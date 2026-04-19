import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../clients/data/client_model.dart';
import '../../../clients/data/clients_repository.dart';
import '../../../clients/utils/phone_validator.dart';
import '../../../clients/utils/rnc_validator.dart';
import '../../../../core/utils/currency_display.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

enum PaymentMethod { cash, card, transfer, mixed, credit, layaway }

enum PaymentOutputMode { ticket, pdf, none }

enum PaymentDocumentType { consumidorFinal, creditoFiscal, cotizacion }

enum PaymentCheckoutMode { ventaLocal, facturaElectronica, cotizacion }

enum PaymentElectronicCustomerType { consumidorFinal, empresa }

enum QuoteOutputMode { save, preview, print }

/// Diálogo de pago profesional
class PaymentDialog extends StatefulWidget {
  final double total;
  final bool initialPrintTicket;
  final bool allowInvoicePdfDownload;
  final String? initialChargeOutputMode;
  final String? cartFingerprint;
  final ClientModel? selectedClient;
  final PaymentDocumentType initialDocumentType;
  final bool allowElectronicInvoiceOption;
  final Future<PaymentDocumentType> Function(PaymentDocumentType type)
  onDocumentTypeChanged;
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
    this.initialDocumentType = PaymentDocumentType.consumidorFinal,
    this.allowElectronicInvoiceOption = true,
    required this.onDocumentTypeChanged,
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
  final _quoteValidDaysController = TextEditingController(text: '15');
  final _layawayNameController = TextEditingController();
  final _layawayPhoneController = TextEditingController();
  final _receivedController = TextEditingController();
  final _invoiceRncController = TextEditingController();
  final _invoiceNameController = TextEditingController();
  final _invoiceAddressController = TextEditingController();
  final _invoicePhoneController = TextEditingController();
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
  late PaymentDocumentType _selectedDocumentType;
  late PaymentCheckoutMode _checkoutMode;
  PaymentElectronicCustomerType _electronicCustomerType =
      PaymentElectronicCustomerType.consumidorFinal;
  QuoteOutputMode _quoteOutputMode = QuoteOutputMode.save;
  bool _showElectronicCompanyOptionalFields = false;
  bool _saveInvoiceClient = false;
  bool _isLookingUpInvoiceClient = false;
  String? _invoiceLookupMessage;
  bool _invoiceLookupMessageIsError = false;
  ClientModel? _invoiceMatchedClient;
  int _invoiceLookupRequestId = 0;

  bool get _printTicket => _outputMode == PaymentOutputMode.ticket;
  bool get _downloadInvoicePdf => _outputMode == PaymentOutputMode.pdf;
  bool get _isQuoteMode => _checkoutMode == PaymentCheckoutMode.cotizacion;
  bool get _isElectronicInvoiceMode =>
      _checkoutMode == PaymentCheckoutMode.facturaElectronica;

  PaymentDocumentType _normalizeDocumentType(PaymentDocumentType type) {
    if (!widget.allowElectronicInvoiceOption &&
        type == PaymentDocumentType.creditoFiscal) {
      return PaymentDocumentType.consumidorFinal;
    }
    return type;
  }

  PaymentCheckoutMode _resolveInitialCheckoutMode(PaymentDocumentType type) {
    switch (type) {
      case PaymentDocumentType.cotizacion:
        return PaymentCheckoutMode.cotizacion;
      case PaymentDocumentType.creditoFiscal:
        return widget.allowElectronicInvoiceOption
            ? PaymentCheckoutMode.facturaElectronica
            : PaymentCheckoutMode.ventaLocal;
      case PaymentDocumentType.consumidorFinal:
        return PaymentCheckoutMode.ventaLocal;
    }
  }

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
    _selectedDocumentType = _normalizeDocumentType(widget.initialDocumentType);
    _checkoutMode = _resolveInitialCheckoutMode(_selectedDocumentType);
    _electronicCustomerType =
        _selectedDocumentType == PaymentDocumentType.creditoFiscal
        ? PaymentElectronicCustomerType.empresa
        : PaymentElectronicCustomerType.consumidorFinal;
    _selectedClient = widget.selectedClient;
    if (_selectedClient != null) {
      _syncLayawayFromClient(_selectedClient!);
      _syncInvoiceClientForm(_selectedClient!, preserveLookupMessage: false);
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
    _quoteValidDaysController.dispose();
    _layawayNameController.dispose();
    _layawayPhoneController.dispose();
    _receivedController.dispose();
    _invoiceRncController.dispose();
    _invoiceNameController.dispose();
    _invoiceAddressController.dispose();
    _invoicePhoneController.dispose();
    super.dispose();
  }

  void _syncInvoiceClientForm(
    ClientModel client, {
    bool preserveLookupMessage = true,
  }) {
    _invoiceMatchedClient = client;
    _invoiceRncController.text = client.normalizedRnc ?? '';
    _invoiceNameController.text = client.nombre.trim();
    _invoiceAddressController.text = client.normalizedAddress ?? '';
    _invoicePhoneController.text = client.normalizedPhone ?? '';
    _saveInvoiceClient = false;
    if (!preserveLookupMessage) {
      _invoiceLookupMessage = null;
      _invoiceLookupMessageIsError = false;
      return;
    }
    _invoiceLookupMessage =
        'Cliente encontrado y autocompletado desde la base de datos.';
    _invoiceLookupMessageIsError = false;
  }

  void _clearInvoiceClientFormForManualEntry({bool keepRnc = true}) {
    final currentRnc = keepRnc ? _invoiceRncController.text : '';
    _invoiceMatchedClient = null;
    _invoiceRncController.text = currentRnc;
    _invoiceNameController.clear();
    _invoiceAddressController.clear();
    _invoicePhoneController.clear();
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
        if (picked.isBusiness) {
          _syncInvoiceClientForm(picked);
        }
      });
    }
  }

  Future<void> _selectCheckoutMode(PaymentCheckoutMode mode) async {
    if (mode == _checkoutMode) return;

    if (mode == PaymentCheckoutMode.cotizacion) {
      final resolved = await widget.onDocumentTypeChanged(
        PaymentDocumentType.cotizacion,
      );
      if (!mounted || resolved != PaymentDocumentType.cotizacion) return;
      setState(() {
        _selectedDocumentType = resolved;
        _checkoutMode = PaymentCheckoutMode.cotizacion;
        _quoteOutputMode = QuoteOutputMode.save;
      });
      return;
    }

    if (mode == PaymentCheckoutMode.facturaElectronica) {
      if (!widget.allowElectronicInvoiceOption) return;
      final resolved = await widget.onDocumentTypeChanged(
        PaymentDocumentType.creditoFiscal,
      );
      if (!mounted || resolved != PaymentDocumentType.creditoFiscal) return;
      setState(() {
        _selectedDocumentType = resolved;
        _checkoutMode = PaymentCheckoutMode.facturaElectronica;
      });
      if (_selectedClient?.isBusiness == true) {
        _syncInvoiceClientForm(_selectedClient!);
      }
      return;
    }

    final resolved = await widget.onDocumentTypeChanged(
      PaymentDocumentType.consumidorFinal,
    );
    if (!mounted || resolved != PaymentDocumentType.consumidorFinal) return;
    setState(() {
      _selectedDocumentType = resolved;
      _checkoutMode = PaymentCheckoutMode.ventaLocal;
    });
  }

  void _selectElectronicCustomerType(PaymentElectronicCustomerType type) {
    if (type == _electronicCustomerType) return;
    setState(() {
      _electronicCustomerType = type;
      _showElectronicCompanyOptionalFields = false;
      if (type == PaymentElectronicCustomerType.consumidorFinal) {
        _saveInvoiceClient = false;
      } else if (_selectedClient?.isBusiness == true) {
        _syncInvoiceClientForm(_selectedClient!);
      }
    });
  }

  Future<void> _handleInvoiceRncChanged(String value) async {
    final requestId = ++_invoiceLookupRequestId;
    final normalized = RncValidator.normalize(value);

    if (value.trim().isEmpty) {
      setState(() {
        _invoiceMatchedClient = null;
        _invoiceLookupMessage = 'Ingrese RNC para factura empresarial';
        _invoiceLookupMessageIsError = false;
      });
      return;
    }

    if (normalized == null) {
      setState(() {
        _invoiceMatchedClient = null;
        _invoiceLookupMessage = 'RNC inválido. Debe contener 9 dígitos';
        _invoiceLookupMessageIsError = true;
      });
      return;
    }

    setState(() {
      _isLookingUpInvoiceClient = true;
      _invoiceLookupMessage = 'Buscando cliente en la base de datos...';
      _invoiceLookupMessageIsError = false;
    });

    final client = await ClientsRepository.getByRnc(normalized);
    if (!mounted || requestId != _invoiceLookupRequestId) return;

    setState(() {
      _isLookingUpInvoiceClient = false;
      if (client != null) {
        _syncInvoiceClientForm(client);
      } else {
        if (_invoiceMatchedClient != null &&
            _invoiceMatchedClient!.normalizedRnc != normalized) {
          _clearInvoiceClientFormForManualEntry();
        }
        _invoiceMatchedClient = null;
        _invoiceLookupMessage =
            'RNC no registrado. Complete los datos y active Guardar cliente si desea almacenarlo.';
        _invoiceLookupMessageIsError = false;
      }
    });
  }

  ClientModel _buildElectronicBusinessClientDraft() {
    final normalizedRnc = RncValidator.normalize(_invoiceRncController.text);
    final normalizedPhone = PhoneValidator.normalizeRDPhone(
      _invoicePhoneController.text.trim(),
    );

    return ClientModel(
      id: _invoiceMatchedClient?.id,
      nombre: _invoiceNameController.text.trim(),
      telefono: normalizedPhone,
      direccion: _invoiceAddressController.text.trim().isEmpty
          ? null
          : _invoiceAddressController.text.trim(),
      rnc: normalizedRnc,
      cedula: null,
      isActive: _invoiceMatchedClient?.isActive ?? true,
      hasCredit: _invoiceMatchedClient?.hasCredit ?? false,
      createdAtMs:
          _invoiceMatchedClient?.createdAtMs ??
          DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<ClientModel?> _resolveElectronicBusinessClient() async {
    final normalizedRnc = RncValidator.normalize(_invoiceRncController.text);
    if (normalizedRnc == null) {
      _showError('Ingrese un RNC válido para factura empresarial');
      return null;
    }

    final businessName = _invoiceNameController.text.trim();
    if (businessName.isEmpty) {
      _showError('Debe indicar nombre o razón social para factura empresarial');
      return null;
    }

    final rawPhone = _invoicePhoneController.text.trim();
    if (rawPhone.isNotEmpty &&
        PhoneValidator.normalizeRDPhone(rawPhone) == null) {
      _showError('Teléfono inválido. Use 10 dígitos RD o deje el campo vacío');
      return null;
    }

    final draft = _buildElectronicBusinessClientDraft();
    if (!_saveInvoiceClient) {
      return draft;
    }

    final existingByRnc = await ClientsRepository.getByRnc(normalizedRnc);
    if (existingByRnc != null) {
      final updated = existingByRnc.copyWith(
        nombre: draft.nombre,
        telefono: draft.telefono,
        direccion: draft.direccion,
        rnc: draft.rnc,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await ClientsRepository.update(updated);
      return (await ClientsRepository.getById(existingByRnc.id!)) ?? updated;
    }

    final createdId = await ClientsRepository.create(draft);
    return (await ClientsRepository.getById(createdId)) ??
        draft.copyWith(id: createdId);
  }

  PaymentDocumentType _resolvedDocumentType() {
    if (_isElectronicInvoiceMode) {
      return _electronicCustomerType == PaymentElectronicCustomerType.empresa
          ? PaymentDocumentType.creditoFiscal
          : PaymentDocumentType.consumidorFinal;
    }
    if (_isQuoteMode) {
      return PaymentDocumentType.cotizacion;
    }
    return _selectedDocumentType;
  }

  ClientModel? _resolvedSelectedClient({
    required ClientModel? resolvedElectronicClient,
  }) {
    if (_isElectronicInvoiceMode) {
      return _electronicCustomerType == PaymentElectronicCustomerType.empresa
          ? resolvedElectronicClient
          : null;
    }
    return _selectedClient;
  }

  Future<bool> _confirmElectronicInvoice({
    required PaymentDocumentType documentType,
    required ClientModel? client,
  }) async {
    final label = documentType == PaymentDocumentType.creditoFiscal
        ? 'E31'
        : 'E32';
    final clientLabel = documentType == PaymentDocumentType.creditoFiscal
        ? '${client?.nombre ?? ''} • RNC ${(client?.rnc ?? '').trim()}'
        : 'Consumidor final seleccionado';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar factura electrónica'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se generará un comprobante $label para esta venta.'),
            const SizedBox(height: 10),
            Text(clientLabel),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Generar factura'),
          ),
        ],
      ),
    );

    return confirmed == true;
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

    final isElectronicInvoiceRequested = _isElectronicInvoiceMode;
    ClientModel? resolvedElectronicClient;

    if (isElectronicInvoiceRequested) {
      if (_electronicCustomerType == PaymentElectronicCustomerType.empresa) {
        resolvedElectronicClient = await _resolveElectronicBusinessClient();
        if (resolvedElectronicClient == null) return;
      }
    }

    if (_isQuoteMode) {
      if (_selectedClient == null) {
        _showError('Debe seleccionar un cliente para generar la cotización');
        await _ensureClientSelected();
        return;
      }

      final validDays = int.tryParse(_quoteValidDaysController.text) ?? 0;
      if (validDays <= 0) {
        _showError('Debe indicar una vigencia válida para la cotización');
        return;
      }

      final result = {
        'paymentRequestId': paymentRequestId,
        'triggerSource': _lastTriggerSource,
        'documentType': PaymentDocumentType.cotizacion,
        'selectedClient': _selectedClient,
        'quoteOutputMode': _quoteOutputMode,
        'quoteValidDays': validDays,
        'quoteNotes': _noteController.text.trim(),
      };
      _closeDialog(result);
      return;
    }

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

    final resolvedDocumentType = _resolvedDocumentType();
    final resolvedSelectedClient = _resolvedSelectedClient(
      resolvedElectronicClient: resolvedElectronicClient,
    );

    if (isElectronicInvoiceRequested &&
        _electronicCustomerType == PaymentElectronicCustomerType.empresa &&
        !(resolvedElectronicClient?.isBusiness ?? false)) {
      _showError(
        'La factura electrónica E31 requiere un cliente de empresa con RNC',
      );
      return;
    }

    if (_downloadInvoicePdf) {
      if (resolvedSelectedClient == null) {
        _showError('Debe seleccionar un cliente para descargar la factura');
        await _ensureClientSelected();
        return;
      }
      final name = resolvedSelectedClient.nombre.trim();
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

    if (isElectronicInvoiceRequested) {
      final confirmed = await _confirmElectronicInvoice(
        documentType: resolvedDocumentType,
        client: resolvedSelectedClient,
      );
      if (!confirmed) return;
    }

    // Retornar resultado (cerrar el diálogo que lo presentó)
    final result = {
      'paymentRequestId': paymentRequestId,
      'triggerSource': _lastTriggerSource,
      'documentType': resolvedDocumentType,
      'selectedClient': resolvedSelectedClient,
      'electronicInvoiceRequested': isElectronicInvoiceRequested,
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

  Widget _buildCheckoutModeSelector() {
    Widget buildCard({
      required PaymentCheckoutMode mode,
      required String title,
      required String subtitle,
      required IconData icon,
      required double width,
    }) {
      final selected = _checkoutMode == mode;
      return SizedBox(
        width: width,
        child: InkWell(
          onTap: () => unawaited(_selectCheckoutMode(mode)),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withOpacity(0.10)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: scheme.onSurface.withAlpha(175),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de comprobante',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final optionCount = widget.allowElectronicInvoiceOption ? 3 : 2;
            final isCompact = constraints.maxWidth < 760;
            final spacing = 8.0;
            final cardWidth = isCompact
                ? constraints.maxWidth
                : (constraints.maxWidth - (spacing * (optionCount - 1))) /
                      optionCount;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                buildCard(
                  mode: PaymentCheckoutMode.ventaLocal,
                  title: 'Venta normal',
                  subtitle: 'Cobro rápido sin emisión DGII',
                  icon: Icons.point_of_sale_rounded,
                  width: cardWidth,
                ),
                if (widget.allowElectronicInvoiceOption)
                  buildCard(
                    mode: PaymentCheckoutMode.facturaElectronica,
                    title: 'Factura electrónica',
                    subtitle: 'Emitir E31 o E32 automáticamente',
                    icon: Icons.receipt_long_rounded,
                    width: cardWidth,
                  ),
                buildCard(
                  mode: PaymentCheckoutMode.cotizacion,
                  title: 'Cotización',
                  subtitle: 'Guardar propuesta sin cobrar',
                  icon: Icons.request_quote_outlined,
                  width: cardWidth,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildElectronicInvoiceClientPanel() {
    final showLookupState = _invoiceLookupMessage?.trim().isNotEmpty == true;
    final isBusiness =
        _electronicCustomerType == PaymentElectronicCustomerType.empresa;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withOpacity(0.03),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tipo de cliente',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 680;
              final optionWidth = stacked
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _ElectronicCustomerTypeOption(
                    width: optionWidth,
                    title: 'Consumidor final',
                    subtitle: 'No se pedirá RNC. Se generará E32.',
                    value: PaymentElectronicCustomerType.consumidorFinal,
                    groupValue: _electronicCustomerType,
                    onChanged: _selectElectronicCustomerType,
                  ),
                  _ElectronicCustomerTypeOption(
                    width: optionWidth,
                    title: 'Empresa / negocio',
                    subtitle: 'RNC y razón social obligatorios. E31.',
                    value: PaymentElectronicCustomerType.empresa,
                    groupValue: _electronicCustomerType,
                    onChanged: _selectElectronicCustomerType,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          if (!isBusiness)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.tertiary.withOpacity(0.35)),
              ),
              child: Text(
                'Consumidor final seleccionado. Se generará un comprobante E32 automáticamente y no se solicitará RNC.',
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            )
          else ...[
            TextFormField(
              controller: _invoiceRncController,
              keyboardType: TextInputType.number,
              onChanged: (value) => unawaited(_handleInvoiceRncChanged(value)),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'RNC *',
                hintText: 'Ingrese RNC para factura empresarial',
                prefixIcon: const Icon(Icons.business_rounded),
                suffixIcon: _isLookingUpInvoiceClient
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _invoiceNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre o razón social *',
                prefixIcon: Icon(Icons.apartment_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _showElectronicCompanyOptionalFields =
                            !_showElectronicCompanyOptionalFields;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    child: Text(
                      _showElectronicCompanyOptionalFields
                          ? 'Ver menos'
                          : 'Ver más',
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() => _saveInvoiceClient = !_saveInvoiceClient);
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      backgroundColor: _saveInvoiceClient
                          ? scheme.primary.withOpacity(0.18)
                          : null,
                    ),
                    child: Text(_saveInvoiceClient ? 'Guardar: Sí' : 'Guardar'),
                  ),
                ],
              ),
            ),
            if (_showElectronicCompanyOptionalFields) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _invoiceAddressController,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _invoicePhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (showLookupState) ...[
              const SizedBox(height: 4),
              Text(
                _invoiceLookupMessage!,
                style: TextStyle(
                  color: _invoiceLookupMessageIsError
                      ? scheme.error
                      : scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _dialogTitle() {
    if (_isQuoteMode) return 'GENERAR COTIZACIÓN';
    return 'PROCESAR PAGO';
  }

  String _dialogSubtitle() {
    if (_isQuoteMode) {
      return 'Configure los datos de la propuesta antes de guardarla';
    }
    return '';
  }

  IconData _dialogIcon() {
    if (_isQuoteMode) return Icons.request_quote_outlined;
    return Icons.payment;
  }

  void _selectQuoteOutput(QuoteOutputMode mode) {
    setState(() => _quoteOutputMode = mode);
  }

  Widget _buildClientPanel() {
    final clientLabel = (_selectedClient?.nombre ?? 'Sin cliente seleccionado')
        .trim();
    final secondary = [
      (_selectedClient?.telefono ?? '').trim(),
      (_selectedClient?.rnc ?? '').trim(),
      (_selectedClient?.cedula ?? '').trim(),
    ].where((value) => value.isNotEmpty).join('  •  ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.person_outline, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CLIENTE DE LA COTIZACIÓN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withAlpha(170),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  clientLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    secondary,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withAlpha(170),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: _ensureClientSelected,
            icon: const Icon(Icons.search, size: 18),
            label: Text(_selectedClient == null ? 'Seleccionar' : 'Cambiar'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteModeBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withOpacity(0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: scheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'La cotización no registra pago. Solo guarda la propuesta comercial con su cliente, vigencia y observaciones.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildClientPanel(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _quoteValidDaysController,
                decoration: const InputDecoration(
                  labelText: 'VIGENCIA (DÍAS)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event_available_outlined),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _noteController,
          decoration: const InputDecoration(
            labelText: 'NOTAS / CONDICIONES',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.note_alt_outlined),
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width * 0.88).clamp(520.0, 860.0);
    final dialogMaxHeight = (viewport.height * 0.93).clamp(700.0, 980.0);

    return DialogKeyboardShortcuts(
      onSubmit: () => _submitPayment(source: 'keyboard_enter'),
      enableSubmitShortcuts: true,
      enableDismissShortcut: false,
      child: Dialog(
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: dialogMaxHeight),
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
                    Icon(_dialogIcon(), color: scheme.onPrimary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dialogTitle(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimary,
                            ),
                          ),
                          if (_dialogSubtitle().isNotEmpty)
                            Text(
                              _dialogSubtitle(),
                              style: TextStyle(
                                color: scheme.onPrimary.withAlpha(179),
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
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
                          color: _isQuoteMode
                              ? scheme.primaryContainer
                              : scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isQuoteMode
                                ? scheme.primary
                                : scheme.secondary,
                            width: 2,
                          ),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runSpacing: 8,
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isQuoteMode
                                      ? Icons.description_outlined
                                      : Icons.attach_money,
                                  color: _isQuoteMode
                                      ? scheme.primary
                                      : scheme.secondary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isQuoteMode
                                      ? 'TOTAL COTIZADO:'
                                      : 'TOTAL A PAGAR:',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _isQuoteMode
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              CurrencyDisplay.format(widget.total),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _isQuoteMode
                                    ? scheme.primary
                                    : scheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      _buildCheckoutModeSelector(),

                      const SizedBox(height: 16),

                      if (_isElectronicInvoiceMode) ...[
                        _buildElectronicInvoiceClientPanel(),
                        const SizedBox(height: 16),
                      ],

                      if (_isQuoteMode) ...[
                        _buildQuoteModeBody(),
                      ] else ...[
                        // Sección de Recibido y Devuelta
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            children: [
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
                                      _selectedMethod == PaymentMethod.layaway
                                          ? 'ABONO INICIAL:'
                                          : 'CLIENTE PAGA CON:',
                                      style: const TextStyle(
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
                                        hintText: widget.total.toStringAsFixed(
                                          2,
                                        ),
                                        hintStyle: TextStyle(
                                          color: scheme.onSurface.withAlpha(
                                            102,
                                          ),
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _change > 0
                                      ? status.success.withAlpha(51)
                                      : (_change < 0
                                            ? status.error.withAlpha(51)
                                            : scheme.surfaceContainerHighest),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        runSpacing: 8,
                                        spacing: 12,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
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
                                                                .withAlpha(
                                                                  153,
                                                                )),
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
                                            CurrencyDisplay.format(
                                              _change.abs(),
                                            ),
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
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
                        if (_selectedMethod == PaymentMethod.cash) ...[
                          // Solo el efectivo, la devuelta ya se muestra arriba
                          const SizedBox.shrink(),
                        ] else if (_selectedMethod == PaymentMethod.card) ...[
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
                        ] else if (_selectedMethod == PaymentMethod.mixed) ...[
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
                          Text(
                            'Solo se permite Efectivo + Tarjeta o Efectivo + Transferencia.',
                            style: TextStyle(
                              color: scheme.onSurface.withAlpha(170),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
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
                              children: [
                                Expanded(
                                  child: Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    runSpacing: 8,
                                    spacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      const Text(
                                        'DIFERENCIA:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        CurrencyDisplay.format(_change),
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
                              ],
                            ),
                          ),
                        ] else if (_selectedMethod == PaymentMethod.credit) ...[
                          // Cliente
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: scheme.outlineVariant),
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
                                        (_selectedClient?.nombre ?? 'NINGUNO')
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
                                    prefixIcon: Icon(Icons.stacked_line_chart),
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
                                            color: scheme.onSurface.withAlpha(
                                              153,
                                            ),
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
                                  const Icon(Icons.arrow_forward_ios, size: 16),
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
                              border: Border.all(color: scheme.outlineVariant),
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (_isQuoteMode) {
                          return _buildOutputSwitchRow(
                            constraints: constraints,
                            children: [
                              _buildOutputSwitchCard(
                                label: 'GUARDAR',
                                subtitle: 'Registrar cotización',
                                icon: Icons.save_outlined,
                                value: _quoteOutputMode == QuoteOutputMode.save,
                                onChanged: (enabled) {
                                  if (enabled) {
                                    _selectQuoteOutput(QuoteOutputMode.save);
                                  }
                                },
                              ),
                              _buildOutputSwitchCard(
                                label: 'VISTA PREVIA',
                                subtitle: 'Guardar y mostrar PDF',
                                icon: Icons.visibility_outlined,
                                value:
                                    _quoteOutputMode == QuoteOutputMode.preview,
                                onChanged: (enabled) {
                                  if (enabled) {
                                    _selectQuoteOutput(QuoteOutputMode.preview);
                                  }
                                },
                              ),
                              _buildOutputSwitchCard(
                                label: 'IMPRIMIR',
                                subtitle: 'Guardar e imprimir',
                                icon: Icons.print_outlined,
                                value:
                                    _quoteOutputMode == QuoteOutputMode.print,
                                onChanged: (enabled) {
                                  if (enabled) {
                                    _selectQuoteOutput(QuoteOutputMode.print);
                                  }
                                },
                              ),
                            ],
                          );
                        }
                        return _buildOutputSwitchRow(
                          constraints: constraints,
                          children: [
                            _buildOutputSwitchCard(
                              label: 'TICKET',
                              subtitle: 'Cobrar e imprimir',
                              icon: Icons.print,
                              value: _outputMode == PaymentOutputMode.ticket,
                              onChanged: (enabled) {
                                if (enabled) _selectPrint();
                              },
                            ),
                            _buildOutputSwitchCard(
                              label: 'PDF',
                              subtitle: 'Cobrar y descargar',
                              icon: Icons.download,
                              value: _outputMode == PaymentOutputMode.pdf,
                              enabled: widget.allowInvoicePdfDownload,
                              onChanged: (enabled) {
                                if (enabled) _selectDownloadInvoicePdf();
                              },
                            ),
                            _buildOutputSwitchCard(
                              label: 'SIN IMPRIMIR',
                              subtitle: 'Solo cobrar',
                              icon: Icons.block,
                              value: _outputMode == PaymentOutputMode.none,
                              onChanged: (enabled) {
                                if (enabled) _selectWithoutPrinting();
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isQuoteMode
                          ? 'Atajos: Enter/F9 = Guardar cotización  ·  Esc = Salir'
                          : 'Atajos: Enter/F9 = Cobrar  ·  Esc = Salir',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withAlpha(170),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.end,
                      runSpacing: 10,
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: _isProcessingPayment
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          child: const Text('CANCELAR'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isProcessingPayment
                              ? null
                              : () => _submitPayment(source: 'mouse_click'),
                          icon: Icon(_chargeActionIcon()),
                          label: Text(_chargeActionLabel()),
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

  String _chargeActionLabel() {
    if (_isQuoteMode) {
      return 'GUARDAR COTIZACIÓN';
    }
    switch (_outputMode) {
      case PaymentOutputMode.ticket:
        return 'COBRAR E IMPRIMIR';
      case PaymentOutputMode.pdf:
        return 'COBRAR Y DESCARGAR';
      case PaymentOutputMode.none:
        return 'COBRAR SIN IMPRIMIR';
    }
  }

  IconData _chargeActionIcon() {
    if (_isQuoteMode) {
      return Icons.request_quote_outlined;
    }
    switch (_outputMode) {
      case PaymentOutputMode.ticket:
        return Icons.print;
      case PaymentOutputMode.pdf:
        return Icons.download;
      case PaymentOutputMode.none:
        return Icons.check_circle_outline;
    }
  }

  Widget _buildOutputSwitchRow({
    required BoxConstraints constraints,
    required List<Widget> children,
  }) {
    final minCardWidth = constraints.maxWidth >= 760
        ? (constraints.maxWidth - 24) / 3
        : 220.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            SizedBox(width: minCardWidth, child: children[index]),
            if (index != children.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildOutputSwitchCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final textColor = enabled
        ? scheme.onSurface
        : scheme.onSurface.withAlpha(120);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? scheme.primary : scheme.outlineVariant,
          width: value ? 1.8 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (value ? scheme.primary : scheme.outlineVariant).withAlpha(
                28,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value ? scheme.primary : textColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: textColor.withAlpha(210),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.84,
            child: Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: scheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
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

class _ElectronicCustomerTypeOption extends StatelessWidget {
  const _ElectronicCustomerTypeOption({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final double width;
  final String title;
  final String subtitle;
  final PaymentElectronicCustomerType value;
  final PaymentElectronicCustomerType groupValue;
  final ValueChanged<PaymentElectronicCustomerType> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = value == groupValue;

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withOpacity(0.08)
                : scheme.surfaceContainerHighest.withOpacity(0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Radio<PaymentElectronicCustomerType>(
                  value: value,
                  groupValue: groupValue,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (next) {
                    if (next != null) onChanged(next);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        color: scheme.onSurface.withAlpha(175),
                      ),
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
}
