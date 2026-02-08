import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_sizes.dart';
import '../../../core/window/window_service.dart';
import '../../../core/brand/fullpos_brand_theme.dart';
import '../license_config.dart';
import '../data/license_models.dart';
import '../services/license_controller.dart';

class LicensePage extends ConsumerStatefulWidget {
  const LicensePage({super.key});

  @override
  ConsumerState<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends ConsumerState<LicensePage> {
  final _demoNombreNegocioCtrl = TextEditingController();
  final _demoRolNegocioCtrl = TextEditingController();
  final _demoContactoNombreCtrl = TextEditingController();
  final _demoContactoTelefonoCtrl = TextEditingController();

  String? _demoRolNegocioSelected;

  _LicenseSection _section = _LicenseSection.demo;

  String? _licenseFileName;
  String? _licenseFileStatus;

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
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    _licenseFileName = file.name;

    String raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null && file.path!.trim().isNotEmpty) {
      raw = await File(file.path!).readAsString();
    } else {
      setState(() {
        _licenseFileStatus = 'No se pudo leer el archivo seleccionado';
      });
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      setState(() {
        _licenseFileStatus = 'El archivo no es un JSON válido';
      });
      return;
    }
    if (decoded is! Map) {
      setState(() {
        _licenseFileStatus = 'Formato inválido: se esperaba un objeto JSON';
      });
      return;
    }

    setState(() {
      _licenseFileStatus = 'Verificando archivo...';
    });

    await controller.applyOfflineLicenseFile(decoded.cast<String, dynamic>());

    final st = ref.read(licenseControllerProvider);
    final info = st.info;
    setState(() {
      if (st.error != null && st.error!.trim().isNotEmpty) {
        _licenseFileStatus = st.error;
      } else if (info?.isActive == true && info?.isExpired == false) {
        _licenseFileStatus = 'Licencia aplicada y activa';
      } else {
        _licenseFileStatus = 'Archivo verificado. Verifica el estado.';
      }
    });
  }

  Future<void> _openWhatsapp() async {
    const phone = '18295319442';
    final url = 'https://wa.me/$phone';

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
  }) {
    final selected = _section == value;
    final onPressed = selected
        ? null
        : () {
            setState(() {
              _section = value;
            });
          };

    return Expanded(
      child: selected
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(licenseControllerProvider);
    final controller = ref.read(licenseControllerProvider.notifier);
    final info = state.info;

    ref.listen(licenseControllerProvider, (prev, next) {
      final err = next.error;
      if (err != null && err.isNotEmpty && err != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err)));
      }
      // Keep text fields in sync when info changes.
      final i = next.info;
      if (i != null) {
        // no-op
      }
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    final mutedText = onSurface.withOpacity(0.72);
    final cardBorder = scheme.primary.withOpacity(0.18);
    final dividerColor = scheme.onSurface.withOpacity(0.10);

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
    }

    final licenseActive = info?.isActive == true && info?.isExpired == false;

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
                  await controller.startDemo(
                    nombreNegocio: _demoNombreNegocioCtrl.text,
                    rolNegocio: _demoRolNegocioCtrl.text,
                    contactoNombre: _demoContactoNombreCtrl.text,
                    contactoTelefono: _demoContactoTelefonoCtrl.text,
                  );
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
                                            'Adquiere tu licencia y desbloquea FULLPOS',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: onSurface,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Proyecto: $kFullposProjectCode',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: mutedText),
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
                          Row(
                            children: [
                              _sectionButton(
                                value: _LicenseSection.demo,
                                label: 'Prueba',
                                icon: Icons.play_circle_outline,
                              ),
                              const SizedBox(width: 10),
                              _sectionButton(
                                value: _LicenseSection.file,
                                label: 'Archivo',
                                icon: Icons.upload_file,
                              ),
                              const SizedBox(width: 10),
                              _sectionButton(
                                value: _LicenseSection.buy,
                                label: 'Comprar',
                                icon: Icons.shopping_cart_outlined,
                              ),
                            ],
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Licencia activa',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _kv('Device ID', info?.deviceId ?? '-'),
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
          'WhatsApp: 8295319442',
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

enum _LicenseSection { demo, file, buy }
