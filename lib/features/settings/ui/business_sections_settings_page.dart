import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/window/window_service.dart';
import '../data/business_settings_model.dart';
import '../providers/business_settings_provider.dart';
import 'settings_layout.dart';

class CompanyProfileSettingsPage extends ConsumerStatefulWidget {
  const CompanyProfileSettingsPage({super.key});

  @override
  ConsumerState<CompanyProfileSettingsPage> createState() =>
      _CompanyProfileSettingsPageState();
}

class _CompanyProfileSettingsPageState
    extends ConsumerState<CompanyProfileSettingsPage> {
  final _businessNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phone2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _rncController = TextEditingController();
  final _sloganController = TextEditingController();
  final _websiteController = TextEditingController();

  bool _didLoadInitialValues = false;
  bool _isSaving = false;
  bool _isUpdatingLogo = false;
  bool _hasChanges = false;

  @override
  void dispose() {
    _businessNameController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _rncController.dispose();
    _sloganController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  void _loadInitialValues(BusinessSettings settings) {
    if (_didLoadInitialValues) return;
    _didLoadInitialValues = true;
    _businessNameController.text = settings.businessName;
    _phoneController.text = settings.phone ?? '';
    _phone2Controller.text = settings.phone2 ?? '';
    _emailController.text = settings.email ?? '';
    _addressController.text = settings.address ?? '';
    _cityController.text = settings.city ?? '';
    _rncController.text = settings.rnc ?? '';
    _sloganController.text = settings.slogan ?? '';
    _websiteController.text = settings.website ?? '';
  }

  String _normalizeOptional(String value) => value.trim();

  void _markDirty([String? _]) {
    if (_hasChanges) return;
    setState(() => _hasChanges = true);
  }

  Future<void> _pickLogo() async {
    try {
      final result = await WindowService.runWithSystemDialog(
        () => FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        ),
      );
      if (!mounted || result?.files.single.path == null) return;

      setState(() => _isUpdatingLogo = true);

      final sourcePath = result!.files.single.path!;
      final current = ref.read(businessSettingsProvider);
      final appDir = await getApplicationDocumentsDirectory();
      final logoDir = Directory(p.join(appDir.path, 'fullpos', 'logo'));
      if (!await logoDir.exists()) {
        await logoDir.create(recursive: true);
      }

      final extension = p.extension(sourcePath);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final destPath = p.join(logoDir.path, 'business_logo_$ts$extension');

      await File(sourcePath).copy(destPath);
      await ref.read(businessSettingsProvider.notifier).updateLogo(destPath);

      try {
        final previousPath = (current.logoPath ?? '').trim();
        if (previousPath.isNotEmpty &&
            previousPath != destPath &&
            p.isWithin(logoDir.path, previousPath) &&
            File(previousPath).existsSync()) {
          await File(previousPath).delete();
        }
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo actualizado correctamente')),
      );
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _pickLogo,
          module: 'settings/company/logo',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingLogo = false);
      }
    }
  }

  Future<void> _removeLogo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar logo'),
        content: const Text('Se quitará el logo del negocio en toda la app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isUpdatingLogo = true);
    try {
      await ref.read(businessSettingsProvider.notifier).updateLogo(null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo eliminado correctamente')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingLogo = false);
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final current = ref.read(businessSettingsProvider);
      final updated = current.copyWith(
        businessName: _businessNameController.text.trim().isEmpty
            ? 'FULLPOS'
            : _businessNameController.text.trim(),
        phone: _normalizeOptional(_phoneController.text),
        phone2: _normalizeOptional(_phone2Controller.text),
        email: _normalizeOptional(_emailController.text),
        address: _normalizeOptional(_addressController.text),
        city: _normalizeOptional(_cityController.text),
        rnc: _normalizeOptional(_rncController.text),
        slogan: _normalizeOptional(_sloganController.text),
        website: _normalizeOptional(_websiteController.text),
      );
      await ref.read(businessSettingsProvider.notifier).saveSettings(updated);
      String feedback = 'Información de empresa guardada';
      try {
        await CloudSyncService.instance.syncCompanyConfigIfEnabled();
        feedback = 'Empresa guardada y sincronizada con el backend';
      } catch (_) {
        feedback =
            'Empresa guardada localmente, pero la sincronización backend falló';
      }
      if (!mounted) return;
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(feedback)),
      );
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _save,
          module: 'settings/company/save',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(businessSettingsProvider);
    _loadInitialValues(settings);

    return _SettingsDetailScaffold(
      title: 'Empresa',
      icon: Icons.business_outlined,
      onSave: _save,
      isSaving: _isSaving,
      hasChanges: _hasChanges,
      child: _SettingsSectionGrid(
        children: [
          _SettingsSectionCard(
            title: 'Logo',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final preview = _LogoPreview(
                  logoPath: settings.logoPath,
                  isBusy: _isUpdatingLogo,
                );
                final actions = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _isUpdatingLogo ? null : _pickLogo,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Subir logo'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: (_isUpdatingLogo || settings.logoPath == null)
                          ? null
                          : _removeLogo,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Quitar logo'),
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    children: [preview, const SizedBox(height: 16), actions],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: preview),
                    const SizedBox(width: 18),
                    Expanded(child: actions),
                  ],
                );
              },
            ),
          ),
          _SettingsSectionCard(
            title: 'Empresa',
            child: _ResponsiveFieldWrap(
              children: [
                _SettingsTextField(
                  controller: _businessNameController,
                  label: 'Nombre del negocio',
                  icon: Icons.storefront_outlined,
                  onChanged: _markDirty,
                ),
                _SettingsTextField(
                  controller: _sloganController,
                  label: 'Eslogan o lema',
                  icon: Icons.campaign_outlined,
                  onChanged: _markDirty,
                ),
                _SettingsTextField(
                  controller: _rncController,
                  label: 'RNC',
                  icon: Icons.badge_outlined,
                  onChanged: _markDirty,
                ),
                _SettingsTextField(
                  controller: _websiteController,
                  label: 'Sitio web',
                  icon: Icons.language_outlined,
                  keyboardType: TextInputType.url,
                  onChanged: _markDirty,
                ),
              ],
            ),
          ),
          _SettingsSectionCard(
            title: 'Contacto',
            child: _ResponsiveFieldWrap(
              children: [
                _SettingsTextField(
                  controller: _phoneController,
                  label: 'Teléfono principal',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  onChanged: _markDirty,
                ),
                _SettingsTextField(
                  controller: _phone2Controller,
                  label: 'Teléfono secundario',
                  icon: Icons.phone_forwarded_outlined,
                  keyboardType: TextInputType.phone,
                  onChanged: _markDirty,
                ),
                _SettingsTextField(
                  controller: _emailController,
                  label: 'Correo electrónico',
                  icon: Icons.alternate_email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: _markDirty,
                ),
                _SettingsTextField(
                  controller: _cityController,
                  label: 'Ciudad',
                  icon: Icons.location_city_outlined,
                  onChanged: _markDirty,
                ),
                _SettingsTextField(
                  controller: _addressController,
                  label: 'Dirección',
                  icon: Icons.place_outlined,
                  maxLines: 2,
                  expandWide: true,
                  onChanged: _markDirty,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TaxSettingsPage extends ConsumerStatefulWidget {
  const TaxSettingsPage({super.key});

  @override
  ConsumerState<TaxSettingsPage> createState() => _TaxSettingsPageState();
}

class _TaxSettingsPageState extends ConsumerState<TaxSettingsPage> {
  final _rateController = TextEditingController();
  bool _itbisEnabled = true;
  bool _includeTaxInPrice = true;
  bool _didLoadInitialValues = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  void _loadInitialValues(BusinessSettings settings) {
    if (_didLoadInitialValues) return;
    _didLoadInitialValues = true;
    _rateController.text = settings.defaultTaxRate.toStringAsFixed(2);
    _itbisEnabled = settings.itbisEnabled;
    _includeTaxInPrice = settings.taxIncludedInPrices;
  }

  double get _rateValue {
    final parsed = double.tryParse(_rateController.text.replaceAll(',', '.'));
    return (parsed ?? 18).clamp(0, 100).toDouble();
  }

  void _markDirty() {
    if (_hasChanges) return;
    setState(() => _hasChanges = true);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final current = ref.read(businessSettingsProvider);
      final updated = current.copyWith(
        defaultTaxRate: _rateValue,
        itbisEnabled: _itbisEnabled,
        taxIncludedInPrices: _includeTaxInPrice,
      );
      await ref.read(businessSettingsProvider.notifier).saveSettings(updated);
      if (!mounted) return;
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impuestos guardados correctamente')),
      );
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _save,
          module: 'settings/tax/save',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(businessSettingsProvider);
    _loadInitialValues(settings);

    return _SettingsDetailScaffold(
      title: 'Impuestos',
      icon: Icons.receipt_long_outlined,
      onSave: _save,
      isSaving: _isSaving,
      hasChanges: _hasChanges,
      child: _SettingsSectionGrid(
        children: [
          _SettingsSectionCard(
            title: 'ITBIS',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleTile(
                  title: 'Activar ITBIS',
                  value: _itbisEnabled,
                  onChanged: (value) {
                    setState(() {
                      _itbisEnabled = value;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _ResponsiveFieldWrap(
                  children: [
                    _SettingsTextField(
                      controller: _rateController,
                      label: 'Tasa por defecto (%)',
                      icon: Icons.percent_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => _markDirty(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in const [0.0, 16.0, 18.0])
                      ChoiceChip(
                        label: Text('${value.toStringAsFixed(0)}%'),
                        selected: (_rateValue - value).abs() < 0.01,
                        onSelected: (_) {
                          setState(() {
                            _rateController.text = value.toStringAsFixed(2);
                            _hasChanges = true;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _rateValue,
                  min: 0,
                  max: 30,
                  divisions: 60,
                  label: '${_rateValue.toStringAsFixed(2)}%',
                  onChanged: (value) {
                    setState(() {
                      _rateController.text = value.toStringAsFixed(2);
                      _hasChanges = true;
                    });
                  },
                ),
              ],
            ),
          ),
          _SettingsSectionCard(
            title: 'Precios',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleTile(
                  title: 'Los precios ya incluyen ITBIS',
                  value: _includeTaxInPrice,
                  onChanged: (value) {
                    setState(() {
                      _includeTaxInPrice = value;
                      _hasChanges = true;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CurrencySettingsPage extends ConsumerStatefulWidget {
  const CurrencySettingsPage({super.key});

  @override
  ConsumerState<CurrencySettingsPage> createState() =>
      _CurrencySettingsPageState();
}

class _CurrencySettingsPageState extends ConsumerState<CurrencySettingsPage> {
  static const List<Map<String, String>> _currencies = [
    {'code': 'DOP', 'symbol': 'RD\$'},
    {'code': 'USD', 'symbol': '\$'},
    {'code': 'EUR', 'symbol': '€'},
    {'code': 'MXN', 'symbol': 'MX\$'},
  ];

  final _symbolController = TextEditingController();
  String _currencyCode = 'DOP';
  bool _didLoadInitialValues = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void dispose() {
    _symbolController.dispose();
    super.dispose();
  }

  void _loadInitialValues(BusinessSettings settings) {
    if (_didLoadInitialValues) return;
    _didLoadInitialValues = true;
    _currencyCode = settings.defaultCurrency;
    _symbolController.text = settings.currencySymbol;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final symbol = _symbolController.text.trim().isEmpty
          ? 'RD\$'
          : _symbolController.text.trim();
      await ref
          .read(businessSettingsProvider.notifier)
          .updateCurrency(_currencyCode, symbol);
      if (!mounted) return;
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Moneda guardada correctamente')),
      );
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _save,
          module: 'settings/currency/save',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(businessSettingsProvider);
    _loadInitialValues(settings);

    return _SettingsDetailScaffold(
      title: 'Moneda',
      icon: Icons.attach_money_outlined,
      onSave: _save,
      isSaving: _isSaving,
      hasChanges: _hasChanges,
      child: _SettingsSectionGrid(
        children: [
          _SettingsSectionCard(
            title: 'Moneda base',
            child: _ResponsiveFieldWrap(
              children: [
                _SettingsDropdownField<String>(
                  value:
                      _currencies.any((item) => item['code'] == _currencyCode)
                      ? _currencyCode
                      : _currencies.first['code']!,
                  label: 'Código de moneda',
                  icon: Icons.currency_exchange_outlined,
                  items: [
                    for (final item in _currencies)
                      DropdownMenuItem<String>(
                        value: item['code'],
                        child: Text('${item['code']} · ${item['symbol']}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final matched = _currencies.firstWhere(
                      (item) => item['code'] == value,
                      orElse: () => _currencies.first,
                    );
                    setState(() {
                      _currencyCode = value;
                      if (_symbolController.text.trim().isEmpty ||
                          _currencies.any(
                            (item) =>
                                item['symbol'] == _symbolController.text.trim(),
                          )) {
                        _symbolController.text = matched['symbol'] ?? 'RD\$';
                      }
                      _hasChanges = true;
                    });
                  },
                ),
                _SettingsTextField(
                  controller: _symbolController,
                  label: 'Símbolo mostrado',
                  icon: Icons.sell_outlined,
                  onChanged: (_) {
                    if (_hasChanges) return;
                    setState(() => _hasChanges = true);
                  },
                ),
              ],
            ),
          ),
          _SettingsSectionCard(
            title: 'Vista previa',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withOpacity(0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ejemplo de importe',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_symbolController.text.trim().isEmpty ? 'RD\$' : _symbolController.text.trim()} 1,250.00',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Código: $_currencyCode',
                    style: Theme.of(context).textTheme.bodyMedium,
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

class PosGeneralSettingsPage extends ConsumerStatefulWidget {
  const PosGeneralSettingsPage({super.key});

  @override
  ConsumerState<PosGeneralSettingsPage> createState() =>
      _PosGeneralSettingsPageState();
}

class _PosGeneralSettingsPageState
    extends ConsumerState<PosGeneralSettingsPage> {
  final _invoiceObservationController = TextEditingController();
  bool _enableFullQuotesFlow = false;
  bool _enableAutoBackup = true;
  bool _enableNotifications = true;
  bool _enableInventoryTracking = true;
  bool _enableClientApproval = false;
  bool _enableDataEncryption = true;
  bool _showDetailsOnDashboard = true;
  int _sessionTimeoutMinutes = 30;
  String _defaultChargeOutputMode = 'ticket';

  bool _didLoadInitialValues = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void dispose() {
    _invoiceObservationController.dispose();
    super.dispose();
  }

  void _loadInitialValues(BusinessSettings settings) {
    if (_didLoadInitialValues) return;
    _didLoadInitialValues = true;
    _invoiceObservationController.text = settings.receiptHeader;
    _enableFullQuotesFlow = settings.enableFullQuotesFlow;
    _enableAutoBackup = settings.enableAutoBackup;
    _enableNotifications = settings.enableNotifications;
    _enableInventoryTracking = settings.enableInventoryTracking;
    _enableClientApproval = settings.enableClientApproval;
    _enableDataEncryption = settings.enableDataEncryption;
    _showDetailsOnDashboard = settings.showDetailsOnDashboard;
    _sessionTimeoutMinutes = settings.sessionTimeoutMinutes;
    _defaultChargeOutputMode = settings.defaultChargeOutputMode;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final current = ref.read(businessSettingsProvider);
      final updated = current.copyWith(
        receiptHeader: _invoiceObservationController.text.trim(),
        defaultChargeOutputMode: _defaultChargeOutputMode,
        enableFullQuotesFlow: _enableFullQuotesFlow,
        enableAutoBackup: _enableAutoBackup,
        enableNotifications: _enableNotifications,
        enableInventoryTracking: _enableInventoryTracking,
        enableClientApproval: _enableClientApproval,
        enableDataEncryption: _enableDataEncryption,
        showDetailsOnDashboard: _showDetailsOnDashboard,
        sessionTimeoutMinutes: _sessionTimeoutMinutes,
      );
      await ref.read(businessSettingsProvider.notifier).saveSettings(updated);
      if (!mounted) return;
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajustes generales guardados')),
      );
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _save,
          module: 'settings/pos_general/save',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(businessSettingsProvider);
    _loadInitialValues(settings);

    return _SettingsDetailScaffold(
      title: 'General POS',
      icon: Icons.tune_outlined,
      onSave: _save,
      isSaving: _isSaving,
      hasChanges: _hasChanges,
      child: _SettingsSectionGrid(
        children: [
          _SettingsSectionCard(
            title: 'Cobro',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ResponsiveFieldWrap(
                  children: [
                    _SettingsDropdownField<String>(
                      value: _defaultChargeOutputMode,
                      label: 'Salida predeterminada al cobrar',
                      icon: Icons.print_outlined,
                      items: const [
                        DropdownMenuItem(
                          value: 'ticket',
                          child: Text('Imprimir ticket'),
                        ),
                        DropdownMenuItem(
                          value: 'pdf',
                          child: Text('Descargar PDF'),
                        ),
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Sin salida automática'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _defaultChargeOutputMode = value;
                          _hasChanges = true;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _SettingsTextField(
                  controller: _invoiceObservationController,
                  label: 'Observación predeterminada en PDF/factura',
                  icon: Icons.note_alt_outlined,
                  maxLines: 2,
                  expandWide: true,
                  onChanged: (_) {
                    if (_hasChanges) return;
                    setState(() => _hasChanges = true);
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'La impresión automática y las opciones del ticket se administran en Impresora. Aquí solo defines la salida al cobrar y la observación usada en PDF/factura.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SettingsSectionCard(
            title: 'Operación',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleTile(
                  title: 'Activar flujo completo de cotizaciones',
                  value: _enableFullQuotesFlow,
                  onChanged: (value) {
                    setState(() {
                      _enableFullQuotesFlow = value;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ToggleTile(
                  title: 'Rastreo de inventario activo',
                  value: _enableInventoryTracking,
                  onChanged: (value) {
                    setState(() {
                      _enableInventoryTracking = value;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ToggleTile(
                  title: 'Solicitar aprobación para clientes nuevos',
                  value: _enableClientApproval,
                  onChanged: (value) {
                    setState(() {
                      _enableClientApproval = value;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ToggleTile(
                  title: 'Mostrar detalles en dashboard',
                  value: _showDetailsOnDashboard,
                  onChanged: (value) {
                    setState(() {
                      _showDetailsOnDashboard = value;
                      _hasChanges = true;
                    });
                  },
                ),
              ],
            ),
          ),
          _SettingsSectionCard(
            title: 'Sistema',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleTile(
                  title: 'Backup automático',
                  value: _enableAutoBackup,
                  onChanged: (value) {
                    setState(() {
                      _enableAutoBackup = value;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ToggleTile(
                  title: 'Notificaciones activas',
                  value: _enableNotifications,
                  onChanged: (value) {
                    setState(() {
                      _enableNotifications = value;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ToggleTile(
                  title: 'Encriptación de datos',
                  value: _enableDataEncryption,
                  onChanged: (value) {
                    setState(() {
                      _enableDataEncryption = value;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tiempo de cierre de sesión: $_sessionTimeoutMinutes min',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Slider(
                  value: _sessionTimeoutMinutes.toDouble().clamp(5, 180),
                  min: 5,
                  max: 180,
                  divisions: 35,
                  label: '$_sessionTimeoutMinutes min',
                  onChanged: (value) {
                    setState(() {
                      _sessionTimeoutMinutes = value.round();
                      _hasChanges = true;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsDetailScaffold extends StatelessWidget {
  const _SettingsDetailScaffold({
    required this.title,
    required this.icon,
    required this.child,
    required this.onSave,
    required this.isSaving,
    required this.hasChanges,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Future<void> Function() onSave;
  final bool isSaving;
  final bool hasChanges;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(hasChanges ? 'Guardar' : 'Guardar igual'),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              max: 1180,
              child: SizedBox.expand(child: child),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SettingsSectionGrid extends StatelessWidget {
  const _SettingsSectionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final compactHeight = height < 760;
        final spacing = compactHeight ? 10.0 : 14.0;
        final columns = width >= 980 ? 2 : 1;
        final itemWidth = columns == 1 ? width : (width - spacing) / 2;

        return Align(
          alignment: Alignment.topCenter,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final child in children)
                SizedBox(width: itemWidth, child: child),
            ],
          ),
        );
      },
    );
  }
}

class _ResponsiveFieldWrap extends StatelessWidget {
  const _ResponsiveFieldWrap({required this.children});

  final List<_SettingsFieldSpec> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final spacing = maxWidth < 720 ? 10.0 : 12.0;
        final singleColumn = maxWidth < 720;
        final fieldWidth = singleColumn ? maxWidth : (maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: child.expandWide && !singleColumn
                    ? maxWidth
                    : fieldWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

abstract class _SettingsFieldSpec extends StatelessWidget {
  const _SettingsFieldSpec({required this.expandWide});

  final bool expandWide;
}

class _SettingsTextField extends _SettingsFieldSpec {
  const _SettingsTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.onChanged,
    super.expandWide = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SettingsDropdownField<T> extends _SettingsFieldSpec {
  const _SettingsDropdownField({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
    super.expandWide = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest.withOpacity(0.35),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({required this.logoPath, required this.isBusy});

  final String? logoPath;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasLogo =
        logoPath != null &&
        logoPath!.trim().isNotEmpty &&
        File(logoPath!).existsSync();
    return Container(
      height: 144,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.45)),
      ),
      child: Center(
        child: isBusy
            ? const CircularProgressIndicator()
            : hasLogo
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(logoPath!), fit: BoxFit.contain),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 54,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sin logo configurado',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
