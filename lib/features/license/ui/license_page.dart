import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/config/app_config.dart';
import '../../../core/window/window_service.dart';
import '../../registration/services/business_identity_storage.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/license_models.dart';
import '../license_config.dart';
import '../services/license_controller.dart';
import '../services/license_support_message.dart';

const _bgTop = Color(0xFFF8FBFF);
const _bgBottom = Color(0xFFEAF1F8);
const _ink = Color(0xFF142033);
const _muted = Color(0xFF637188);
const _soft = Color(0xFF97A4B8);
const _line = Color(0xFFD9E2EE);
const _panel = Color(0xFFFDFEFF);
const _panelSoft = Color(0xFFF5F8FC);
const _primary = Color(0xFF153E75);
const _primaryBright = Color(0xFF2563EB);
const _primaryTint = Color(0xFFEAF2FF);
const _accent = Color(0xFFB96534);
const _warning = Color(0xFFD97706);
const _danger = Color(0xFFD14343);

class LicensePage extends ConsumerStatefulWidget {
  const LicensePage({super.key});

  @override
  ConsumerState<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends ConsumerState<LicensePage> {
  static const String _supportPhoneWhatsapp = '18295319442';

  final _businessNameCtrl = TextEditingController();
  final _businessNicheCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _rncCtrl = TextEditingController();

  final _identityStorage = BusinessIdentityStorage();
  final _businessSettingsRepo = BusinessSettingsRepository();

  String? _businessId;
  String? _selectedNiche;
  String? _licenseFileName;
  String? _licenseFileStatus;
  bool _loadingProfile = true;
  bool _onboardingCompleted = false;
  bool _trialUsed = false;
  DateTime? _trialStartedAt;
  bool _hasMinimumProfileData = false;
  bool _navigatedToApp = false;
  int _selectedTab = 0;

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
    _loadProfile();
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessNicheCtrl.dispose();
    _ownerNameCtrl.dispose();
    _whatsappCtrl.dispose();
    _emailCtrl.dispose();
    _rncCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _identityStorage.getOnboardingProfile();
    final settings = await _businessSettingsRepo.loadSettings();
    final trialUsed = await _identityStorage.isDemoConsumed();
    final onboardingCompleted = await _identityStorage.isOnboardingCompleted();
    final businessId = await _identityStorage.getBusinessId();

    _seedFields(settings, profile);

    final inferredCompleted =
        onboardingCompleted ||
        trialUsed ||
        (businessId ?? '').trim().isNotEmpty ||
        (profile?.hasMinimumData ?? false);
    if (inferredCompleted && !onboardingCompleted) {
      await _identityStorage.setOnboardingCompleted(true);
    }

    if (!mounted) return;
    setState(() {
      final normalizedBusinessId = (businessId ?? '').trim();
      _businessId = normalizedBusinessId.isEmpty ? null : normalizedBusinessId;
      _onboardingCompleted = inferredCompleted;
      _trialUsed = trialUsed || profile?.trialStart != null;
      _trialStartedAt = profile?.trialStart;
      _hasMinimumProfileData = profile?.hasMinimumData == true;
      _loadingProfile = false;
    });
  }

  void _seedFields(
    BusinessSettings settings,
    BusinessOnboardingProfile? profile,
  ) {
    final businessName = profile?.businessName.trim().isNotEmpty == true
        ? profile!.businessName.trim()
        : settings.businessName.trim();
    final niche = profile?.role.trim().isNotEmpty == true
        ? profile!.role.trim()
        : '';
    final ownerName = profile?.ownerName.trim().isNotEmpty == true
        ? profile!.ownerName.trim()
        : '';
    final phone = profile?.phone.trim().isNotEmpty == true
        ? profile!.phone.trim()
        : (settings.phone ?? '').trim();
    final email = profile?.email?.trim().isNotEmpty == true
        ? profile!.email!.trim()
        : (settings.email ?? '').trim();
    final rnc = (settings.rnc ?? '').trim();

    _businessNameCtrl.text = businessName;
    _businessNicheCtrl.text = niche;
    _ownerNameCtrl.text = ownerName;
    _whatsappCtrl.text = phone;
    _emailCtrl.text = email;
    _rncCtrl.text = rnc;
    _selectedNiche = _nicheOptions.contains(niche) ? niche : null;
  }

  Future<bool> _saveOnboarding({
    bool requireFullFields = true,
    bool showSuccessMessage = true,
  }) async {
    final businessName = _businessNameCtrl.text.trim();
    final niche = _businessNicheCtrl.text.trim();
    final ownerName = _ownerNameCtrl.text.trim();
    final whatsapp = _whatsappCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final rnc = _rncCtrl.text.trim();

    final missingRequired =
        businessName.isEmpty ||
        ownerName.isEmpty ||
        whatsapp.isEmpty ||
        (requireFullFields && niche.isEmpty);
    if (missingRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requireFullFields
                ? 'Completa negocio, tipo, representante y WhatsApp.'
                : 'Completa negocio, representante y WhatsApp.',
          ),
        ),
      );
      return false;
    }

    await _identityStorage.saveBusinessProfile(
      businessName: businessName,
      role: niche.isEmpty ? 'Otro' : niche,
      ownerName: ownerName,
      phone: whatsapp,
      email: email.isEmpty ? null : email,
    );
    await _identityStorage.setOnboardingCompleted(true);

    final currentSettings = await _businessSettingsRepo.loadSettings();
    final updatedSettings = currentSettings.copyWith(
      businessName:
          currentSettings.businessName.trim() == 'FULLPOS' ||
              currentSettings.businessName.trim().isEmpty
          ? businessName
          : currentSettings.businessName,
      phone: (currentSettings.phone ?? '').trim().isEmpty
          ? whatsapp
          : currentSettings.phone,
      email: (currentSettings.email ?? '').trim().isEmpty && email.isNotEmpty
          ? email
          : currentSettings.email,
      rnc: (currentSettings.rnc ?? '').trim().isEmpty && rnc.isNotEmpty
          ? rnc
          : currentSettings.rnc,
    );
    await _businessSettingsRepo.saveSettings(updatedSettings);

    if (!mounted) return false;
    setState(() {
      _onboardingCompleted = true;
      _hasMinimumProfileData = true;
    });
    if (showSuccessMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos iniciales guardados correctamente.'),
        ),
      );
    }
    return true;
  }

  Future<void> _startTrial(LicenseController controller) async {
    final saved = await _saveOnboarding();
    if (!saved) return;
    final ok = await controller.startLocalTrialOfflineFirst(
      nombreNegocio: _businessNameCtrl.text,
      rolNegocio: _businessNicheCtrl.text,
      contactoNombre: _ownerNameCtrl.text.trim().isEmpty
          ? _businessNameCtrl.text
          : _ownerNameCtrl.text,
      contactoTelefono: _whatsappCtrl.text,
    );
    if (!ok || !mounted) return;
    await _loadProfile();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _verifyLicense(LicenseController controller) async {
    await controller.syncBusinessLicenseNow();
    if (!mounted) return;
    await _loadProfile();
  }

  Future<void> _pickAndApplyLicenseFile(LicenseController controller) async {
    setState(() {
      _licenseFileStatus = null;
    });

    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'dat', 'fulllicense'],
        withData: true,
        lockParentWindow: true,
      ),
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    setState(() {
      _licenseFileName = file.name;
      _licenseFileStatus = 'Leyendo archivo...';
    });

    String raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null && file.path!.trim().isNotEmpty) {
      raw = await File(file.path!).readAsString();
    } else {
      if (!mounted) return;
      setState(() {
        _licenseFileStatus = 'No se pudo leer el archivo seleccionado.';
      });
      return;
    }

    raw = raw.trimLeft();
    if (raw.startsWith('\uFEFF')) {
      raw = raw.substring(1);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _licenseFileStatus =
            'El archivo no tiene formato JSON válido para la activación manual.';
      });
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      if (!mounted) return;
      setState(() {
        _licenseFileStatus = 'Formato inválido: se esperaba un objeto JSON.';
      });
      return;
    }

    final normalized = _normalizeUploadedLicenseFile(decoded);
    if (normalized == null) {
      if (!mounted) return;
      setState(() {
        _licenseFileStatus =
            'Formato inválido: el archivo debe incluir payload y signature.';
      });
      return;
    }

    await controller.applyOfflineLicenseFile(normalized);
    final nextState = ref.read(licenseControllerProvider);
    if (!mounted) return;
    setState(() {
      if (nextState.error != null && nextState.error!.trim().isNotEmpty) {
        _licenseFileStatus = nextState.error;
      } else if (nextState.info?.isActive == true &&
          nextState.info?.isExpired == false) {
        _licenseFileStatus = 'Licencia aplicada y activa.';
      } else {
        _licenseFileStatus = 'Archivo validado. Verifica el estado.';
      }
    });
  }

  Map<String, dynamic>? _normalizeUploadedLicenseFile(
    Map<String, dynamic> input,
  ) {
    final payload = input['payload'];
    final signature = (input['signature'] ?? '').toString().trim();
    if (payload is Map && signature.isNotEmpty) {
      return {
        'payload': payload.cast<String, dynamic>(),
        'signature': signature,
        'alg': (input['alg'] ?? 'Ed25519').toString().trim(),
      };
    }

    final nested = input['license'];
    if (nested is Map<String, dynamic>) {
      final nestedPayload = nested['payload'];
      final nestedSignature = (nested['signature'] ?? '').toString().trim();
      if (nestedPayload is Map && nestedSignature.isNotEmpty) {
        return {
          'payload': nestedPayload.cast<String, dynamic>(),
          'signature': nestedSignature,
          'alg': (nested['alg'] ?? 'Ed25519').toString().trim(),
        };
      }
    }
    return null;
  }

  Future<void> _openSupportWhatsapp(
    LicenseInfo? info, {
    String? supportCode,
  }) async {
    final businessId = await _identityStorage.getBusinessId();
    final message = LicenseSupportMessage.build(
      supportCode: (supportCode ?? 'LIC-HELP-00').trim(),
      businessId: businessId,
      deviceId: info?.deviceId,
      licenseKey: info?.licenseKey,
      projectCode: info?.projectCode ?? kFullposProjectCode,
      status: info?.estado,
    );

    final extra = <String>[
      if (_businessNameCtrl.text.trim().isNotEmpty)
        'Negocio: ${_businessNameCtrl.text.trim()}',
      if (_businessNicheCtrl.text.trim().isNotEmpty)
        'Nicho: ${_businessNicheCtrl.text.trim()}',
      if (_whatsappCtrl.text.trim().isNotEmpty)
        'WhatsApp cliente: ${_whatsappCtrl.text.trim()}',
    ].join('\n');

    final fullMessage = extra.isEmpty ? message : '$message\n$extra';
    final uri = Uri.parse(
      '${AppConfig.whatsappBaseUrl}/$_supportPhoneWhatsapp',
    ).replace(queryParameters: {'text': fullMessage});

    await WindowService.runWithExternalApplication(() async {
      await WindowService.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final ok = await launchUrlString(
        uri.toString(),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    });
  }

  Future<void> _copyBusinessId() async {
    final businessId = (_businessId ?? '').trim();
    if (businessId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business ID no disponible todavía.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: businessId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Business ID copiado.')));
  }

  bool _hasActiveLicense(LicenseInfo? info) =>
      info?.isActive == true && info?.isExpired == false;

  bool _shouldShowTrialSection(LicenseInfo? info) {
    if (_hasActiveLicense(info) || info?.isBlocked == true) return false;
    if (_trialUsed || _trialStartedAt != null) return false;
    return true;
  }

  bool _shouldShowOnboardingSection(LicenseInfo? info) {
    if (_hasActiveLicense(info)) return false;
    if (_onboardingCompleted || _hasMinimumProfileData || _trialUsed) {
      return false;
    }
    if ((_businessId ?? '').trim().isNotEmpty) return false;
    return true;
  }

  void _redirectToAppIfReady(LicenseInfo? info) {
    if (_navigatedToApp || !_hasActiveLicense(info) || !mounted) return;
    _navigatedToApp = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/sales');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(licenseControllerProvider);
    final controller = ref.read(licenseControllerProvider.notifier);
    final info = state.info;
    final showOnboarding = _shouldShowOnboardingSection(info);
    final showTrial = _shouldShowTrialSection(info);
    final businessId = (_businessId ?? info?.businessId ?? '').trim();
    final isExpired = info?.isExpired == true;
    final isBlocked = info?.isBlocked == true;

    if (_hasActiveLicense(info)) {
      _redirectToAppIfReady(info);
    }

    ref.listen(licenseControllerProvider, (prev, next) {
      if (_hasActiveLicense(next.info)) {
        _redirectToAppIfReady(next.info);
      }
    });

    final title = isBlocked
        ? 'Licencia bloqueada'
        : isExpired
        ? 'Licencia vencida'
        : 'Activación FullPOS';
    final subtitle = isBlocked
        ? 'Verifica o reactiva tu licencia para continuar.'
        : isExpired
        ? 'Renueva tu acceso para volver a entrar.'
        : 'Completa solo lo necesario para comenzar.';

    return Scaffold(
      backgroundColor: _bgTop,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: _loadingProfile
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFEFFFFFF), Color(0xFFF8FBFF)],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x120E1A2B),
                              blurRadius: 26,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: _buildWorkspace(
                          state: state,
                          controller: controller,
                          info: info,
                          businessId: businessId,
                          showOnboarding: showOnboarding,
                          showTrial: showTrial,
                          isExpired: isExpired,
                          isBlocked: isBlocked,
                          title: title,
                          subtitle: subtitle,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildWorkspace({
    required LicenseState state,
    required LicenseController controller,
    required LicenseInfo? info,
    required String businessId,
    required bool showOnboarding,
    required bool showTrial,
    required bool isExpired,
    required bool isBlocked,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCompactHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          _buildTabsHeader(),
          const SizedBox(height: 12),
          if (state.uiError != null) ...[
            _buildErrorBanner(state.uiError!.title, state.uiError!.message),
            const SizedBox(height: 12),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Container(
              key: ValueKey(_selectedTab),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _line.withOpacity(0.95)),
              ),
              padding: const EdgeInsets.all(16),
              child: switch (_selectedTab) {
                0 => _buildTrialTabContent(
                  state: state,
                  controller: controller,
                  info: info,
                  businessId: businessId,
                  showOnboarding: showOnboarding,
                  showTrial: showTrial,
                ),
                1 => _buildActivateTabContent(
                  state: state,
                  controller: controller,
                  info: info,
                  businessId: businessId,
                ),
                _ => _buildSupportTabContent(
                  info: info,
                  businessId: businessId,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: _muted,
            fontSize: 12.8,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTabsHeader() {
    const items = [
      (icon: Icons.rocket_launch_rounded, label: 'Prueba'),
      (icon: Icons.key_rounded, label: 'Activar'),
      (icon: Icons.headset_mic_rounded, label: 'Soporte'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final active = _selectedTab == index;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: active ? _ink : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: active
                    ? const [
                        BoxShadow(
                          color: Color(0x14122033),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _selectedTab = index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 15,
                        color: active ? Colors.white : _muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: active ? Colors.white : _muted,
                          fontSize: 12.5,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTrialTabContent({
    required LicenseState state,
    required LicenseController controller,
    required LicenseInfo? info,
    required String businessId,
    required bool showOnboarding,
    required bool showTrial,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionLabel(showTrial ? 'Prueba gratis de 5 días' : 'Prueba'),
        const SizedBox(height: 12),
        if (showOnboarding || showTrial) ...[
          _buildBusinessFormCard(
            showIdentityHint: false,
            businessId: businessId,
          ),
          const SizedBox(height: 12),
        ],
        if (showTrial)
          _buildPrimaryCta(
            icon: state.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.rocket_launch_rounded, size: 18),
            label: state.loading
                ? 'Iniciando demo...'
                : 'Iniciar prueba gratis',
            helper: null,
            onPressed: state.loading ? null : () => _startTrial(controller),
          )
        else
          _buildSoftNotice(
            tone: _warning,
            title: 'Prueba no disponible',
            body: _trialUsed
                ? 'Esta instalación ya consumió la prueba gratis.'
                : 'La prueba gratis ya no está disponible.',
            actionLabel: 'Ir a activar licencia',
            onPressed: () => setState(() => _selectedTab = 1),
          ),
      ],
    );
  }

  Widget _buildActivateTabContent({
    required LicenseState state,
    required LicenseController controller,
    required LicenseInfo? info,
    required String businessId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionLabel('Activación'),
        const SizedBox(height: 12),
        _buildPurchaseHighlightCard(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metaTile(
              icon: Icons.badge_rounded,
              label: 'Business ID',
              value: businessId.isEmpty ? 'Pendiente' : businessId,
              onCopy: businessId.isEmpty ? null : _copyBusinessId,
            ),
            _metaTile(
              icon: Icons.computer_rounded,
              label: 'Device ID',
              value: info?.deviceId ?? '-',
            ),
          ],
        ),
        if (_licenseFileName != null || _licenseFileStatus != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _panelSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Archivo seleccionado',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_licenseFileName != null)
                  Text(
                    _licenseFileName!,
                    style: const TextStyle(color: _muted, fontSize: 13.5),
                  ),
                if (_licenseFileStatus != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _licenseFileStatus!,
                    style: const TextStyle(color: _soft, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _actionRow(
          primary: _buildWideButton(
            icon: Icons.upload_file_rounded,
            label: 'Subir archivo de licencia',
            onPressed: state.loading
                ? null
                : () => _pickAndApplyLicenseFile(controller),
            primary: true,
          ),
          secondary: _buildWideButton(
            icon: Icons.verified_user_rounded,
            label: 'Verificar licencia',
            onPressed: state.loading ? null : () => _verifyLicense(controller),
            primary: false,
          ),
        ),
        const SizedBox(height: 8),
        _buildWideButton(
          icon: Icons.support_agent_rounded,
          label: 'Pedir activación virtual',
          onPressed: () => _openSupportWhatsapp(info),
          primary: false,
        ),
      ],
    );
  }

  Widget _buildPurchaseHighlightCard() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.985, end: 1),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF2E8), Color(0xFFFFFBF7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1D7C8)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18B96534),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.local_fire_department_rounded, color: _accent, size: 18),
                SizedBox(width: 8),
                Text(
                  'Comprar licencia',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Activa o renueva con PayPal desde 3 meses en adelante.',
              style: TextStyle(
                color: _muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1800),
              curve: Curves.easeOutCubic,
              builder: (context, glow, child) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x33B96534).withOpacity(0.18 + (glow * 0.18)),
                        blurRadius: 18 + (glow * 10),
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: _buildWideButton(
                icon: Icons.shopping_cart_checkout_rounded,
                label: 'Comprar ahora',
                onPressed: () async {
                  final saved = await _saveOnboarding(
                    requireFullFields: false,
                    showSuccessMessage: false,
                  );
                  if (!saved || !mounted) return;
                  context.go('/license/purchase');
                },
                primary: true,
                tone: _accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportTabContent({
    required LicenseInfo? info,
    required String businessId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionLabel('Soporte'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _panelSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.chat_bubble_rounded,
                    color: _primaryBright,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Contacto directo',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'WhatsApp: 829-531-9442',
                style: TextStyle(
                  color: _primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metaTile(
                    icon: Icons.badge_rounded,
                    label: 'Business ID',
                    value: businessId.isEmpty ? '-' : businessId,
                  ),
                  _metaTile(
                    icon: Icons.computer_rounded,
                    label: 'Device ID',
                    value: info?.deviceId ?? '-',
                  ),
                  _metaTile(
                    icon: Icons.vpn_key_rounded,
                    label: 'Proyecto',
                    value: info?.projectCode ?? kFullposProjectCode,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildWideButton(
          icon: Icons.chat_rounded,
          label: 'Abrir WhatsApp',
          onPressed: () => _openSupportWhatsapp(info),
          primary: true,
        ),
        const SizedBox(height: 8),
        _buildWideButton(
          icon: Icons.info_outline_rounded,
          label: 'Solicitar código de soporte',
          onPressed: () =>
              _openSupportWhatsapp(info, supportCode: 'LIC-HELP-01'),
          primary: false,
        ),
      ],
    );
  }

  Widget _buildBusinessFormCard({
    required bool showIdentityHint,
    required String businessId,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showIdentityHint) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metaTile(
                  icon: Icons.apartment_rounded,
                  label: 'Business ID',
                  value: businessId.isEmpty
                      ? 'Se generará o reutilizará'
                      : businessId,
                  onCopy: businessId.isEmpty ? null : _copyBusinessId,
                ),
                _metaTile(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Estado',
                  value: _onboardingCompleted
                      ? 'Datos existentes'
                      : 'Primera configuración',
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _buildBusinessForm(),
        ],
      ),
    );
  }

  Widget _buildBusinessForm() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 580;
        final fields = <Widget>[
          _buildTextField(
            controller: _businessNameCtrl,
            label: 'Nombre del negocio',
            hint: 'Ej: Comercial Núcleo',
            icon: Icons.storefront_rounded,
          ),
          _buildNicheDropdown(),
          _buildTextField(
            controller: _ownerNameCtrl,
            label: 'Nombre de contacto',
            hint: 'Responsable principal',
            icon: Icons.person_outline_rounded,
          ),
          _buildTextField(
            controller: _whatsappCtrl,
            label: 'WhatsApp',
            hint: '809 555 5555',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
          ),
          _buildTextField(
            controller: _emailCtrl,
            label: 'Correo electrónico',
            hint: 'Opcional',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          _buildTextField(
            controller: _rncCtrl,
            label: 'RNC',
            hint: 'Opcional',
            icon: Icons.badge_outlined,
          ),
        ];

        if (!wide) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i != fields.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: fields[0]),
                const SizedBox(width: 14),
                Expanded(child: fields[1]),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: fields[2]),
                const SizedBox(width: 14),
                Expanded(child: fields[3]),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: fields[4]),
                const SizedBox(width: 14),
                Expanded(child: fields[5]),
              ],
            ),
          ],
        );
      },
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
      cursorColor: _primaryBright,
      style: const TextStyle(
        color: _ink,
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
      ),
      decoration: _inputDecoration(label: label, hint: hint, icon: icon),
    );
  }

  Widget _buildNicheDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedNiche,
      borderRadius: BorderRadius.circular(18),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.expand_more_rounded, color: _soft),
      style: const TextStyle(
        color: _ink,
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
      ),
      decoration: _inputDecoration(
        label: 'Tipo de negocio',
        hint: 'Selecciona una categoría',
        icon: Icons.category_outlined,
      ),
      items: _nicheOptions
          .map(
            (niche) =>
                DropdownMenuItem<String>(value: niche, child: Text(niche)),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedNiche = value;
          _businessNicheCtrl.text = value ?? '';
        });
      },
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(icon, size: 18, color: _soft),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 46),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(
        color: _muted,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: const TextStyle(
        color: _soft,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primaryBright, width: 1.6),
      ),
    );
  }

  Widget _buildPrimaryCta({
    required Widget icon,
    required String label,
    required String? helper,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF173B70), Color(0xFF2254A4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33173B70),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _primary,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
            icon: icon,
            label: Text(label),
          ),
          if (helper != null) ...[
            const SizedBox(height: 10),
            Text(
              helper,
              style: const TextStyle(
                color: Color(0xD9FFFFFF),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSoftNotice({
    required Color tone,
    required String title,
    required String body,
    String? actionLabel,
    VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Color.lerp(tone, Colors.white, 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Color.lerp(tone, Colors.white, 0.72)!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: tone, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: tone,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: _muted,
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (actionLabel != null && onPressed != null) ...[
            const SizedBox(height: 14),
            _buildWideButton(
              icon: Icons.arrow_forward_rounded,
              label: actionLabel,
              onPressed: onPressed,
              primary: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String title, String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF4CFCF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 20, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _danger,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: _danger,
                    fontSize: 12.8,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool primary,
    Color? tone,
  }) {
    final color = tone ?? _primary;
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: _ink,
            side: const BorderSide(color: _line),
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          );

    final button = primary
        ? FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );

    return SizedBox(width: double.infinity, child: button);
  }

  Widget _actionRow({required Widget primary, required Widget secondary}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 580) {
          return Column(
            children: [primary, const SizedBox(height: 12), secondary],
          );
        }
        return Row(
          children: [
            Expanded(child: primary),
            const SizedBox(width: 12),
            Expanded(child: secondary),
          ],
        );
      },
    );
  }

  Widget _metaTile({
    required IconData icon,
    required String label,
    required String value,
    Future<void> Function()? onCopy,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _primaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _primaryBright, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _soft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.copy_rounded, size: 15, color: _soft),
              ),
            ),
          ],
        ],
      ),
    );
  }

}
