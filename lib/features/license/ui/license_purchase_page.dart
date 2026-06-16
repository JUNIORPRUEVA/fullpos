import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/session/session_manager.dart';
import '../../../core/window/window_service.dart';
import '../../registration/services/business_identity_storage.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/data/business_settings_repository.dart';
import '../license_config.dart';
import '../services/bank_transfer_whatsapp.dart';
import '../services/license_controller.dart';
import '../services/license_payment_api.dart';
import '../services/license_storage.dart';

const _purchaseBgTop = Color(0xFFF8FBFF);
const _purchaseBgBottom = Color(0xFFEAF1F8);
const _purchaseInk = Color(0xFF142033);
const _purchaseMuted = Color(0xFF637188);
const _purchaseSoft = Color(0xFF97A4B8);
const _purchaseLine = Color(0xFFD9E2EE);
const _purchasePanel = Color(0xFFFDFEFF);
const _purchasePanelSoft = Color(0xFFF5F8FC);
const _purchasePrimary = Color(0xFF153E75);
const _purchasePrimaryBright = Color(0xFF2563EB);
const _purchasePrimaryTint = Color(0xFFEAF2FF);
const _purchaseAccent = Color(0xFFB96534);
const _purchaseDisabledBg = Color(0xFFE7EDF5);
const _purchaseDisabledFg = Color(0xFF75839A);

enum _LicensePaymentMethod { paypal, bankTransfer }

class LicensePurchasePage extends ConsumerStatefulWidget {
  const LicensePurchasePage({super.key});

  @override
  ConsumerState<LicensePurchasePage> createState() =>
      _LicensePurchasePageState();
}

class _LicensePurchasePageState extends ConsumerState<LicensePurchasePage> {
  final _businessNameCtrl = TextEditingController();
  final _businessTypeCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _settingsRepo = BusinessSettingsRepository();
  final _identityStorage = BusinessIdentityStorage();
  final _licenseStorage = LicenseStorage();
  final _paymentApi = LicensePaymentApi();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _businessId;
  String? _deviceId;
  String? _selectedBusinessType;
  LicenseBillingInfo? _billingInfo;
  int _selectedMonths = 3;
  LicensePaymentOrder? _pendingOrder;
  _LicensePaymentMethod _paymentMethod = _LicensePaymentMethod.paypal;
  String _selectedBank = dominicanBanks.first;
  bool _confirmedDominicanRepublic = false;
  bool _businessDataExpanded = false;

  static const _nicheOptions = <String>[
    'Colmado',
    'Mini market',
    'Supermercado',
    'Ferretería',
    'Farmacia',
    'Tienda de ropa',
    'Tienda de electrónicos',
    'Licorería',
    'Papelería',
    'Panadería',
    'Restaurante',
    'Otro',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessTypeCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await _identityStorage.getOnboardingProfile();
      final settings = await _settingsRepo.loadSettings();
      final businessId = await _identityStorage.getBusinessId();
      final deviceId =
          (await _licenseStorage.getDeviceId()) ??
          await SessionManager.ensureTerminalId();
      await _licenseStorage.setDeviceId(deviceId);

      _seedFields(settings, profile);

      final billing = await _paymentApi.getBillingInfo(
        baseUrl: kLicenseBackendBaseUrl,
        projectCode: kFullposProjectCode,
      );
      final minMonths = billing.minPurchaseMonths < 1
          ? 1
          : billing.minPurchaseMonths;
      final currentOrderId = await _licenseStorage.getLastRenewalOrderId();
      final currentPaypalOrderId = await _licenseStorage.getLastPaypalOrderId();

      if (!mounted) return;
      final normalizedBusinessId = (businessId ?? '').trim();
      final normalizedOrderId = (currentOrderId ?? '').trim();
      final normalizedPaypalOrderId = (currentPaypalOrderId ?? '').trim();
      setState(() {
        _businessId = normalizedBusinessId.isEmpty
            ? null
            : normalizedBusinessId;
        _deviceId = deviceId;
        _billingInfo = billing;
        _selectedMonths = [
          3,
          6,
          9,
          12,
        ].firstWhere((months) => months >= minMonths, orElse: () => minMonths);
        if (normalizedOrderId.isNotEmpty &&
            normalizedPaypalOrderId.isNotEmpty) {
          _pendingOrder = LicensePaymentOrder(
            paymentOrderId: normalizedOrderId,
            paypalOrderId: normalizedPaypalOrderId,
            checkoutUrl: '',
            amount: 0,
            currency: billing.currency,
            months: _selectedMonths,
            monthlyPrice: billing.monthlyPrice,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _seedFields(
    BusinessSettings settings,
    BusinessOnboardingProfile? profile,
  ) {
    final profileBusinessName = (profile?.businessName ?? '').trim();
    final profileBusinessType = (profile?.role ?? '').trim();
    final profileOwnerName = (profile?.ownerName ?? '').trim();
    final profilePhone = (profile?.phone ?? '').trim();
    final profileEmail = (profile?.email ?? '').trim();
    final settingsBusinessName = settings.businessName.trim();
    final settingsPhone = (settings.phone ?? '').trim();
    final settingsEmail = (settings.email ?? '').trim();

    _businessNameCtrl.text = profileBusinessName.isNotEmpty
        ? profileBusinessName
        : settingsBusinessName;
    _businessTypeCtrl.text = profileBusinessType;
    _ownerNameCtrl.text = profileOwnerName;
    _phoneCtrl.text = profilePhone.isNotEmpty ? profilePhone : settingsPhone;
    _emailCtrl.text = profileEmail.isNotEmpty ? profileEmail : settingsEmail;
    _selectedBusinessType = _nicheOptions.contains(profileBusinessType)
        ? profileBusinessType
        : null;
  }

  Future<void> _openCheckout(String checkoutUrl) async {
    if (checkoutUrl.trim().isEmpty) return;
    await WindowService.runWithExternalApplication(() async {
      await WindowService.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await launchUrlString(checkoutUrl, mode: LaunchMode.externalApplication);
    });
  }

  bool get _hasRequiredBusinessData {
    return _businessNameCtrl.text.trim().isNotEmpty &&
        _businessTypeCtrl.text.trim().isNotEmpty &&
        _ownerNameCtrl.text.trim().isNotEmpty &&
        _phoneCtrl.text.trim().isNotEmpty;
  }

  void _showRequiredBusinessDataError() {
    setState(() {
      _businessDataExpanded = true;
      _error = 'Completa negocio, tipo, representante y WhatsApp.';
    });
  }

  Future<void> _createOrder() async {
    final businessName = _businessNameCtrl.text.trim();
    final businessType = _businessTypeCtrl.text.trim();
    final ownerName = _ownerNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final deviceId = (_deviceId ?? '').trim();
    final billing = _billingInfo;

    if (businessName.isEmpty ||
        businessType.isEmpty ||
        ownerName.isEmpty ||
        phone.isEmpty) {
      _showRequiredBusinessDataError();
      return;
    }

    if (deviceId.isEmpty || billing == null) {
      setState(() {
        _error =
            'No se pudo preparar la compra. Verifica la conexión e intenta de nuevo.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final order = await _paymentApi.createPaypalOrder(
        baseUrl: kLicenseBackendBaseUrl,
        projectCode: kFullposProjectCode,
        deviceId: deviceId,
        months: _selectedMonths,
        businessName: businessName,
        phone: phone,
        email: email.isEmpty ? null : email,
      );
      await _licenseStorage.setLastRenewalOrderId(order.paymentOrderId);
      await _licenseStorage.setLastPaypalOrderId(order.paypalOrderId);
      if (!mounted) return;
      setState(() {
        _pendingOrder = order;
      });
      await _openCheckout(order.checkoutUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _verifyPaymentNow() async {
    final order = _pendingOrder;
    if (order == null) {
      setState(() {
        _error = 'Primero debes crear una orden de compra.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _paymentApi.capturePaypalOrder(
        baseUrl: kLicenseBackendBaseUrl,
        paymentOrderId: order.paymentOrderId,
        paypalOrderId: order.paypalOrderId,
      );
    } catch (e) {
      final message = e.toString();
      final alreadyProcessed =
          message.contains('409') || message.contains('ya fue pagada');
      if (!alreadyProcessed) {
        if (!mounted) return;
        setState(() {
          _error = message;
        });
        setState(() {
          _submitting = false;
        });
        return;
      }
    }

    final controller = ref.read(licenseControllerProvider.notifier);
    await controller.syncBusinessLicenseNow();
    final state = ref.read(licenseControllerProvider);
    if (!mounted) return;

    if (state.info?.isActive == true && state.info?.isExpired == false) {
      await _licenseStorage.setLastRenewalOrderId(null);
      await _licenseStorage.setLastPaypalOrderId(null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Licencia verificada y activada correctamente.'),
        ),
      );
      context.go('/login');
    } else {
      setState(() {
        _error =
            'El pago todavía no ha sido confirmado por el backend. Intenta verificar de nuevo en unos momentos.';
      });
    }

    setState(() {
      _submitting = false;
    });
  }

  Future<void> _requestBankTransfer() async {
    final businessName = _businessNameCtrl.text.trim();
    final businessType = _businessTypeCtrl.text.trim();
    final ownerName = _ownerNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final deviceId = (_deviceId ?? '').trim();
    final billing = _billingInfo;

    if (!_confirmedDominicanRepublic) {
      setState(() {
        _error =
            'La transferencia bancaria está disponible solo para clientes en República Dominicana.';
      });
      return;
    }
    if (businessName.isEmpty ||
        businessType.isEmpty ||
        ownerName.isEmpty ||
        phone.isEmpty) {
      _showRequiredBusinessDataError();
      return;
    }

    if (deviceId.isEmpty || billing == null) {
      setState(() {
        _error =
            'No se pudo preparar la solicitud. Verifica la conexión e intenta de nuevo.';
      });
      return;
    }

    await _saveOnboardingDataLocally();
    final uri = buildBankTransferWhatsappUri(
      programName: 'FullPOS',
      bankName: _selectedBank,
      months: _selectedMonths,
      amount: billing.monthlyPrice * _selectedMonths,
      currency: billing.currency,
      businessName: businessName,
      deviceId: deviceId,
    );
    final opened = await launchUrlString(
      uri.toString(),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() {
        _error = 'No se pudo abrir WhatsApp. Comunícate al 1 849 431 4070.';
      });
    }
  }

  Future<void> _saveOnboardingDataLocally() async {
    final businessName = _businessNameCtrl.text.trim();
    final businessType = _businessTypeCtrl.text.trim();
    final ownerName = _ownerNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final profile = await _identityStorage.getOnboardingProfile();
    final storedBusinessName = (profile?.businessName ?? '').trim();

    if (businessName.isEmpty ||
        businessType.isEmpty ||
        ownerName.isEmpty ||
        phone.isEmpty) {
      return;
    }

    await _identityStorage.saveBusinessProfile(
      businessName: storedBusinessName.isNotEmpty
          ? storedBusinessName
          : businessName,
      role: businessType,
      ownerName: ownerName,
      phone: phone,
      email: email.isEmpty ? null : email,
    );
    await _identityStorage.setOnboardingCompleted(true);

    final currentSettings = await _settingsRepo.loadSettings();
    final updatedSettings = currentSettings.copyWith(
      businessName:
          currentSettings.businessName.trim().isEmpty ||
              currentSettings.businessName.trim() == 'FULLPOS'
          ? businessName
          : currentSettings.businessName,
      phone: (currentSettings.phone ?? '').trim().isEmpty
          ? phone
          : currentSettings.phone,
      email: (currentSettings.email ?? '').trim().isEmpty && email.isNotEmpty
          ? email
          : currentSettings.email,
    );
    await _settingsRepo.saveSettings(updatedSettings);
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/license');
  }

  @override
  Widget build(BuildContext context) {
    final billing = _billingInfo;
    final pendingOrder = _pendingOrder;

    return Scaffold(
      backgroundColor: _purchaseBgTop,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_purchaseBgTop, _purchaseBgBottom],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildLoadedContent(
                  billing: billing,
                  pendingOrder: pendingOrder,
                ),
        ),
      ),
    );
  }

  Widget _buildLoadedContent({
    required LicenseBillingInfo? billing,
    required LicensePaymentOrder? pendingOrder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _purchasePanel,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.8)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120E1A2B),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: _goBack,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _purchaseInk,
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Comprar licencia',
                                  style: TextStyle(
                                    color: _purchaseInk,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Elige PayPal o transferencia bancaria y completa tu compra.',
                                  style: TextStyle(
                                    color: _purchaseMuted,
                                    fontSize: 12.8,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_error != null) ...[
                        _buildErrorBanner(_error!),
                        const SizedBox(height: 12),
                      ],
                      _buildBusinessDataPanel(),
                      const SizedBox(height: 12),
                      _buildCard(
                        title: 'Identidad de compra',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _dataChip(
                              'Business ID',
                              _businessId ?? 'Pendiente',
                            ),
                            _dataChip('Device ID', _deviceId ?? 'Pendiente'),
                            _dataChip(
                              'Proyecto',
                              billing?.projectCode ?? kFullposProjectCode,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildCard(
                        title: 'Tiempo de licencia',
                        subtitle: billing == null
                            ? 'No se pudo consultar la configuración del proyecto.'
                            : 'Mínimo ${billing.minPurchaseMonths} meses. Puedes elegir más según lo que necesites.',
                        child: _buildDurationSelector(billing: billing),
                      ),
                      const SizedBox(height: 12),
                      _buildPurchaseCtaCard(pendingOrder),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPurchaseCtaCard(LicensePaymentOrder? pendingOrder) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF2E8), Color(0xFFFFFBF7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D7C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Comprar ahora',
            style: TextStyle(
              color: _purchaseInk,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'PayPal activa automáticamente. Las transferencias se confirman por WhatsApp antes de activar la licencia.',
            style: TextStyle(
              color: _purchaseMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _buildPaymentMethodSelector(),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.985, end: 1),
            duration: const Duration(milliseconds: 1400),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: FilledButton.icon(
              onPressed:
                  _submitting ||
                      (_paymentMethod == _LicensePaymentMethod.bankTransfer &&
                          !_confirmedDominicanRepublic)
                  ? null
                  : () async {
                      if (_paymentMethod ==
                          _LicensePaymentMethod.bankTransfer) {
                        await _requestBankTransfer();
                      } else {
                        await _saveOnboardingDataLocally();
                        await _createOrder();
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: _purchaseAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _purchaseDisabledBg,
                disabledForegroundColor: _purchaseDisabledFg,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                elevation: 0,
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _paymentMethod == _LicensePaymentMethod.bankTransfer
                          ? Icons.chat_rounded
                          : Icons.shopping_cart_checkout_rounded,
                    ),
              label: Text(
                _submitting
                    ? 'Procesando...'
                    : _paymentMethod == _LicensePaymentMethod.bankTransfer
                    ? 'Solicitar transferencia por WhatsApp'
                    : 'Pagar con PayPal',
              ),
            ),
          ),
          if (pendingOrder != null) ...[
            const SizedBox(height: 10),
            _buildOutlineAction(
              label: 'Ya pagué, verificar ahora',
              icon: Icons.verified_outlined,
              onPressed: _submitting
                  ? null
                  : () async {
                      await _verifyPaymentNow();
                    },
            ),
            if (pendingOrder.checkoutUrl.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildOutlineAction(
                label: 'Abrir PayPal otra vez',
                icon: Icons.open_in_new_rounded,
                onPressed: _submitting
                    ? null
                    : () => _openCheckout(pendingOrder.checkoutUrl),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.82),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _purchaseLine),
              ),
              child: Text(
                'Orden local: ${pendingOrder.paymentOrderId}\nPayPal: ${pendingOrder.paypalOrderId}',
                style: const TextStyle(
                  color: _purchaseMuted,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    final transferSelected =
        _paymentMethod == _LicensePaymentMethod.bankTransfer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Método de pago',
          style: TextStyle(
            color: _purchaseInk,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<_LicensePaymentMethod>(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _purchasePrimary;
              }
              return Colors.white;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return _purchaseInk;
            }),
            iconColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return _purchasePrimaryBright;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const BorderSide(color: _purchasePrimary);
              }
              return const BorderSide(color: _purchaseLine);
            }),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          segments: const [
            ButtonSegment(
              value: _LicensePaymentMethod.paypal,
              icon: Icon(Icons.credit_card_rounded),
              label: Text('PayPal'),
            ),
            ButtonSegment(
              value: _LicensePaymentMethod.bankTransfer,
              icon: Icon(Icons.account_balance_rounded),
              label: Text('Transferencia'),
            ),
          ],
          selected: {_paymentMethod},
          onSelectionChanged: (selection) {
            setState(() => _paymentMethod = selection.first);
          },
        ),
        if (transferSelected) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedBank,
            dropdownColor: Colors.white,
            style: const TextStyle(
              color: _purchaseInk,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            iconEnabledColor: _purchasePrimary,
            decoration: InputDecoration(
              labelText: 'Banco',
              labelStyle: const TextStyle(color: _purchaseMuted),
              prefixIcon: const Icon(
                Icons.account_balance_outlined,
                color: _purchasePrimaryBright,
              ),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _purchaseLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: _purchasePrimaryBright,
                  width: 1.5,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            items: dominicanBanks
                .map(
                  (bank) => DropdownMenuItem(
                    value: bank,
                    child: Text(
                      bank,
                      style: const TextStyle(
                        color: _purchaseInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selectedBank = value);
            },
          ),
          CheckboxListTile(
            value: _confirmedDominicanRepublic,
            onChanged: (value) {
              setState(() => _confirmedDominicanRepublic = value ?? false);
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _purchasePrimary,
            title: const Text(
              'Confirmo que estoy en República Dominicana',
              style: TextStyle(
                color: _purchaseInk,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Disponible para Banreservas, BHD y Popular.',
              style: TextStyle(color: _purchaseMuted, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBusinessDataPanel() {
    final complete = _hasRequiredBusinessData;
    final statusColor = complete ? const Color(0xFF059669) : _purchaseAccent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _purchasePanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _businessDataExpanded ? _purchasePrimaryBright : _purchaseLine,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() => _businessDataExpanded = !_businessDataExpanded);
            },
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    complete
                        ? Icons.check_circle_outline_rounded
                        : Icons.edit_note_rounded,
                    color: statusColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Datos del negocio',
                        style: TextStyle(
                          color: _purchaseInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        complete
                            ? 'Listos para comprar. Toca para revisar.'
                            : 'Faltan datos obligatorios. Toca para completar.',
                        style: const TextStyle(
                          color: _purchaseMuted,
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _businessDataExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: _purchaseMuted,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                children: [
                  _buildTextField(
                    controller: _businessNameCtrl,
                    label: 'Nombre del negocio',
                    hint: 'Ej: Comercial Núcleo',
                    icon: Icons.storefront_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildBusinessTypeDropdown(),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _ownerNameCtrl,
                    label: 'Representante',
                    hint: 'Nombre del responsable',
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _phoneCtrl,
                    label: 'WhatsApp',
                    hint: '809 555 5555',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _emailCtrl,
                    label: 'Correo electrónico opcional',
                    hint: 'Opcional',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
            crossFadeState: _businessDataExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 190),
            firstCurve: Curves.easeOutCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelector({required LicenseBillingInfo? billing}) {
    final minMonths = billing == null
        ? 3
        : (billing.minPurchaseMonths < 3 ? 3 : billing.minPurchaseMonths);
    final maxMonths = minMonths > 36 ? minMonths : 36;
    final selected = _selectedMonths.clamp(minMonths, maxMonths).toInt();
    final monthlyPrice = billing?.monthlyPrice;
    final currency = billing?.currency ?? 'USD';
    final total = monthlyPrice == null ? null : monthlyPrice * selected;
    final quickOptions = <int>{
      minMonths,
      6,
      12,
      24,
    }.where((months) => months >= minMonths && months <= maxMonths).toList();

    void selectMonths(int value) {
      final next = value.clamp(minMonths, maxMonths).toInt();
      setState(() => _selectedMonths = next);
    }

    if (_selectedMonths != selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedMonths = selected);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickOptions
              .map(
                (months) => ChoiceChip(
                  label: Text(
                    months == 12 ? '12 meses recomendado' : '$months meses',
                  ),
                  selected: selected == months,
                  onSelected: (_) => selectMonths(months),
                  selectedColor: _purchasePrimary,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected == months ? Colors.white : _purchaseInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                  side: BorderSide(
                    color: selected == months
                        ? _purchasePrimary
                        : _purchaseLine,
                  ),
                  showCheckmark: false,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _purchaseLine),
          ),
          child: Row(
            children: [
              _monthStepButton(
                icon: Icons.remove_rounded,
                enabled: selected > minMonths,
                onTap: () => selectMonths(selected - 1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$selected meses',
                      style: const TextStyle(
                        color: _purchaseInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Más meses, menos renovaciones.',
                      style: TextStyle(
                        color: _purchaseMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _monthStepButton(
                icon: Icons.add_rounded,
                enabled: selected < maxMonths,
                onTap: () => selectMonths(selected + 1),
              ),
            ],
          ),
        ),
        if (billing != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _purchasePrimaryTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Precio mensual: ${billing.monthlyPrice.toStringAsFixed(2)} ${billing.currency}',
                    style: const TextStyle(
                      color: _purchaseMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Total: ${total!.toStringAsFixed(2)} $currency',
                  style: const TextStyle(
                    color: _purchaseInk,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _monthStepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      style: IconButton.styleFrom(
        backgroundColor: enabled ? _purchasePrimary : _purchaseDisabledBg,
        foregroundColor: enabled ? Colors.white : _purchaseDisabledFg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      icon: Icon(icon),
    );
  }

  Widget _buildCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _purchasePanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purchaseLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _purchaseInk,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: _purchaseMuted,
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      cursorColor: _purchasePrimaryBright,
      style: const TextStyle(
        color: _purchaseInk,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(icon, size: 18, color: _purchaseSoft),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          color: _purchaseMuted,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: _purchaseSoft,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _purchaseLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _purchasePrimaryBright,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedBusinessType,
      borderRadius: BorderRadius.circular(14),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.expand_more_rounded, color: _purchaseSoft),
      style: const TextStyle(
        color: _purchaseInk,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Tipo de negocio',
        hintText: 'Selecciona una categoría',
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(Icons.category_outlined, size: 18, color: _purchaseSoft),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          color: _purchaseMuted,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: _purchaseSoft,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _purchaseLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _purchasePrimaryBright,
            width: 1.5,
          ),
        ),
      ),
      items: _nicheOptions
          .map(
            (niche) =>
                DropdownMenuItem<String>(value: niche, child: Text(niche)),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedBusinessType = value;
          _businessTypeCtrl.text = value ?? '';
        });
      },
    );
  }

  Widget _buildOutlineAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _purchaseInk,
        side: const BorderSide(color: _purchaseLine),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF4CFCF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFD14343),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFD14343),
                fontSize: 12.8,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataChip(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _purchaseLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _purchaseSoft,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: _purchaseInk,
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
