import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../core/printing/simplified_ticket_preview_widget.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/printing/models/models.dart';
import '../data/printer_settings_model.dart';
import '../data/printer_settings_repository.dart';
import 'settings_layout.dart';

/// Página de configuración de impresora y ticket mejorada
/// con controles avanzados y vista previa en tiempo real
class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  late PrinterSettingsModel _settings;
  CompanyInfo? _companyInfo;
  List<Printer> _availablePrinters = [];
  bool _loading = true;
  bool _printing = false;
  bool _saving = false;

  ColorScheme get _scheme => Theme.of(context).colorScheme;

  // Controllers para TextFields (solo footer, resto viene de CompanyInfo)
  late TextEditingController _footerCtrl;
  late TextEditingController _headerExtraCtrl;
  late TextEditingController _warrantyPolicyCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadData();
  }

  void _initControllers() {
    _footerCtrl = TextEditingController();
    _headerExtraCtrl = TextEditingController();
    _warrantyPolicyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _footerCtrl.dispose();
    _headerExtraCtrl.dispose();
    _warrantyPolicyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();
      final printers = await UnifiedTicketPrinter.getAvailablePrinters();

      // Cargar información de empresa desde fuente única
      final companyInfo = await CompanyInfoRepository.getCurrentCompanyInfo();

      _headerExtraCtrl.text = settings.headerExtra ?? '';
      _footerCtrl.text = settings.footerMessage;
      _warrantyPolicyCtrl.text = settings.warrantyPolicy;

      if (!mounted) return;
      setState(() {
        _settings = settings;
        _companyInfo = companyInfo;
        _availablePrinters = printers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando configuración de impresora: $e'),
          backgroundColor: _scheme.error,
        ),
      );
    }
  }

  Future<void> _refreshPrinters() async {
    final printers = await UnifiedTicketPrinter.getAvailablePrinters();
    if (!mounted) return;
    setState(() => _availablePrinters = printers);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${printers.length} impresora(s) encontrada(s)'),
          backgroundColor: _scheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;
    setState(() => _saving = true);

    final updatedSettings = _settings.copyWith(
      headerExtra: _headerExtraCtrl.text.trim(),
      footerMessage: _footerCtrl.text.trim(),
      warrantyPolicy: _warrantyPolicyCtrl.text.trim(),
      // Guardar datos de empresa desde CompanyInfo (sin duplicar)
      headerBusinessName: _companyInfo?.name ?? 'FULLPOS',
      headerRnc: _companyInfo?.rnc,
      headerAddress: _companyInfo?.address,
      headerPhone: _companyInfo?.primaryPhone,
    );

    try {
      await PrinterSettingsRepository.updateSettings(updatedSettings);

      if (!mounted) return;
      setState(() {
        _settings = updatedSettings;
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: _scheme.onTertiary),
              SizedBox(width: 8),
              Text('Configuración guardada correctamente'),
            ],
          ),
          backgroundColor: _scheme.tertiary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la configuración: $e'),
          backgroundColor: _scheme.error,
        ),
      );
    }
  }

  Future<void> _printTest() async {
    if (_settings.selectedPrinterName == null ||
        _settings.selectedPrinterName!.isEmpty) {
      _showNoPrinterWarning();
      return;
    }

    if (!mounted) return;
    setState(() => _printing = true);

    // Usar el nuevo sistema unificado
    PrintTicketResult result;
    try {
      result = await UnifiedTicketPrinter.printTestTicket();
    } catch (e, st) {
      debugPrint('Error printing test ticket: $e\\n$st');
      if (mounted) {
        setState(() => _printing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al imprimir: $e'),
            backgroundColor: _scheme.error,
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _printing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.success ? Icons.print : Icons.error,
                color: result.success ? _scheme.onTertiary : _scheme.onError,
              ),
              const SizedBox(width: 8),
              Text(
                result.success
                    ? 'Impresión de prueba enviada'
                    : 'Error al imprimir',
              ),
            ],
          ),
          backgroundColor: result.success ? _scheme.tertiary : _scheme.error,
        ),
      );
    }
  }

  Future<void> _printWidthRuler() async {
    if (_settings.selectedPrinterName == null ||
        _settings.selectedPrinterName!.isEmpty) {
      _showNoPrinterWarning();
      return;
    }

    if (!mounted) return;
    setState(() => _printing = true);
    final result = await UnifiedTicketPrinter.printWidthRulerTest();
    if (mounted) setState(() => _printing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.success ? Icons.straighten : Icons.error,
                color: result.success ? _scheme.onTertiary : _scheme.onError,
              ),
              const SizedBox(width: 8),
              Text(
                result.success
                    ? 'Regla de ancho enviada'
                    : 'Error al imprimir regla',
              ),
            ],
          ),
          backgroundColor: result.success ? _scheme.tertiary : _scheme.error,
        ),
      );
    }
  }

  void _showNoPrinterWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: _scheme.secondary,
          size: 48,
        ),
        title: const Text('Sin Impresora'),
        content: const Text(
          'No hay una impresora seleccionada.\n\n'
          'Por favor, seleccione una impresora de la lista antes de imprimir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.auto_fix_high, color: _scheme.primary, size: 48),
        title: const Text('Restaurar Plantilla Profesional'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Desea restaurar la configuración a la plantilla profesional por defecto?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 16),
            Text('Se aplicará:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('✓ Fuente Arial Black (ejecutiva)'),
            Text('✓ Tamaño de papel: 80mm'),
            Text('✓ Logo activado'),
            Text('✓ Todas las secciones visibles'),
            Text('✓ Márgenes optimizados'),
            Text('✓ Diseño tipo factura profesional'),
            SizedBox(height: 16),
            Text(
              '⚠️ La impresora seleccionada NO se modificará.',
              style: TextStyle(color: _scheme.primary, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _scheme.primary),
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Restaurar Plantilla'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final resetSettings = await PrinterSettingsRepository.resetToProfessional();

      // Recargar CompanyInfo
      final companyInfo = await CompanyInfoRepository.getCurrentCompanyInfo();
      if (!mounted) return;

      _headerExtraCtrl.text = resetSettings.headerExtra ?? '';
      _footerCtrl.text = resetSettings.footerMessage;

      setState(() {
        _settings = resetSettings;
        _companyInfo = companyInfo;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.auto_fix_high, color: _scheme.onPrimary),
              SizedBox(width: 8),
              Text('Plantilla profesional aplicada'),
            ],
          ),
          backgroundColor: _scheme.primary,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      debugPrint('Error resetting printer settings: $e\\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo restaurar la plantilla: $e'),
            backgroundColor: _scheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateSetting(
    PrinterSettingsModel Function(PrinterSettingsModel) update,
  ) {
    setState(() => _settings = update(_settings));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: LayoutBuilder(
      builder: (context, constraints) {
        final padding = SettingsLayout.contentPadding(constraints);
        final sectionGap = SettingsLayout.sectionGap(constraints);
        final isNarrow = constraints.maxWidth < 980;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: SettingsLayout.maxWidth(constraints, max: 1400),
            child: Padding(
              padding: padding,
              child: Column(
                children: [
                  // Header
                  _buildHeader(),
                  SizedBox(height: sectionGap),

                  // Contenido principal
                  Expanded(
                    child: isNarrow
                        ? Column(
                            children: [
                              Expanded(child: _buildSettingsPanel()),
                              SizedBox(height: sectionGap),
                              Expanded(child: _buildPreviewPanel()),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Panel de configuraci??n (izquierda)
                              Expanded(flex: 3, child: _buildSettingsPanel()),
                              SizedBox(width: sectionGap),

                              // Panel de preview (derecha)
                              Expanded(flex: 2, child: _buildPreviewPanel()),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_scheme.primary, _scheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.print, size: 36, color: _scheme.onPrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plantilla Profesional de Ticket',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _scheme.onPrimary,
                  ),
                ),
                Text(
                  'Configure el diseño y contenido de sus recibos de venta',
                  style: TextStyle(color: _scheme.onPrimary.withOpacity(0.7), fontSize: 13),
                ),
              ],
            ),
          ),

          // Botones de acción
          OutlinedButton.icon(
            onPressed: _resetSettings,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text('Plantilla Profesional'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _scheme.onPrimary,
              side: BorderSide(color: _scheme.onPrimary),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(_saving ? 'Guardando...' : 'Guardar Configuración'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _scheme.primary,
              foregroundColor: _scheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Sección: Impresora
          _buildSection(
            icon: Icons.print,
            title: '🖨️ Impresora',
            children: [
              // Dropdown de impresoras
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Impresora Térmica',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.print_outlined),
                        filled: true,
                        fillColor: _scheme.surfaceVariant,
                      ),
                      initialValue:
                          _availablePrinters.any(
                            (p) => p.name == _settings.selectedPrinterName,
                          )
                          ? _settings.selectedPrinterName
                          : null,
                      hint: const Text('Seleccione una impresora'),
                      items: _availablePrinters
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.name,
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => _updateSetting(
                        (s) => s.copyWith(selectedPrinterName: value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _refreshPrinters,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Actualizar lista',
                    style: IconButton.styleFrom(
                      backgroundColor: _scheme.primaryContainer,
                    ),
                  ),
                ],
              ),

              // Estado de impresora
              if (_settings.selectedPrinterName != null &&
                  _settings.selectedPrinterName!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _scheme.tertiaryContainer),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: _scheme.tertiary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Impresora: ${_settings.selectedPrinterName}',
                          style: TextStyle(
                            color: _scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _scheme.secondaryContainer),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: _scheme.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No hay impresora seleccionada',
                          style: TextStyle(
                            color: _scheme.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Botón imprimir prueba
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _printing ? null : _printTest,
                  icon: _printing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.print),
                  label: Text(_printing ? 'Imprimiendo...' : 'Imprimir Prueba'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _scheme.primary,
                    foregroundColor: _scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Botón regla de ancho (verifica 48/42 chars reales)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _printing ? null : _printWidthRuler,
                  icon: const Icon(Icons.straighten),
                  label: const Text('Imprimir Regla (48/42)'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Tamaño y Márgenes
          _buildSection(
            icon: Icons.straighten,
            title: '📏 Tamaño y Márgenes',
            children: [
              // Tamaño de papel
              const Text(
                'Ancho del papel:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 58,
                    label: Text('58 mm'),
                    icon: Icon(Icons.receipt, size: 18),
                  ),
                  ButtonSegment(
                    value: 80,
                    label: Text('80 mm'),
                    icon: Icon(Icons.receipt_long, size: 18),
                  ),
                ],
                selected: {_settings.paperWidthMm},
                onSelectionChanged: (values) {
                  final width = values.first;
                  if (width == 58) {
                    _updateSetting(
                      (s) => s.copyWith(paperWidthMm: width, charsPerLine: 32),
                    );
                    return;
                  }

                  // 80mm: usar 48 por defecto (mm80 normal), con opción de bajar a 42.
                  final current = _settings.charsPerLine;
                  final chars = (current == 42) ? 42 : 48;
                  _updateSetting(
                    (s) => s.copyWith(paperWidthMm: width, charsPerLine: chars),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Caracteres por línea: ${_settings.charsPerLine}',
                style: TextStyle(color: _scheme.onSurfaceVariant, fontSize: 12),
              ),

              if (_settings.paperWidthMm == 80) ...[
                const SizedBox(height: 12),
                const Text(
                  'Ancho de texto (80mm):',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 42,
                      label: Text('42 (Seguro)'),
                      icon: Icon(Icons.shield, size: 18),
                    ),
                    ButtonSegment(
                      value: 48,
                      label: Text('48 (Máximo)'),
                      icon: Icon(Icons.width_full, size: 18),
                    ),
                  ],
                  selected: {_settings.charsPerLine == 48 ? 48 : 42},
                  onSelectionChanged: (values) {
                    final chars = values.first;
                    _updateSetting((s) => s.copyWith(charsPerLine: chars));
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Recomendado: 42 si el ticket sale “apretado” o se corta.',
                  style: TextStyle(color: _scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(),

              // Altura automática
              SwitchListTile(
                title: const Text('Altura automática'),
                subtitle: const Text('El ticket se ajusta al contenido'),
                value: _settings.autoHeight == 1,
                onChanged: (value) => _updateSetting(
                  (s) => s.copyWith(autoHeight: value ? 1 : 0),
                ),
                activeThumbColor: _scheme.primary,
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 8),

              // Márgenes
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Margen superior: ${_settings.topMargin}px',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Slider(
                          value: _settings.topMargin.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 6,
                          activeColor: _scheme.primary,
                          onChanged: (value) => _updateSetting(
                            (s) => s.copyWith(topMargin: value.toInt()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Margen inferior: ${_settings.bottomMargin}px',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Slider(
                          value: _settings.bottomMargin.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 6,
                          activeColor: _scheme.primary,
                          onChanged: (value) => _updateSetting(
                            (s) => s.copyWith(bottomMargin: value.toInt()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Margen izquierdo: ${_settings.leftMargin}px',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Slider(
                          value: _settings.leftMargin.toDouble(),
                          min: 0,
                          max: 20,
                          divisions: 4,
                          activeColor: _scheme.primary,
                          onChanged: (value) => _updateSetting(
                            (s) => s.copyWith(leftMargin: value.toInt()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Margen derecho: ${_settings.rightMargin}px',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Slider(
                          value: _settings.rightMargin.toDouble(),
                          min: 0,
                          max: 20,
                          divisions: 4,
                          activeColor: _scheme.primary,
                          onChanged: (value) => _updateSetting(
                            (s) => s.copyWith(rightMargin: value.toInt()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Logo y Marca
          _buildSection(
            icon: Icons.image,
            title: '🖼️ Logo y Marca',
            children: [
              SwitchListTile(
                title: const Text('Mostrar Logo'),
                subtitle: const Text(
                  'Muestra el logo del negocio en el encabezado',
                ),
                value: _settings.showLogo == 1,
                onChanged: (value) =>
                    _updateSetting((s) => s.copyWith(showLogo: value ? 1 : 0)),
                activeThumbColor: _scheme.primary,
                contentPadding: EdgeInsets.zero,
              ),

              if (_settings.showLogo == 1) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.photo_size_select_large,
                      size: 20,
                      color: _scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tamaño del logo: ${_settings.logoSize}px',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Slider(
                            value: _settings.logoSize.toDouble(),
                            min: 40,
                            max: 120,
                            divisions: 8,
                            activeColor: _scheme.primary,
                            onChanged: (value) => _updateSetting(
                              (s) => s.copyWith(logoSize: value.toInt()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(),

              SwitchListTile(
                title: const Text('Mostrar datos del negocio'),
                subtitle: const Text('RNC, dirección, teléfono en encabezado'),
                value: _settings.showBusinessData == 1,
                onChanged: (value) => _updateSetting(
                  (s) => s.copyWith(showBusinessData: value ? 1 : 0),
                ),
                activeThumbColor: _scheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Tipografía & Texto
          _buildSection(
            icon: Icons.text_fields,
            title: '🔠 Tipografía & Texto',
            children: [
              // Familia de fuente
              const Text(
                'Tipo de fuente:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.font_download),
                  filled: true,
                  fillColor: _scheme.surfaceVariant,
                ),
                initialValue: _settings.fontFamily,
                items: const [
                  DropdownMenuItem(
                    value: 'courier',
                    child: Text('Courier (Clásica)'),
                  ),
                  DropdownMenuItem(value: 'arial', child: Text('Arial')),
                  DropdownMenuItem(
                    value: 'arialBlack',
                    child: Text('Arial Black (Recomendada)'),
                  ),
                  DropdownMenuItem(value: 'roboto', child: Text('Roboto')),
                  DropdownMenuItem(
                    value: 'sansSerif',
                    child: Text('Sans Serif'),
                  ),
                ],
                onChanged: (value) =>
                    _updateSetting((s) => s.copyWith(fontFamily: value)),
              ),

              const SizedBox(height: 16),

              // Tamaño de fuente
              const Text(
                'Tamaño de fuente:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'small',
                    label: Text('Pequeña'),
                    icon: Icon(Icons.text_decrease, size: 18),
                  ),
                  ButtonSegment(
                    value: 'normal',
                    label: Text('Normal'),
                    icon: Icon(Icons.text_fields, size: 18),
                  ),
                  ButtonSegment(
                    value: 'large',
                    label: Text('Grande'),
                    icon: Icon(Icons.text_increase, size: 18),
                  ),
                ],
                selected: {_settings.fontSize},
                onSelectionChanged: (values) =>
                    _updateSetting((s) => s.copyWith(fontSize: values.first)),
              ),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _scheme.secondaryContainer),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: _scheme.onSecondaryContainer),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Recomendación: use Courier para que las columnas (precio/total) queden perfectamente alineadas en la impresora.',
                        style: TextStyle(fontSize: 12.5, color: _scheme.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Alineación
          _buildSection(
            icon: Icons.format_align_center,
            title: '↔️ Alineación',
            children: [
              const Text(
                'Encabezado:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.title),
                  filled: true,
                  fillColor: _scheme.surfaceVariant,
                ),
                initialValue: _settings.headerAlignment,
                items: const [
                  DropdownMenuItem(value: 'left', child: Text('Izquierda')),
                  DropdownMenuItem(value: 'center', child: Text('Centro')),
                  DropdownMenuItem(value: 'right', child: Text('Derecha')),
                ],
                onChanged: (value) =>
                    _updateSetting((s) => s.copyWith(headerAlignment: value)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Detalles (cliente/datos):',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.subject),
                  filled: true,
                  fillColor: _scheme.surfaceVariant,
                ),
                initialValue: _settings.detailsAlignment,
                items: const [
                  DropdownMenuItem(value: 'left', child: Text('Izquierda')),
                  DropdownMenuItem(value: 'center', child: Text('Centro')),
                  DropdownMenuItem(value: 'right', child: Text('Derecha')),
                ],
                onChanged: (value) =>
                    _updateSetting((s) => s.copyWith(detailsAlignment: value)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Totales:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.calculate),
                  filled: true,
                  fillColor: _scheme.surfaceVariant,
                ),
                initialValue: _settings.totalsAlignment,
                items: const [
                  DropdownMenuItem(value: 'left', child: Text('Izquierda')),
                  DropdownMenuItem(value: 'center', child: Text('Centro')),
                  DropdownMenuItem(
                    value: 'right',
                    child: Text('Derecha (recomendado)'),
                  ),
                ],
                onChanged: (value) =>
                    _updateSetting((s) => s.copyWith(totalsAlignment: value)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Niveles de Espaciado (NUEVA)
          _buildSection(
            icon: Icons.format_line_spacing,
            title: '📐 Espaciado del Ticket',
            children: [
              // Info sobre los niveles
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _scheme.primaryContainer.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _scheme.primaryContainer),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: _scheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Ajuste el tamaño y espaciado del ticket con valores del 1 al 10.\nEstos valores afectan tanto la vista previa como la impresión real.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Nivel de tamaño de fuente (1-10)
              Row(
                children: [
                  Icon(Icons.format_size, size: 20, color: _scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tamaño de letra:',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_settings.fontSizeLevel}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _settings.fontSizeLevel.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          activeColor: _scheme.primary,
                          label: _settings.fontSizeLevel.toString(),
                          onChanged: (value) => _updateSetting(
                            (s) => s.copyWith(fontSizeLevel: value.toInt()),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Pequeño',
                              style: TextStyle(
                                fontSize: 11,
                                color: _scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Grande',
                              style: TextStyle(
                                fontSize: 11,
                                color: _scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Nivel de espaciado entre líneas (1-10)
              Row(
                children: [
                  Icon(
                    Icons.format_line_spacing,
                    size: 20,
                    color: _scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Espacio entre líneas:',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_settings.lineSpacingLevel}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _settings.lineSpacingLevel.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          activeColor: _scheme.primary,
                          label: _settings.lineSpacingLevel.toString(),
                          onChanged: (value) => _updateSetting(
                            (s) => s.copyWith(lineSpacingLevel: value.toInt()),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Compacto',
                              style: TextStyle(
                                fontSize: 11,
                                color: _scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Amplio',
                              style: TextStyle(
                                fontSize: 11,
                                color: _scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Nivel de espaciado entre secciones (1-10)
              Row(
                children: [
                  Icon(
                    Icons.view_agenda_outlined,
                    size: 20,
                    color: _scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Espacio entre secciones:',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_settings.sectionSpacingLevel}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _settings.sectionSpacingLevel.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          activeColor: _scheme.primary,
                          label: _settings.sectionSpacingLevel.toString(),
                          onChanged: (value) => _updateSetting(
                            (s) =>
                                s.copyWith(sectionSpacingLevel: value.toInt()),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Junto',
                              style: TextStyle(
                                fontSize: 11,
                                color: _scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Separado',
                              style: TextStyle(
                                fontSize: 11,
                                color: _scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Separadores decorativos por sección (líneas de "punticos")
              const Text(
                'Separadores decorativos (líneas por sección):',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.horizontal_rule),
                  filled: true,
                  fillColor: _scheme.surfaceVariant,
                ),
                initialValue: _settings.sectionSeparatorStyle,
                items: const [
                  DropdownMenuItem(
                    value: 'single',
                    child: Text('Simple (1 línea) - recomendado'),
                  ),
                  DropdownMenuItem(
                    value: 'double',
                    child: Text('Doble (2 líneas: arriba y abajo)'),
                  ),
                ],
                onChanged: (value) => _updateSetting(
                  (s) => s.copyWith(sectionSeparatorStyle: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Datos del Negocio (desde Configuración Empresa)
          _buildSection(
            icon: Icons.store,
            title: '🏪 Datos del Negocio',
            children: [
              // Aviso: datos centralizados
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _scheme.primaryContainer),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: _scheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Datos centralizados',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                              Text(
                            'Los datos del negocio se toman automáticamente de Configuración → Empresa',
                            style: TextStyle(
                              fontSize: 12,
                              color: _scheme.primary.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Preview de datos de empresa
              if (_companyInfo != null) ...[
                _buildInfoRow('Nombre:', _companyInfo!.name),
                if (_companyInfo!.rnc != null && _companyInfo!.rnc!.isNotEmpty)
                  _buildInfoRow('RNC:', _companyInfo!.rnc!),
                if (_companyInfo!.primaryPhone != null &&
                    _companyInfo!.primaryPhone!.isNotEmpty)
                  _buildInfoRow('Teléfono:', _companyInfo!.primaryPhone!),
                if (_companyInfo!.address != null &&
                    _companyInfo!.address!.isNotEmpty)
                  _buildInfoRow('Dirección:', _companyInfo!.address!),
                const SizedBox(height: 8),
              ],

              // Botón para ir a configuración de empresa
              OutlinedButton.icon(
                onPressed: () {
                  // Navegar a configuración de empresa
                  Navigator.pop(context);
                  // TODO: Navegar a la página de configuración de empresa
                },
                icon: const Icon(Icons.settings, size: 18),
                label: Text('Editar en Configuración Empresa'),
                style: OutlinedButton.styleFrom(foregroundColor: _scheme.primary),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Campos adicionales del ticket (no de empresa)
              TextField(
                controller: _headerExtraCtrl,
                decoration: InputDecoration(
                  labelText: 'Texto adicional (encabezado)',
                  hintText: 'Ej: Horario, redes sociales, etc.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.text_fields),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _footerCtrl,
                decoration: InputDecoration(
                  labelText: 'Mensaje final (pie de página)',
                  hintText: 'Ej: ¡Gracias por su preferencia!',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _warrantyPolicyCtrl,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: 'Política de garantía / cambios (opcional)',
                  hintText:
                      'Escribe aquí las líneas de tu política.\nSi lo dejas vacío, NO se imprimirá esta sección.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.policy_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Secciones del Ticket
          _buildSection(
            icon: Icons.view_list,
            title: '🧾 Secciones del Ticket',
            children: [
              _buildSwitch(
                'Mostrar Cliente',
                Icons.person_outline,
                _settings.showClient == 1,
                (v) => _updateSetting((s) => s.copyWith(showClient: v ? 1 : 0)),
              ),
              _buildSwitch(
                'Mostrar Cajero',
                Icons.badge_outlined,
                _settings.showCashier == 1,
                (v) =>
                    _updateSetting((s) => s.copyWith(showCashier: v ? 1 : 0)),
              ),
              _buildSwitch(
                'Mostrar Fecha y Hora',
                Icons.access_time,
                _settings.showDatetime == 1,
                (v) =>
                    _updateSetting((s) => s.copyWith(showDatetime: v ? 1 : 0)),
              ),
              _buildSwitch(
                'Mostrar Código de Venta',
                Icons.qr_code,
                _settings.showCode == 1,
                (v) => _updateSetting((s) => s.copyWith(showCode: v ? 1 : 0)),
              ),
              const Divider(),
              _buildSwitch(
                'Mostrar Subtotal/ITBIS/Total',
                Icons.calculate_outlined,
                _settings.showSubtotalItbisTotal == 1,
                (v) => _updateSetting(
                  (s) => s.copyWith(showSubtotalItbisTotal: v ? 1 : 0),
                ),
              ),
              _buildSwitch(
                'Mostrar ITBIS desglosado',
                Icons.percent,
                _settings.showItbis == 1,
                (v) => _updateSetting((s) => s.copyWith(showItbis: v ? 1 : 0)),
              ),
              _buildSwitch(
                'Mostrar Descuentos',
                Icons.discount_outlined,
                _settings.showDiscounts == 1,
                (v) =>
                    _updateSetting((s) => s.copyWith(showDiscounts: v ? 1 : 0)),
              ),
              const Divider(),
              _buildSwitch(
                'Mostrar NCF (Valor Fiscal)',
                Icons.receipt_outlined,
                _settings.showNcf == 1,
                (v) => _updateSetting((s) => s.copyWith(showNcf: v ? 1 : 0)),
              ),
              _buildSwitch(
                'Mostrar Método de Pago',
                Icons.payment,
                _settings.showPaymentMethod == 1,
                (v) => _updateSetting(
                  (s) => s.copyWith(showPaymentMethod: v ? 1 : 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sección: Preferencias Generales
          _buildSection(
            icon: Icons.settings,
            title: '📌 Preferencias Generales',
            children: [
              // Copias
              Row(
                children: [
                  Icon(Icons.copy_all, size: 20, color: _scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Número de copias:')),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('0')),
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                    ],
                    selected: {_settings.copies},
                    onSelectionChanged: (values) =>
                        _updateSetting((s) => s.copyWith(copies: values.first)),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Auto imprimir
              SwitchListTile(
                title: const Text('Imprimir automáticamente al cobrar'),
                subtitle: const Text(
                  'Se imprimirá el ticket cuando se finalice la venta',
                ),
                value: _settings.autoPrintOnPayment == 1,
                onChanged: (value) => _updateSetting(
                  (s) => s.copyWith(autoPrintOnPayment: value ? 1 : 0),
                ),
                activeThumbColor: _scheme.primary,
                contentPadding: EdgeInsets.zero,
              ),

              // Auto corte
              SwitchListTile(
                title: const Text('Corte automático'),
                subtitle: const Text(
                  'Agregar espacio para corte al final del ticket',
                ),
                value: _settings.autoCut == 1,
                onChanged: (value) =>
                    _updateSetting((s) => s.copyWith(autoCut: value ? 1 : 0)),
                activeThumbColor: _scheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Column(
      children: [
        // Header del preview
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _scheme.surfaceVariant,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              Icon(Icons.preview, color: _scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Vista Previa',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              Chip(
                label: Text('${_settings.paperWidthMm}mm'),
                backgroundColor: _scheme.primaryContainer,
                labelStyle: const TextStyle(fontSize: 12),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Preview del ticket
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _scheme.surfaceVariant,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                // FUENTE ÚNICA DE VERDAD: Usar SimplifiedTicketPreviewWidget
                // que usa exactamente las mismas líneas que la impresión térmica
                child: SimplifiedTicketPreviewWidget(
                  settings: _settings.copyWith(
                    headerExtra: _headerExtraCtrl.text,
                    footerMessage: _footerCtrl.text.isNotEmpty
                        ? _footerCtrl.text
                        : 'Gracias por su compra',
                    warrantyPolicy: _warrantyPolicyCtrl.text,
                  ),
                  company: _companyInfo,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _scheme.surfaceVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _scheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Switch(value: value, onChanged: onChanged, activeThumbColor: _scheme.primary),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: _scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
