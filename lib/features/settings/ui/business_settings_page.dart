import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../providers/business_settings_provider.dart';
import '../data/business_settings_model.dart';
import '../../../core/services/app_configuration_service.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/window/window_service.dart';
import '../../sales/data/app_settings_model.dart';
import '../../sales/data/settings_repository.dart';
import 'settings_layout.dart';

/// Página de configuración del negocio
class BusinessSettingsPage extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const BusinessSettingsPage({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<BusinessSettingsPage> createState() =>
      _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends ConsumerState<BusinessSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  BusinessSettings _draft = BusinessSettings.defaultSettings;
  String? _pendingLogoSourcePath;
  AppSettingsModel? _appSettings;

  // Controladores de texto
  final _businessNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phone2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _rncController = TextEditingController();
  final _sloganController = TextEditingController();
  final _websiteController = TextEditingController();
  final _instagramController = TextEditingController();
  final _facebookController = TextEditingController();

  bool _isLoading = false;
  bool _hasChanges = false;

  ColorScheme get _scheme => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex.clamp(0, 1);
    _tabController = TabController(length: 2, vsync: this, initialIndex: idx);
    _loadInitialValues(ref.read(businessSettingsProvider));
    _loadAppSettings();
  }

  void _loadInitialValues(BusinessSettings settings) {
    _draft = settings;
    _pendingLogoSourcePath = null;
    _businessNameController.text = settings.businessName;
    _phoneController.text = settings.phone ?? '';
    _phone2Controller.text = settings.phone2 ?? '';
    _emailController.text = settings.email ?? '';
    _addressController.text = settings.address ?? '';
    _cityController.text = settings.city ?? '';
    _rncController.text = settings.rnc ?? '';
    _sloganController.text = settings.slogan ?? '';
    _websiteController.text = settings.website ?? '';
    _instagramController.text = settings.instagramUrl ?? '';
    _facebookController.text = settings.facebookUrl ?? '';
  }

  Future<void> _loadAppSettings() async {
    try {
      final settings = await SettingsRepository.getAppSettings();
      if (!mounted) return;
      setState(() => _appSettings = settings);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando ajustes de ventas: $e'),
          backgroundColor: _scheme.error,
        ),
      );
    }
  }

  Future<void> _updateItbisDefault(bool value) async {
    final current = _appSettings;
    if (current == null) return;
    final updated = current.copyWith(itbisEnabledDefault: value);
    try {
      await SettingsRepository.updateAppSettings(updated);
      if (!mounted) return;
      setState(() => _appSettings = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error guardando ITBIS por defecto: $e'),
          backgroundColor: _scheme.error,
        ),
      );
    }
  }

  Future<void> _updateFiscalDefault(bool value) async {
    final current = _appSettings;
    if (current == null) return;
    final updated = current.copyWith(fiscalEnabledDefault: value);
    try {
      await SettingsRepository.updateAppSettings(updated);
      if (!mounted) return;
      setState(() => _appSettings = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error guardando NCF por defecto: $e'),
          backgroundColor: _scheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _businessNameController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _rncController.dispose();
    _sloganController.dispose();
    _websiteController.dispose();
    _instagramController.dispose();
    _facebookController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final result = await WindowService.runWithSystemDialog(
        () => FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        ),
      );

      if (result != null && result.files.single.path != null) {
        final sourcePath = result.files.single.path!;
        if (!mounted) return;
        setState(() {
          _pendingLogoSourcePath = sourcePath;
          _draft = _draft.copyWith(logoPath: sourcePath);
          _hasChanges = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Logo seleccionado (recuerda GUARDAR TODO)'),
              backgroundColor: _scheme.tertiary,
            ),
          );
        }
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _pickLogo,
          module: 'settings/business/logo',
        );
      }
    }
  }

  Future<void> _removeLogo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Logo'),
        content: const Text('¿Está seguro de eliminar el logo del negocio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _scheme.error),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    setState(() {
      _pendingLogoSourcePath = null;
      _draft = _draft.copyWith(clearLogoPath: true);
      _hasChanges = true;
    });
  }

  Future<void> _saveAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(businessSettingsProvider.notifier);
      final current = ref.read(businessSettingsProvider);

      String? logoToPersist;
      bool clearLogoPath = false;
      if (_draft.logoPath == null) {
        clearLogoPath = true;
      } else if (_pendingLogoSourcePath != null) {
        final sourcePath = _pendingLogoSourcePath!;
        final appDir = await getApplicationDocumentsDirectory();
        final logoDir = Directory(p.join(appDir.path, 'fullpos', 'logo'));

        if (!await logoDir.exists()) {
          await logoDir.create(recursive: true);
        }

        final previousLogoPath = current.logoPath;
        final extension = p.extension(sourcePath);
        final ts = DateTime.now().millisecondsSinceEpoch;
        final destPath = p.join(logoDir.path, 'business_logo_$ts$extension');
        await File(sourcePath).copy(destPath);
        logoToPersist = destPath;

        // Limpiar logo anterior para evitar acumulaciÇün (best-effort).
        try {
          final prev = (previousLogoPath ?? '').trim();
          if (prev.isNotEmpty &&
              prev != destPath &&
              p.isWithin(logoDir.path, prev) &&
              File(prev).existsSync()) {
            await File(prev).delete();
          }
        } catch (_) {}
      } else {
        logoToPersist = _draft.logoPath;
      }

      var updated = current.copyWith(
        businessName: _businessNameController.text.isNotEmpty
            ? _businessNameController.text
            : 'FULLPOS',
        phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
        phone2: _phone2Controller.text.isNotEmpty
            ? _phone2Controller.text
            : null,
        email: _emailController.text.isNotEmpty ? _emailController.text : null,
        address: _addressController.text.isNotEmpty
            ? _addressController.text
            : null,
        city: _cityController.text.isNotEmpty ? _cityController.text : null,
        rnc: _rncController.text.isNotEmpty ? _rncController.text : null,
        slogan: _sloganController.text.isNotEmpty
            ? _sloganController.text
            : null,
        website: _websiteController.text.isNotEmpty
            ? _websiteController.text
            : null,
        instagramUrl: _instagramController.text.isNotEmpty
            ? _instagramController.text
            : null,
        facebookUrl: _facebookController.text.isNotEmpty
            ? _facebookController.text
            : null,
        defaultTaxRate: _draft.defaultTaxRate,
        taxIncludedInPrices: _draft.taxIncludedInPrices,
        defaultCurrency: _draft.defaultCurrency,
        currencySymbol: _draft.currencySymbol,
      );

      if (clearLogoPath) {
        updated = updated.copyWith(clearLogoPath: true);
      } else if (logoToPersist != null) {
        updated = updated.copyWith(logoPath: logoToPersist);
      }

      await notifier.saveSettings(updated);
      if (!mounted) return;

      // Mantener servicio global sincronizado (usado por helpers/impresiones)
      appConfigService.updateSettings(updated);

      setState(() {
        _isLoading = false;
        _hasChanges = false;
        _pendingLogoSourcePath = null;
        _draft = updated;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Configuración guardada correctamente'),
            backgroundColor: _scheme.tertiary,
          ),
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _saveAll,
        module: 'settings/business/save',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mantenemos el provider activo (carga/actualiza desde DB) pero editamos contra _draft.
    ref.watch(businessSettingsProvider);

    // Mantener el borrador sincronizado con la DB mientras no haya cambios sin guardar.
    // Nota: `ref.listen` debe usarse dentro de `build` en Riverpod.
    ref.listen<BusinessSettings>(businessSettingsProvider, (previous, next) {
      if (!mounted) return;
      if (_hasChanges) return;
      setState(() {
        _loadInitialValues(next);
      });
    });
    final settings = _draft;

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
      appBar: AppBar(
        title: const Text('CONFIGURACIÓN DEL NEGOCIO'),
        actions: [
          if (_hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _scheme.secondary.withAlpha(50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'SIN GUARDAR',
                    style: TextStyle(
                      color: _scheme.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _saveAll,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : const Icon(Icons.save, color: Colors.black),
            label: const Text(
              'GUARDAR TODO',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black87,
          indicatorColor: Colors.black,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.store), text: 'Empresa'),
            Tab(icon: Icon(Icons.attach_money), text: 'Impuestos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCompanyTab(settings), _buildTaxesTab(settings)],
      ),
      ),
    );
  }

  Widget _buildCompanyTab(BusinessSettings settings) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        (MediaQuery.sizeOf(context).width * 0.04).clamp(12.0, 32.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Center(
            child: Column(
              children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: _scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _scheme.outlineVariant),
                  ),
                  child:
                      settings.logoPath != null &&
                          File(settings.logoPath!).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.file(
                            File(settings.logoPath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.store,
                              size: 48,
                              color: _scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sin Logo',
                              style: TextStyle(color: _scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickLogo,
                      icon: const Icon(Icons.upload),
                      label: const Text('Subir Logo'),
                    ),
                    if (settings.logoPath != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _isLoading ? null : _removeLogo,
                        icon: Icon(Icons.delete, color: _scheme.error),
                        label: Text(
                          'Eliminar',
                          style: TextStyle(color: _scheme.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Información del negocio
          _buildSectionTitle('INFORMACIÓN BÁSICA'),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _businessNameController,
                  label: 'Nombre del Negocio',
                  icon: Icons.store,
                  required: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _rncController,
                  label: 'RNC',
                  icon: Icons.badge,
                  hint: '000-000000-0',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _sloganController,
            label: 'Slogan',
            icon: Icons.format_quote,
            hint: 'Tu slogan aquí...',
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _phoneController,
                  label: 'Teléfono Principal',
                  icon: Icons.phone,
                  hint: '809-000-0000',
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _phone2Controller,
                  label: 'Teléfono Secundario',
                  icon: Icons.phone_android,
                  hint: '829-000-0000',
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _emailController,
                  label: 'Correo Electrónico',
                  icon: Icons.email,
                  hint: 'correo@ejemplo.com',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _websiteController,
                  label: 'Sitio Web',
                  icon: Icons.language,
                  hint: 'www.ejemplo.com',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _instagramController,
                  label: 'Instagram',
                  icon: Icons.photo_camera,
                  hint: '@tuempresa',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _facebookController,
                  label: 'Facebook',
                  icon: Icons.facebook,
                  hint: '/tuempresa',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _addressController,
                  label: 'Dirección',
                  icon: Icons.location_on,
                  hint: 'Calle, número, sector...',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _cityController,
                  label: 'Ciudad',
                  icon: Icons.location_city,
                  hint: 'Santo Domingo',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaxesTab(BusinessSettings settings) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        (MediaQuery.sizeOf(context).width * 0.04).clamp(12.0, 32.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('CONFIGURACIÓN DE IMPUESTOS'),
          const SizedBox(height: 24),

          // Tasa de impuesto
          _buildNumberField(
            label: 'Tasa de Impuesto (ITBIS)',
            value: settings.defaultTaxRate,
            suffix: '%',
            icon: Icons.receipt_long,
            min: 0,
            max: 100,
            onChanged: (value) {
              setState(() {
                _draft = _draft.copyWith(defaultTaxRate: value);
                _hasChanges = true;
              });
            },
          ),
          const SizedBox(height: 24),

          // Impuesto incluido en precios
          SwitchListTile(
            title: const Text('Impuesto incluido en precios'),
            subtitle: const Text(
              'Los precios de los productos ya incluyen el ITBIS',
            ),
            value: settings.taxIncludedInPrices,
            onChanged: (value) {
              setState(() {
                _draft = _draft.copyWith(taxIncludedInPrices: value);
                _hasChanges = true;
              });
            },
          ),
          SwitchListTile(
            title: const Text('ITBIS activo por defecto en ventas'),
            subtitle: const Text(
              'Define el estado inicial del switch de ITBIS en la pantalla de ventas.',
            ),
            value: _appSettings?.itbisEnabledDefault ?? false,
            onChanged: _appSettings == null ? null : _updateItbisDefault,
          ),
          SwitchListTile(
            title: const Text('NCF activo por defecto en ventas'),
            subtitle: const Text(
              'Define el estado inicial del switch de NCF (comprobante fiscal) en la pantalla de ventas.',
            ),
            value: _appSettings?.fiscalEnabledDefault ?? false,
            onChanged: _appSettings == null ? null : _updateFiscalDefault,
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          _buildSectionTitle('MONEDA'),
          const SizedBox(height: 16),

          // Selector de moneda
          DropdownButtonFormField<String>(
            initialValue: settings.defaultCurrency,
            decoration: InputDecoration(
              labelText: 'Moneda',
              prefixIcon: const Icon(Icons.attach_money),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'DOP',
                child: Text('Peso Dominicano (DOP)'),
              ),
              DropdownMenuItem(
                value: 'USD',
                child: Text('Dólar Estadounidense (USD)'),
              ),
              DropdownMenuItem(value: 'EUR', child: Text('Euro (EUR)')),
            ],
            onChanged: (value) {
              if (value != null) {
                String symbol;
                switch (value) {
                  case 'DOP':
                    symbol = 'RD\$';
                    break;
                  case 'USD':
                    symbol = '\$';
                    break;
                  case 'EUR':
                    symbol = '€';
                    break;
                  default:
                    symbol = '\$';
                }
                setState(() {
                  _draft = _draft.copyWith(
                    defaultCurrency: value,
                    currencySymbol: symbol,
                  );
                  _hasChanges = true;
                });
              }
            },
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _scheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text('Símbolo actual: '),
                Text(
                  settings.currencySymbol,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: _scheme.onSurfaceVariant,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: keyboardType,
      onChanged: (_) => setState(() => _hasChanges = true),
    );
  }

  Widget _buildNumberField({
    required String label,
    required double value,
    required String suffix,
    required IconData icon,
    required double min,
    required double max,
    String? helpText,
    required void Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                controller: TextEditingController(
                  text: value.toStringAsFixed(1),
                ),
                decoration: InputDecoration(
                  suffixText: suffix,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                onChanged: (text) {
                  final val = double.tryParse(text);
                  if (val != null && val >= min && val <= max) {
                    onChanged(val);
                  }
                },
              ),
            ),
          ],
        ),
        if (helpText != null)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 4),
            child: Text(
              helpText,
              style: TextStyle(color: _scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildIntField({
    required String label,
    required int value,
    required String suffix,
    required IconData icon,
    required int min,
    required int max,
    String? helpText,
    required void Function(int) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                controller: TextEditingController(text: value.toString()),
                decoration: InputDecoration(
                  suffixText: suffix,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (text) {
                  final val = int.tryParse(text);
                  if (val != null && val >= min && val <= max) {
                    onChanged(val);
                  }
                },
              ),
            ),
          ],
        ),
        if (helpText != null)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 4),
            child: Text(
              helpText,
              style: TextStyle(color: _scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
