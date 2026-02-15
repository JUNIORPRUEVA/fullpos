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
import '../../../core/brand/fullpos_brand_theme.dart';
import '../../registration/services/business_identity_storage.dart';
import '../license_config.dart';
import '../data/license_models.dart';
import '../models/license_ui_error.dart';
import '../services/license_support_message.dart';
import '../services/license_controller.dart';

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
      ),
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    _licenseFileName = file.name;

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

    setState(() {
      _licenseFileStatus = 'Verificando archivo...';
    });

    await controller.applyOfflineLicenseFile(decoded.cast<String, dynamic>());

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
      // Redirigir de inmediato de forma confiable: navegar en el próximo frame.
      // Usamos /sales: si no hay sesión, el router enviará a /login.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/sales');
      });
    }
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
            onPressed: onPressed,
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

    ref.listen(licenseControllerProvider, (prev, next) {
      // Si ya se consumió la DEMO en este equipo/cliente, llevar al flujo de compra.
      if (next.errorCode == 'DEMO_ALREADY_USED' &&
          _section != _LicenseSection.buy) {
        setState(() {
          _section = _LicenseSection.buy;
        });
      }
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    final cardBorder = scheme.primary.withOpacity(0.18);
    final dividerColor = scheme.onSurface.withOpacity(0.10);

    final uiError = state.uiError;

    Widget content;
    switch (_section) {
      case _LicenseSection.demo:
        content = _buildDemoSection(context, info);
        break;
      case _LicenseSection.file:
        content = _buildFileSection(context, info);
        break;
      case _LicenseSection.buy:
        content = _buildBuySection(context);
        break;
      case _LicenseSection.help:
        content = _buildHelpSection(
          context,
          uiError,
          info: info,
          controller: controller,
        );
        break;
    }

    final licenseActive = info?.isActive == true && info?.isExpired == false;

    final statusLabel = state.loading
        ? 'Verificando licencia...'
        : (licenseActive
              ? 'Licencia activa'
              : (uiError?.type == LicenseErrorType.notActivated
                    ? 'Esperando activación'
                    : (uiError != null ? 'Atención requerida' : 'Licencia')));

    final statusBg = state.loading
        ? scheme.surfaceVariant.withOpacity(0.55)
        : (licenseActive
              ? scheme.tertiaryContainer
              : (uiError?.isBlocking == true
                    ? scheme.errorContainer
                    : scheme.surfaceVariant.withOpacity(0.55)));
    final statusFg = uiError?.isBlocking == true
        ? scheme.onErrorContainer
        : (licenseActive ? scheme.onTertiaryContainer : scheme.onSurface);

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
      case _LicenseSection.file:
        primaryAction = (
          label: 'Seleccionar archivo',
          icon: Icons.upload_file,
          onPressed: () async {
            await _pickAndApplyLicenseFile(controller);
          },
        );
        break;
      case _LicenseSection.buy:
        primaryAction = (
          label: 'Abrir WhatsApp',
          icon: Icons.chat_bubble_outline,
          onPressed: () async {
            await _openWhatsapp();
          },
        );
        break;
      case _LicenseSection.help:
        primaryAction = (
          label: 'Verificar ahora',
          icon: Icons.verified_outlined,
          onPressed: () async {
            // Si está esperando activación, preferimos intentar sync nube.
            if (uiError?.type == LicenseErrorType.notActivated) {
              await controller.syncBusinessLicenseNow();
              return;
            }
            await controller.check();
          },
        );
        break;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: FullposBrandTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AbsorbPointer(
                  absorbing: state.loading,
                  child: Card(
                    color: scheme.surface,
                    elevation: 14,
                    shadowColor: Colors.black.withOpacity(0.24),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: cardBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 28,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: cardBorder),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  FullposBrandTheme.logoAsset,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Center(
                                        child: Icon(
                                          Icons.workspace_premium,
                                          size: 36,
                                          color: scheme.primary,
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Licencia',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: onSurface,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.2,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceVariant
                                            .withOpacity(0.40),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: dividerColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            statusLabel,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: statusFg,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: statusBg,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  border: Border.all(
                                                    color: dividerColor,
                                                  ),
                                                ),
                                                child: Text(
                                                  'Proyecto: $kFullposProjectCode',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: statusFg,
                                                        fontWeight:
                                                            FontWeight.w700,
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
                              IconButton(
                                tooltip: 'Minimizar',
                                onPressed: WindowService.minimize,
                                icon: const Icon(Icons.minimize),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: WindowService.close,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (uiError != null) ...[
                            _buildErrorCard(
                              context,
                              uiError,
                              info: info,
                              controller: controller,
                            ),
                            const SizedBox(height: 18),
                          ],
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 520;

                              final buttons = <Widget>[
                                _sectionButton(
                                  value: _LicenseSection.demo,
                                  label: 'Prueba',
                                  icon: Icons.play_circle_outline,
                                  expand: !compact,
                                ),
                                _sectionButton(
                                  value: _LicenseSection.file,
                                  label: 'Activar',
                                  icon: Icons.upload_file,
                                  expand: !compact,
                                ),
                                _sectionButton(
                                  value: _LicenseSection.buy,
                                  label: 'Comprar',
                                  icon: Icons.shopping_cart_outlined,
                                  expand: !compact,
                                ),
                                _sectionButton(
                                  value: _LicenseSection.help,
                                  label: 'Ayuda',
                                  icon: Icons.support_agent,
                                  expand: !compact,
                                ),
                              ];

                              if (compact) {
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: buttons,
                                );
                              }

                              return Row(
                                children: [
                                  buttons[0],
                                  const SizedBox(width: 10),
                                  buttons[1],
                                  const SizedBox(width: 10),
                                  buttons[2],
                                  const SizedBox(width: 10),
                                  buttons[3],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                          content,
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: state.loading
                                  ? null
                                  : () async {
                                      await primaryAction.onPressed?.call();
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
                                color: scheme.surfaceVariant.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: scheme.onSurface.withOpacity(0.10),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(    
                                    'Debug',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Borra TRIAL y licencia local en esta PC (solo debug).',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurface.withOpacity(0.70),
                                      fontWeight: FontWeight.w600,
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
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: const Text('Cancelar'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: const Text('Borrar'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                      if (ok != true) return;

                                      await controller
                                          .debugResetLicensingOnThisDevice();
                                      if (!context.mounted) return;
                                      setState(() {
                                        _licenseFileStatus = null;
                                        _licenseFileName = null;
                                        _section = _LicenseSection.demo;
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
                                      Icons.delete_forever_outlined,
                                    ),
                                    label: const Text('Reset licencia (debug)'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (state.loading) ...[
                            const SizedBox(height: 16),
                            const Center(child: CircularProgressIndicator()),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
    final scheme = theme.colorScheme;

    final bg = uiError.isBlocking
        ? scheme.errorContainer
        : scheme.surfaceVariant.withOpacity(0.45);
    final fg = uiError.isBlocking ? scheme.onErrorContainer : scheme.onSurface;

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
        border: Border.all(color: scheme.onSurface.withOpacity(0.10)),
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
      // Aún así damos acceso a Ayuda.
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _section = _LicenseSection.help;
              _showSupportDetails = true;
            });
          },
          icon: const Icon(Icons.support_agent),
          label: const Text('Ir a Ayuda'),
        ),
      );
    }

    Future<void> onRetry() async {
      if (uiError.type == LicenseErrorType.notActivated) {
        await controller.syncBusinessLicenseNow();
        return;
      }
      if (uiError.type == LicenseErrorType.corruptedLocalFile) {
        await controller.repairAndRetrySync();
        return;
      }
      await controller.check();
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
            },
            icon: const Icon(Icons.build_circle_outlined),
            label: const Text('Reparar y reintentar'),
          ),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _section = _LicenseSection.help;
              _showSupportDetails = true;
            });
          },
          icon: const Icon(Icons.support_agent),
          label: const Text('Ir a Ayuda'),
        ),
      ],
    );
  }

  Widget _buildHelpSection(
    BuildContext context,
    LicenseUiError? uiError, {
    required LicenseInfo? info,
    required LicenseController controller,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final code = (uiError?.supportCode ?? 'LIC-HELP-00').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ayuda',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Si tienes problemas activando o verificando la licencia, usa estas opciones.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withOpacity(0.72),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceVariant.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.onSurface.withOpacity(0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.support_agent, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Soporte',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    code,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.65),
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
                  FilledButton.icon(
                    onPressed: () async {
                      await _openWhatsapp(supportCode: code);
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('WhatsApp soporte'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _copySupportCode(context, code);
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
                    color: scheme.surface.withOpacity(0.70),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.onSurface.withOpacity(0.10),
                    ),
                  ),
                  child: Text(
                    'Guía rápida:\n'
                    '• Confirma que tienes internet (abre una página).\n'
                    '• Si es “Conexión segura falló”, revisa fecha y hora de Windows.\n'
                    '• Si estás en red corporativa, prueba otra red o hotspot.\n'
                    '• Intenta de nuevo en 1 minuto.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.80),
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
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showQuickGuide) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface.withOpacity(0.70),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.onSurface.withOpacity(0.10)),
            ),
            child: Text(
              'Guía rápida:\n'
              '• Confirma que tienes internet (abre una página).\n'
              '• Si es “Conexión segura falló”, revisa fecha y hora de Windows.\n'
              '• Si estás en red corporativa, prueba otra red o hotspot.\n'
              '• Intenta de nuevo en 1 minuto.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.80),
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
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '(opcional)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.65),
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
              color: scheme.surface.withOpacity(0.70),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.onSurface.withOpacity(0.10)),
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurface.withOpacity(0.85),
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

  Widget _buildDemoSection(BuildContext context, LicenseInfo? info) {
    final active = info?.isActive == true && info?.isExpired == false;

    final scheme = Theme.of(context).colorScheme;
    final cardBorder = scheme.primary.withOpacity(0.22);
    final inputFill = scheme.surfaceVariant.withOpacity(0.35);

    InputDecoration fieldDecoration(String label) {
      return InputDecoration(
        labelText: label,
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
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
          if (!isTrial) _kv('Device ID', info?.deviceId ?? '-'),
          _kv('Vence', info?.fechaFin?.toLocal().toString() ?? '-'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Completa los datos del negocio para iniciar una DEMO.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _demoNombreNegocioCtrl,
          decoration: fieldDecoration('Nombre del negocio'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: rolesNegocio.contains(_demoRolNegocioSelected)
              ? _demoRolNegocioSelected
              : null,
          decoration: fieldDecoration('Tipo de negocio'),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          hint: const Text('Selecciona una opción'),
          items: rolesNegocio
              .map(
                (role) => DropdownMenuItem<String>(
                  value: role,
                  child: Text(role, overflow: TextOverflow.ellipsis),
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
        const SizedBox(height: 12),
        TextField(
          controller: _demoContactoNombreCtrl,
          decoration: fieldDecoration('Nombre contacto'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _demoContactoTelefonoCtrl,
          decoration: fieldDecoration('Teléfono contacto'),
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }

  Widget _buildFileSection(BuildContext context, LicenseInfo? info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sube tu archivo de licencia (JSON).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _kv('Proyecto', kFullposProjectCode),
        _kv('Device ID', info?.deviceId ?? '-'),
        if (_licenseFileName != null) _kv('Archivo', _licenseFileName!),
        if (_licenseFileStatus != null) ...[
          const SizedBox(height: 10),
          Text(_licenseFileStatus!),
        ],
      ],
    );
  }

  Widget _buildBuySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Para comprar tu licencia, contáctanos por WhatsApp.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'WhatsApp: $_supportPhoneDisplay',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$k:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

enum _LicenseSection { demo, file, buy, help }
