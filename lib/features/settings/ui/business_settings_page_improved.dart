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

/// Página de configuración del negocio/empresa mejorada y completa
class BusinessSettingsPageImproved extends ConsumerStatefulWidget {
  const BusinessSettingsPageImproved({super.key});

  @override
  ConsumerState<BusinessSettingsPageImproved> createState() =>
      _BusinessSettingsPageImprovedState();
}

class _BusinessSettingsPageImprovedState
    extends ConsumerState<BusinessSettingsPageImproved>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
  final _receiptHeaderController = TextEditingController();
  final _receiptFooterController = TextEditingController();

  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialValues();
  }

  void _loadInitialValues() {
    final settings = ref.read(businessSettingsProvider);
    _businessNameController.text = settings.businessName;
    _phoneController.text = settings.phone ?? '';
    _phone2Controller.text = settings.phone2 ?? '';
    _emailController.text = settings.email ?? '';
    _addressController.text = settings.address ?? '';
    _cityController.text = settings.city ?? '';
    _rncController.text = settings.rnc ?? '';
    _sloganController.text = settings.slogan ?? '';
    _websiteController.text = settings.website ?? '';
    _receiptHeaderController.text = settings.receiptHeader;
    _receiptFooterController.text = settings.receiptFooter;
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
    _receiptHeaderController.dispose();
    _receiptFooterController.dispose();
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
      if (!mounted) return;

      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);

        final current = ref.read(businessSettingsProvider);
        final sourcePath = result.files.single.path!;
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

        // Limpiar logo anterior para evitar acumulaciÇün (best-effort).
        try {
          final prev = (current.logoPath ?? '').trim();
          if (prev.isNotEmpty &&
              prev != destPath &&
              p.isWithin(logoDir.path, prev) &&
              File(prev).existsSync()) {
            await File(prev).delete();
          }
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _hasChanges = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Logo actualizado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e, st) {
      if (mounted) setState(() => _isLoading = false);
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed == true) {
      await ref.read(businessSettingsProvider.notifier).updateLogo(null);
      if (!mounted) return;
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(businessSettingsProvider.notifier);
      final current = ref.read(businessSettingsProvider);

      final updated = current.copyWith(
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
        receiptHeader: _receiptHeaderController.text,
        receiptFooter: _receiptFooterController.text,
      );

      await notifier.saveSettings(updated);
      if (!mounted) return;

      // Actualizar servicio global de configuración
      appConfigService.updateSettings(updated);

      setState(() {
        _isLoading = false;
        _hasChanges = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Configuración guardada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      setState(() => _isLoading = false);
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _saveAll,
          module: 'settings/business/save',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(businessSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CONFIGURACIÓN DEL NEGOCIO'),
        elevation: 0,
        actions: [
          if (_hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(50),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange, width: 1),
                  ),
                  child: const Text(
                    'Cambios sin guardar',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: _isLoading ? null : _saveAll,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save, color: Colors.white),
            label: const Text(
              'GUARDAR TODO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Empresa'),
            Tab(text: 'Contacto'),
            Tab(text: 'Impuestos'),
            Tab(text: 'Avanzado'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCompanyTab(settings),
          _buildContactTab(settings),
          _buildTaxesTab(settings),
          _buildAdvancedTab(settings),
        ],
      ),
    );
  }

  // ========== TAB 1: INFORMACIÓN DE LA EMPRESA ==========
  Widget _buildCompanyTab(BusinessSettings settings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Logo Section
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Logo de la Empresa',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child:
                        settings.logoPath != null &&
                            File(settings.logoPath!).existsSync()
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(settings.logoPath!),
                              fit: BoxFit.contain,
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_not_supported,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Sin logo',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _pickLogo,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('SUBIR LOGO'),
                        ),
                      ),
                      if (settings.logoPath != null) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _removeLogo,
                          icon: const Icon(Icons.delete),
                          label: const Text('ELIMINAR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Nombre del Negocio
          _buildTextField(
            controller: _businessNameController,
            label: 'Nombre del Negocio',
            hint: 'Ej: FULLPOS S.A.',
            icon: Icons.business,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),
          const SizedBox(height: 12),

          // Slogan
          _buildTextField(
            controller: _sloganController,
            label: 'Eslogan/Lema',
            hint: 'Ej: Calidad y confianza',
            icon: Icons.stars,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),

          // RNC
          _buildTextField(
            controller: _rncController,
            label: 'RNC (Registro Nacional de Contribuyentes)',
            hint: 'Ej: 123456789',
            icon: Icons.badge,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => _hasChanges = true),
          ),

          // Website
          _buildTextField(
            controller: _websiteController,
            label: 'Sitio Web',
            hint: 'Ej: www.minegocio.com',
            icon: Icons.language,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),
        ],
      ),
    );
  }

  // ========== TAB 2: INFORMACIÓN DE CONTACTO ==========
  Widget _buildContactTab(BusinessSettings settings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTextField(
            controller: _phoneController,
            label: 'Teléfono Principal',
            hint: 'Ej: +1-809-123-4567',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: _phone2Controller,
            label: 'Teléfono Secundario',
            hint: 'Ej: +1-809-987-6543',
            icon: Icons.phone_in_talk,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'Ej: info@minegocio.com',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: _addressController,
            label: 'Dirección',
            hint: 'Ej: Calle Principal 123',
            icon: Icons.location_on,
            maxLines: 2,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: _cityController,
            label: 'Ciudad/Municipio',
            hint: 'Ej: Santo Domingo',
            icon: Icons.location_city,
            onChanged: (_) => setState(() => _hasChanges = true),
          ),
        ],
      ),
    );
  }

  // ========== TAB 4: CONFIGURACIÓN DE IMPUESTOS ==========
  Widget _buildTaxesTab(BusinessSettings settings) {
    final notifier = ref.read(businessSettingsProvider.notifier);

    double taxRate = settings.defaultTaxRate;
    bool taxIncluded = settings.taxIncludedInPrices;

    return StatefulBuilder(
      builder: (context, setState) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Tasa de Impuesto
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tasa de Impuesto (ITBIS %)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${taxRate.toStringAsFixed(2)}%',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: taxRate,
                      min: 0,
                      max: 30,
                      divisions: 300,
                      onChanged: (value) {
                        setState(() => taxRate = value);
                        notifier.updateDefaultTaxRate(value);
                        this.setState(() => _hasChanges = true);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Impuesto Incluido
            Card(
              child: SwitchListTile(
                title: const Text('Impuesto Incluido en los Precios'),
                subtitle: Text(
                  taxIncluded
                      ? 'Los precios mostrados ya incluyen el impuesto'
                      : 'El impuesto se suma al precio final',
                ),
                value: taxIncluded,
                onChanged: (value) {
                  setState(() => taxIncluded = value);
                  notifier.updateTaxIncludedInPrices(value);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Información de Moneda
            _buildTextField(
              readOnly: true,
              controller: TextEditingController(text: settings.defaultCurrency),
              label: 'Moneda',
              icon: Icons.attach_money,
            ),
            const SizedBox(height: 12),

            _buildTextField(
              readOnly: true,
              controller: TextEditingController(text: settings.currencySymbol),
              label: 'Símbolo de Moneda',
              icon: Icons.monetization_on,
            ),
          ],
        ),
      ),
    );
  }

  // ========== TAB 5: CONFIGURACIÓN AVANZADA ==========
  Widget _buildAdvancedTab(BusinessSettings settings) {
    final notifier = ref.read(businessSettingsProvider.notifier);

    return StatefulBuilder(
      builder: (context, setState) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Funciones Avanzadas y Características',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),

            // Notificaciones
            Card(
              child: SwitchListTile(
                title: const Text('Notificaciones'),
                subtitle: const Text(
                  'Recibir alertas y notificaciones del sistema',
                ),
                value: settings.enableNotifications,
                onChanged: (value) {
                  notifier.updateEnableNotifications(value);
                  setState(() => _hasChanges = true);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Backup Automático
            Card(
              child: SwitchListTile(
                title: const Text('Backup Automático'),
                subtitle: const Text('Respaldar datos automáticamente'),
                value: settings.enableAutoBackup,
                onChanged: (value) {
                  notifier.updateEnableAutoBackup(value);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Rastreo de Inventario
            Card(
              child: SwitchListTile(
                title: const Text('Rastreo de Inventario'),
                subtitle: const Text('Controlar inventario de productos'),
                value: settings.enableInventoryTracking,
                onChanged: (value) {
                  notifier.updateEnableInventoryTracking(value);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Aprobación de Clientes
            Card(
              child: SwitchListTile(
                title: const Text('Aprobación de Clientes Nuevos'),
                subtitle: const Text(
                  'Requiere aprobación para agregar nuevos clientes',
                ),
                value: settings.enableClientApproval,
                onChanged: (value) {
                  notifier.updateEnableClientApproval(value);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Encriptación de Datos
            Card(
              child: SwitchListTile(
                title: const Text('Encriptación de Datos'),
                subtitle: const Text(
                  'Proteger datos sensibles con encriptación',
                ),
                value: settings.enableDataEncryption,
                onChanged: (value) {
                  notifier.updateEnableDataEncryption(value);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Detalles en Dashboard
            Card(
              child: SwitchListTile(
                title: const Text('Detalles en Dashboard'),
                subtitle: const Text(
                  'Mostrar información detallada en el panel principal',
                ),
                value: settings.showDetailsOnDashboard,
                onChanged: (value) {
                  notifier.updateShowDetailsOnDashboard(value);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Modo Oscuro
            Card(
              child: SwitchListTile(
                title: const Text('Modo Oscuro'),
                subtitle: const Text('Usar tema oscuro en la aplicación'),
                value: settings.darkModeEnabled,
                onChanged: (value) {
                  notifier.updateDarkModeEnabled(value);
                  this.setState(() => _hasChanges = true);
                },
              ),
            ),
            const SizedBox(height: 16),

            // Timeout de Sesión
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Timeout de Sesión',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${settings.sessionTimeoutMinutes} min',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: settings.sessionTimeoutMinutes.toDouble(),
                      min: 5,
                      max: 120,
                      divisions: 23,
                      onChanged: (value) {
                        notifier.updateSessionTimeoutMinutes(value.toInt());
                        this.setState(() => _hasChanges = true);
                      },
                    ),
                    const Text(
                      'Tiempo de inactividad antes de cerrar sesión',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Utilidad para construir campos de texto
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    Function(String)? onChanged,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: readOnly,
        fillColor: readOnly ? Colors.grey.shade100 : null,
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      readOnly: readOnly,
    );
  }
}
