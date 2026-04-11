import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_sizes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/window/window_service.dart';
import '../../registration/services/business_identity_storage.dart';
import '../license_config.dart';
import '../data/license_models.dart';
import '../models/license_ui_error.dart';
import '../services/license_support_message.dart';
import '../services/license_controller.dart';

const _licensePageBackground = Color(0xFFE8F0FB);
const _licensePanelColor = Color(0xFF445468);
const _licensePanelColorTop = Color(0xFF506178);
const _licensePanelColorBottom = Color(0xFF3F4D60);
const _licensePrimaryBlue = Color(0xFF1D4ED8);
const _licenseAccentSky = Color(0xFF7CB7FF);
const _licenseAccentCyan = Color(0xFF84D8E8);
const _licensePanelText = Color(0xFFFFFFFF);
const _licensePanelMutedText = Color(0xCCFFFFFF);
const _licenseInputBackground = Color(0xFFFFFFFF);
const _licenseInputText = Color(0xFF000000);
const _licenseInputHint = Color(0xFF6B7280);
const _licenseCardShadow = BoxShadow(
  color: Color(0x220D1B2A),
  blurRadius: 36,
  offset: Offset(0, 18),
);

class LicensePage extends ConsumerStatefulWidget {
  const LicensePage({super.key});

  @override
  ConsumerState<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends ConsumerState<LicensePage> {
  static const String _supportPhoneDisplay = '8295319442';
  static const String _supportPhoneWhatsapp = '18295319442';

  final _demoNombreNegocioCtrl = TextEditingController();
  final _demoRolNegocioCtrl = TextEditingController();
  final _demoContactoNombreCtrl = TextEditingController();
  final _demoContactoTelefonoCtrl = TextEditingController();

  String? _demoRolNegocioSelected;

  _LicenseSection _section = _LicenseSection.demo;

  String? _licenseFileName;
  String? _licenseFileStatus;

  bool _showSupportDetails = false;
  bool _showQuickGuide = false;

  String? _businessId;
  DateTime? _lastBusinessIdFetchAt;

  String _maskKey(String input) {
    final s = input.trim();
    if (s.isEmpty) return '';
    if (s.length <= 8) return '****';
    final start = s.substring(0, 4);
    final end = s.substring(s.length - 4);
    return '$start…$end';
  }

  @override
  void initState() {
    super.initState();

    final currentRole = _demoRolNegocioCtrl.text.trim();
    if (currentRole.isNotEmpty) {
      _demoRolNegocioSelected = currentRole;
    }

    unawaited(_refreshBusinessId(force: true, ensureExists: true));
  }

  Future<void> _refreshBusinessId({
    bool force = false,
    bool ensureExists = false,
  }) async {
    final last = _lastBusinessIdFetchAt;
    if (!force && last != null) {
      if (DateTime.now().difference(last) < const Duration(seconds: 10)) return;
    }
    _lastBusinessIdFetchAt = DateTime.now();

    try {
      final storage = BusinessIdentityStorage();
      final id = ensureExists
          ? await storage.ensureBusinessId()
          : await storage.getBusinessId();
      if (!mounted) return;
      final normalized = (id ?? '').trim();
      setState(() {
        _businessId = normalized.isEmpty ? null : normalized;
      });
    } catch (_) {
      // ignore
    }
  }

  String _formatLocalDateTime(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  String _licenseTypeLabel(LicenseInfo? info) {
    final t = (info?.tipo ?? '').toString().trim();
    if (t.isNotEmpty) return t.toUpperCase();
    final code = (info?.code ?? '').toString().trim();
    return code.isNotEmpty ? code.toUpperCase() : '-';
  }

  @override
  void dispose() {
    _demoNombreNegocioCtrl.dispose();
    _demoRolNegocioCtrl.dispose();
    _demoContactoNombreCtrl.dispose();
    _demoContactoTelefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndApplyLicenseFile(LicenseController controller) async {
    setState(() {
      _licenseFileStatus = null;
    });

    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
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
        _licenseFileStatus = 'No se pudo leer el archivo seleccionado';
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
        _licenseFileStatus = 'El archivo no es un JSON válido';
      });
      return;
    }
    if (decoded is! Map) {
      if (!mounted) return;
      setState(() {
        _licenseFileStatus = 'Formato inválido: se esperaba un objeto JSON';
      });
      return;
    }

    final normalizedFile = _normalizeUploadedLicenseFile(
      decoded.cast<String, dynamic>(),
    );
    if (normalizedFile == null) {
      if (!mounted) return;
      setState(() {
        _licenseFileStatus =
            'Formato inválido: el JSON debe incluir payload y signature';
      });
      return;
    }

    setState(() {
      _licenseFileStatus = 'Verificando archivo...';
    });

    await controller.applyOfflineLicenseFile(normalizedFile);

    if (!mounted) return;

    final st = ref.read(licenseControllerProvider);
    final info = st.info;
    setState(() {
      if (st.error != null && st.error!.trim().isNotEmpty) {
        _licenseFileStatus = st.error;
      } else if (info?.ok == true && info?.isExpired == false) {
        _licenseFileStatus = 'Licencia aplicada y activa';
      } else {
        _licenseFileStatus = 'Archivo verificado. Verifica el estado.';
      }
    });

    if (!mounted) return;
    final isSuccess =
        st.error == null &&
        st.uiError == null &&
        info?.ok == true &&
        info?.isExpired == false;
    if (isSuccess) {
      unawaited(_refreshBusinessId(force: true, ensureExists: true));
      // Redirigir de inmediato de forma confiable: navegar en el próximo frame.
      // Usamos /sales: si no hay sesión, el router enviará a /login.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/sales');
      });
    }
  }

  Map<String, dynamic>? _normalizeUploadedLicenseFile(
    Map<String, dynamic> input,
  ) {
    final directPayload = input['payload'];
    final directSignature = (input['signature'] ?? '').toString().trim();
    if (directPayload is Map && directSignature.isNotEmpty) {
      return {
        'payload': directPayload.cast<String, dynamic>(),
        'signature': directSignature,
        'alg': (input['alg'] ?? 'Ed25519').toString().trim(),
      };
    }

    final nested = input['license'];
    if (nested is Map) {
      final nestedMap = nested.cast<String, dynamic>();
      final payload = nestedMap['payload'];
      final signature = (nestedMap['signature'] ?? '').toString().trim();
      if (payload is Map && signature.isNotEmpty) {
        return {
          'payload': payload.cast<String, dynamic>(),
          'signature': signature,
          'alg': (nestedMap['alg'] ?? input['alg'] ?? 'Ed25519')
              .toString()
              .trim(),
        };
      }
    }

    return null;
  }

  Future<void> _openWhatsapp({String? supportCode}) async {
    final st = ref.read(licenseControllerProvider);
    final info = st.info;

    final businessId = await BusinessIdentityStorage().getBusinessId();

    final deviceId = (info?.deviceId ?? '').trim();
    final licenseKey = (info?.licenseKey ?? '').trim();
    final projectCode = (info?.projectCode ?? kFullposProjectCode).trim();
    final estado = (info?.estado ?? '').trim();

    final negocio = _demoNombreNegocioCtrl.text.trim();
    final tipoNegocio = _demoRolNegocioCtrl.text.trim();
    final contacto = _demoContactoNombreCtrl.text.trim();
    final telefono = _demoContactoTelefonoCtrl.text.trim();

    final message = LicenseSupportMessage.build(
      supportCode: (supportCode ?? st.uiError?.supportCode ?? 'LIC-HELP-00')
          .trim(),
      businessId: businessId,
      deviceId: deviceId,
      licenseKey: licenseKey,
      projectCode: projectCode.isNotEmpty ? projectCode : kFullposProjectCode,
      status: estado,
    );

    final fullMessage = <String>[
      message,
      if (negocio.isNotEmpty) 'Negocio: $negocio',
      if (tipoNegocio.isNotEmpty) 'Tipo negocio: $tipoNegocio',
      if (contacto.isNotEmpty) 'Contacto: $contacto',
      if (telefono.isNotEmpty) 'Teléfono: $telefono',
    ].join('\n');

    final uri = Uri.parse(
      '${AppConfig.whatsappBaseUrl}/$_supportPhoneWhatsapp',
    ).replace(queryParameters: {'text': fullMessage});
    final url = uri.toString();

    await WindowService.runWithExternalApplication(() async {
      // Requisito: minimizar primero, luego abrir WhatsApp.
      await WindowService.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final ok = await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    });
  }

  Widget _sectionButton({
    required _LicenseSection value,
    required String label,
    required IconData icon,
    bool expand = true,
  }) {
    final selected = _section == value;
    final onPressed = selected
        ? null
        : () {
            setState(() {
              _section = value;
            });
          };

    final button = selected
        ? FilledButton.icon(
            onPressed: () {},
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );

    if (!expand) return button;
    return Expanded(child: button);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(licenseControllerProvider);
    final controller = ref.read(licenseControllerProvider.notifier);
    final info = state.info;
    final trialDays = kLocalTrialDuration.inDays;

    // Keep business_id updated (best-effort).
    unawaited(_refreshBusinessId(ensureExists: true));

    ref.listen(licenseControllerProvider, (prev, next) {
      // Si ya se consumió la DEMO en este equipo/cliente, llevar a soporte.
      if (next.errorCode == 'DEMO_ALREADY_USED' &&
          _section != _LicenseSection.support) {
        setState(() {
          _section = _LicenseSection.support;
        });
      }
    });

    final theme = Theme.of(context);
    final cardBorder = Colors.white.withOpacity(0.18);
    final visualTheme = theme.copyWith(
      scaffoldBackgroundColor: _licensePageBackground,
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _licensePrimaryBlue,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _licensePrimaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _licensePanelText,
          backgroundColor: Colors.white.withOpacity(0.07),
          side: BorderSide(color: Colors.white.withOpacity(0.18)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(_licensePrimaryBlue),
          overlayColor: WidgetStatePropertyAll(
            _licensePrimaryBlue.withOpacity(0.10),
          ),
          textStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
            return TextStyle(
              fontWeight: FontWeight.w700,
              decoration: states.contains(WidgetState.hovered)
                  ? TextDecoration.underline
                  : TextDecoration.none,
            );
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _licenseInputBackground,
        labelStyle: const TextStyle(color: _licenseInputHint),
        floatingLabelStyle: const TextStyle(
          color: _licensePrimaryBlue,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: _licenseInputHint),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _licensePrimaryBlue, width: 1.6),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _licensePanelColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );

    final uiError = state.uiError;

    Widget content;
    switch (_section) {
      case _LicenseSection.demo:
        content = _buildDemoSection(context, info);
        break;
      case _LicenseSection.activate:
        content = _buildActivationSection(context, info);
        break;
      case _LicenseSection.support:
        content = _buildSupportSection(
          context,
          uiError,
          info: info,
          controller: controller,
        );
        break;
    }

    final licenseActive = info?.isActive == true && info?.isExpired == false;

    final headerTitle = licenseActive
        ? 'Tu acceso está listo para continuar'
        : 'Activa tu demo de $trialDays días';
    final headerSubtitle = licenseActive
        ? 'Puedes continuar al sistema.'
        : 'Llena los datos a continuación';

    ({String label, IconData icon, Future<void> Function()? onPressed})
    primaryAction;
    switch (_section) {
      case _LicenseSection.demo:
        primaryAction = (
          label: licenseActive ? 'Continuar' : 'Iniciar prueba',
          icon: licenseActive ? Icons.login : Icons.play_arrow,
          onPressed: licenseActive
              ? () async {
                  context.go('/login');
                }
              : () async {
                  final ok = await controller.startLocalTrialOfflineFirst(
                    nombreNegocio: _demoNombreNegocioCtrl.text,
                    rolNegocio: _demoRolNegocioCtrl.text,
                    contactoNombre: _demoContactoNombreCtrl.text,
                    contactoTelefono: _demoContactoTelefonoCtrl.text,
                  );

                  if (ok && context.mounted) {
                    context.go('/login');
                  }
                },
        );
        break;
      case _LicenseSection.activate:
        primaryAction = (
          label: 'Seleccionar archivo',
          icon: Icons.upload_file,
          onPressed: () async {
            await _pickAndApplyLicenseFile(controller);
          },
        );
        break;
      case _LicenseSection.support:
        primaryAction = (
          label: 'Abrir WhatsApp',
          icon: Icons.chat_bubble_outline,
          onPressed: () async {
            await _openWhatsapp(supportCode: uiError?.supportCode);
          },
        );
        break;
    }

    return Theme(
      data: visualTheme,
      child: Scaffold(
        backgroundColor: _licensePageBackground,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF3F8FF), Color(0xFFE4EEFB), Color(0xFFD6E5F8)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: -80,
                  left: -30,
                  child: _buildBackgroundGlow(_licenseAccentSky, 220),
                ),
                Positioned(
                  right: -70,
                  top: 120,
                  child: _buildBackgroundGlow(_licenseAccentCyan, 260),
                ),
                Positioned(
                  bottom: -110,
                  left: 80,
                  child: _buildBackgroundGlow(_licensePrimaryBlue, 240),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSizes.paddingL),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: AbsorbPointer(
                        absorbing: state.loading,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const [_licenseCardShadow],
                          ),
                          child: Card(
                            margin: EdgeInsets.zero,
                            color: Colors.transparent,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                              side: BorderSide(color: cardBorder),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _licensePanelColorTop,
                                    _licensePanelColor,
                                    _licensePanelColorBottom,
                                  ],
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 520;

                                    final sectionButtons = <Widget>[
                                      _sectionButton(
                                        value: _LicenseSection.demo,
                                        label: 'Prueba',
                                        icon: Icons.play_circle_outline,
                                        expand: !compact,
                                      ),
                                      _sectionButton(
                                        value: _LicenseSection.activate,
                                        label: 'Activar',
                                        icon: Icons.upload_file_outlined,
                                        expand: !compact,
                                      ),
                                      _sectionButton(
                                        value: _LicenseSection.support,
                                        label: 'Soporte',
                                        icon: Icons.support_agent,
                                        expand: !compact,
                                      ),
                                    ];

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          headerTitle,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: _licensePanelText,
                                                fontWeight: FontWeight.w800,
                                                height: 1.1,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          headerSubtitle,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: _licensePanelMutedText,
                                                fontWeight: FontWeight.w600,
                                                height: 1.35,
                                              ),
                                        ),
                                        const SizedBox(height: 16),
                                        if (uiError != null) ...[
                                          _buildErrorCard(
                                            context,
                                            uiError,
                                            info: info,
                                            controller: controller,
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                        if (compact)
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: sectionButtons,
                                          )
                                        else
                                          Row(
                                            children: [
                                              sectionButtons[0],
                                              const SizedBox(width: 8),
                                              sectionButtons[1],
                                              const SizedBox(width: 8),
                                              sectionButtons[2],
                                            ],
                                          ),
                                        const SizedBox(height: 16),
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.09,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(
                                                0.12,
                                              ),
                                            ),
                                          ),
                                          child: content,
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: state.loading
                                                ? null
                                                : () async {
                                                    await primaryAction
                                                        .onPressed
                                                        ?.call();
                                                  },
                                            icon: Icon(primaryAction.icon),
                                            label: Text(primaryAction.label),
                                          ),
                                        ),
                                        if (kDebugMode) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(
                                                  0.16,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  'Debug',
                                                  style: theme
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color:
                                                            _licensePanelText,
                                                      ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Borra TRIAL y licencia local en esta PC (solo debug).',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            _licensePanelMutedText,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                const SizedBox(height: 10),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    final ok = await showDialog<bool>(
                                                      context: context,
                                                      builder: (context) {
                                                        return AlertDialog(
                                                          title: const Text(
                                                            'Reset licencia (debug)',
                                                          ),
                                                          content: const Text(
                                                            'Esto borrará el TRIAL, la identidad del negocio, la cola de registro y el archivo license.dat en esta PC.\n\nSolo funciona en modo debug.',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                'Cancelar',
                                                              ),
                                                            ),
                                                            FilledButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                'Borrar',
                                                              ),
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    );
                                                    if (ok != true) return;

                                                    await controller
                                                        .debugResetLicensingOnThisDevice();
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    setState(() {
                                                      _licenseFileStatus = null;
                                                      _licenseFileName = null;
                                                      _section =
                                                          _LicenseSection.demo;
                                                    });
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Licencia/TRIAL borrados (debug).',
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_forever_outlined,
                                                  ),
                                                  label: const Text(
                                                    'Reset licencia (debug)',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (state.loading) ...[
                                          const SizedBox(height: 16),
                                          const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context,
    LicenseUiError uiError, {
    required LicenseInfo? info,
    required LicenseController controller,
  }) {
    final theme = Theme.of(context);

    final bg = uiError.isBlocking
        ? const Color(0x33DC2626)
        : Colors.white.withOpacity(0.10);
    const fg = _licensePanelText;

    IconData iconFor(LicenseErrorType t) {
      return switch (t) {
        LicenseErrorType.offline => Icons.wifi_off,
        LicenseErrorType.timeout => Icons.timer_outlined,
        LicenseErrorType.dns => Icons.public_off,
        LicenseErrorType.ssl => Icons.security,
        LicenseErrorType.serverDown => Icons.cloud_off,
        LicenseErrorType.unauthorized => Icons.lock_outline,
        LicenseErrorType.notActivated => Icons.hourglass_bottom,
        LicenseErrorType.invalidLicenseFile => Icons.insert_drive_file_outlined,
        LicenseErrorType.expired => Icons.event_busy,
        LicenseErrorType.corruptedLocalFile => Icons.broken_image_outlined,
        LicenseErrorType.unknown => Icons.info_outline,
      };
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: uiError.isBlocking
              ? const Color(0x66F87171)
              : Colors.white.withOpacity(0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconFor(uiError.type), color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  uiError.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            uiError.message,
            style: theme.textTheme.bodyMedium?.copyWith(color: fg),
          ),
          const SizedBox(height: 10),
          _buildPrimaryActionsRow(
            context,
            uiError,
            info: info,
            controller: controller,
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionsRow(
    BuildContext context,
    LicenseUiError uiError, {
    required LicenseInfo? info,
    required LicenseController controller,
  }) {
    final actions = uiError.actions;
    final hasRetry = actions.contains(LicenseAction.retry);
    final hasRepair = actions.contains(LicenseAction.repairAndRetry);
    if (!hasRetry && !hasRepair) {
      // Aún así damos acceso a Soporte.
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _section = _LicenseSection.support;
              _showSupportDetails = true;
            });
          },
          icon: const Icon(Icons.support_agent),
          label: const Text('Ir a Soporte'),
        ),
      );
    }

    Future<void> onRetry() async {
      if (uiError.type == LicenseErrorType.notActivated) {
        await controller.syncBusinessLicenseNow();
        if (!mounted) return;
        return;
      }
      if (uiError.type == LicenseErrorType.corruptedLocalFile) {
        await controller.repairAndRetrySync();
        if (!mounted) return;
        return;
      }
      await controller.check();
      if (!mounted) return;
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (hasRetry)
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        if (hasRepair)
          FilledButton.icon(
            onPressed: () async {
              await controller.repairAndRetrySync();
              if (!mounted) return;
            },
            icon: const Icon(Icons.build_circle_outlined),
            label: const Text('Reparar y reintentar'),
          ),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _section = _LicenseSection.support;
              _showSupportDetails = true;
            });
          },
          icon: const Icon(Icons.support_agent),
          label: const Text('Ir a Soporte'),
        ),
      ],
    );
  }

  Widget _buildSupportSection(
    BuildContext context,
    LicenseUiError? uiError, {
    required LicenseInfo? info,
    required LicenseController controller,
  }) {
    final theme = Theme.of(context);

    final code = (uiError?.supportCode ?? 'LIC-HELP-00').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Soporte',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: _licensePanelText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Aquí tienes ayuda, contacto y los datos que soporte puede pedirte para asistirte rápido.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _licensePanelMutedText,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.support_agent, color: _licensePanelText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Soporte',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _licensePanelText,
                      ),
                    ),
                  ),
                  Text(
                    code,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _licensePanelMutedText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _supportInfoPill(
                    context,
                    label: 'Business ID',
                    value: _businessId ?? 'Generando...',
                    trailing: _buildBusinessIdCopyIcon(
                      context,
                      color: _licensePanelText,
                    ),
                  ),
                  if (info?.deviceId.trim().isNotEmpty == true)
                    _supportInfoPill(
                      context,
                      label: 'Device ID',
                      value: info!.deviceId.trim(),
                    ),
                  _supportInfoPill(
                    context,
                    label: 'WhatsApp',
                    value: _supportPhoneDisplay,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await _openWhatsapp(supportCode: code);
                      if (!context.mounted) return;
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('WhatsApp soporte'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _copySupportCode(context, code);
                      if (!context.mounted) return;
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar código'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _showQuickGuide = !_showQuickGuide);
                    },
                    icon: const Icon(Icons.help_outline),
                    label: Text(
                      _showQuickGuide ? 'Ocultar guía' : 'Guía rápida',
                    ),
                  ),
                ],
              ),
              if (uiError != null) ...[
                const SizedBox(height: 10),
                _buildSupportDetails(context, uiError, info: info),
              ] else if (_showQuickGuide) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                  ),
                  child: Text(
                    'Guía rápida:\n'
                    '• Intenta de nuevo en 1 minuto.\n'
                    '• Si persiste, contacta soporte.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _licensePanelMutedText,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSupportDetails(
    BuildContext context,
    LicenseUiError uiError, {
    required LicenseInfo? info,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showQuickGuide) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: Text(
              'Guía rápida:\n'
              '• Intenta de nuevo en 1 minuto.\n'
              '• Si persiste, contacta soporte.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _licensePanelMutedText,
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            setState(() => _showSupportDetails = !_showSupportDetails);
          },
          child: Row(
            children: [
              Icon(
                _showSupportDetails ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'Detalles para soporte',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _licensePanelText,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '(opcional)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _licensePanelMutedText,
                ),
              ),
            ],
          ),
        ),
        if (_showSupportDetails) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.bodySmall!.copyWith(
                color: _licensePanelMutedText,
                height: 1.35,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Código soporte: ${uiError.supportCode}'),
                  if (uiError.endpoint != null)
                    Text('Endpoint: ${uiError.endpoint}'),
                  if (uiError.httpStatusCode != null)
                    Text('HTTP: ${uiError.httpStatusCode}'),
                  if (uiError.technicalSummary != null &&
                      uiError.technicalSummary!.trim().isNotEmpty)
                    Text('Resumen: ${uiError.technicalSummary}'),
                  if (info != null && info.deviceId.trim().isNotEmpty)
                    Text('Device ID: ${info.deviceId.trim()}'),
                  if (info != null && info.licenseKey.trim().isNotEmpty)
                    Text('Licencia: ${_maskKey(info.licenseKey)}'),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _copySupportCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Código copiado.')));
  }

  Future<void> _copyBusinessId(BuildContext context) async {
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

  Widget _buildBusinessIdCopyIcon(BuildContext context, {Color? color}) {
    final enabled = (_businessId ?? '').trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled
          ? () async {
              await _copyBusinessId(context);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          Icons.copy_rounded,
          size: 15,
          color: enabled ? color : (color ?? Colors.white).withOpacity(0.45),
        ),
      ),
    );
  }

  Widget _buildDemoSection(BuildContext context, LicenseInfo? info) {
    final active = info?.isActive == true && info?.isExpired == false;

    InputDecoration fieldDecoration(String label, {String? hint}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: _licenseInputHint),
        floatingLabelStyle: const TextStyle(
          color: _licensePrimaryBlue,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: _licenseInputHint),
        filled: true,
        fillColor: _licenseInputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _licensePrimaryBlue, width: 1.6),
        ),
      );
    }

    const rolesNegocio = <String>[
      'Colmado',
      'Mini market',
      'Supermercado',
      'Ferretería',
      'Farmacia',
      'Tienda de ropa',
      'Boutique',
      'Tienda de electrónicos',
      'Tienda de celulares',
      'Repuestos / Autopartes',
      'Licorería',
      'Papelería',
      'Panadería',
      'Carnicería',
      'Perfumería',
      'Hogar / Decoración',
      'Otro',
    ];

    if (active) {
      final isTrial = (info?.code ?? '').toUpperCase() == 'TRIAL';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isTrial ? 'Prueba gratis activa' : 'Licencia activa',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _kv(
            'Business ID',
            _businessId ?? '—',
            trailing: _buildBusinessIdCopyIcon(context),
          ),
          _kv('Tipo', _licenseTypeLabel(info)),
          if (!isTrial) _kv('Device ID', info?.deviceId ?? '-'),
          _kv('Vence', _formatLocalDateTime(info?.fechaFin)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 620;
            final fields = <Widget>[
              TextField(
                controller: _demoNombreNegocioCtrl,
                style: const TextStyle(color: _licenseInputText),
                cursorColor: _licensePrimaryBlue,
                decoration: fieldDecoration(
                  'Nombre del negocio',
                  hint: 'Ejemplo: Comercial Ana',
                ),
              ),
              DropdownButtonFormField<String>(
                value: rolesNegocio.contains(_demoRolNegocioSelected)
                    ? _demoRolNegocioSelected
                    : null,
                decoration: fieldDecoration(
                  '',
                  hint: 'Selecciona tipo de negocio',
                ).copyWith(labelText: null),
                isExpanded: true,
                dropdownColor: _licenseInputBackground,
                style: const TextStyle(color: _licenseInputText),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: _licenseInputHint,
                ),
                hint: const Text(
                  'Selecciona tipo de negocio',
                  style: TextStyle(color: _licenseInputHint),
                ),
                items: rolesNegocio
                    .map(
                      (role) => DropdownMenuItem<String>(
                        value: role,
                        child: Text(
                          role,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _licenseInputText),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _demoRolNegocioSelected = value;
                    _demoRolNegocioCtrl.text = value ?? '';
                  });
                },
              ),
              TextField(
                controller: _demoContactoNombreCtrl,
                style: const TextStyle(color: _licenseInputText),
                cursorColor: _licensePrimaryBlue,
                decoration: fieldDecoration(
                  'Nombre de contacto',
                  hint: 'Persona responsable',
                ),
              ),
              TextField(
                controller: _demoContactoTelefonoCtrl,
                style: const TextStyle(color: _licenseInputText),
                cursorColor: _licensePrimaryBlue,
                decoration: fieldDecoration('Teléfono', hint: '809 000 0000'),
                keyboardType: TextInputType.phone,
              ),
            ];

            if (!twoColumns) {
              return Column(
                children: [
                  for (var index = 0; index < fields.length; index++) ...[
                    fields[index],
                    if (index != fields.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            }

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 12),
                    Expanded(child: fields[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: fields[2]),
                    const SizedBox(width: 12),
                    Expanded(child: fields[3]),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildActivationSection(BuildContext context, LicenseInfo? info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sube tu archivo de licencia para activar esta instalación de forma rápida y segura.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _licensePanelMutedText),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.upload_file_outlined,
                      color: _licensePanelText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Activación por archivo',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _licensePanelText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _kv('Proyecto', kFullposProjectCode),
              _kv('Device ID', info?.deviceId ?? '-'),
              if (_licenseFileName != null) _kv('Archivo', _licenseFileName!),
            ],
          ),
        ),
        if (_licenseFileStatus != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Text(
              _licenseFileStatus!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _licensePanelText),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBackgroundGlow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.22), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }

  Widget _supportInfoPill(
    BuildContext context, {
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _licensePanelMutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _licensePanelText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$k:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: _licensePanelText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(color: _licensePanelMutedText),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}

enum _LicenseSection { demo, activate, support }
