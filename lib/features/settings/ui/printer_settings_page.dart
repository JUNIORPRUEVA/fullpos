import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/printing/models/models.dart';
import '../data/printer_settings_model.dart';
import '../data/printer_settings_repository.dart';
import 'settings_layout.dart';

/// Página de configuración de impresora y ticket
/// con opciones esenciales en una vista compacta y profesional.
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

  static const int _logoSizeSmall = 40;
  static const int _logoSizeNormal = 70;
  static const int _logoSizeLarge = 100;

  ColorScheme get _scheme => Theme.of(context).colorScheme;

  // Controllers para TextFields (solo footer, resto viene de CompanyInfo)
  late TextEditingController _footerCtrl;
  late TextEditingController _headerExtraCtrl;
  late TextEditingController _warrantyPolicyCtrl;

  _TicketFormat get _ticketFormat {
    final s = _settings;
    final detailedSignals = <bool>[
      s.showClient == 1,
      s.showCashier == 1,
      s.showSubtotalItbisTotal == 1,
      s.showElectronicInvoiceReference == 1,
    ];
    final detailedCount = detailedSignals.where((v) => v).length;
    return detailedCount >= 3 ? _TicketFormat.detailed : _TicketFormat.compact;
  }

  int get _logoSizeBucket {
    final size = _settings.logoSize;
    if (size <= 55) return _logoSizeSmall;
    if (size <= 85) return _logoSizeNormal;
    return _logoSizeLarge;
  }

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

    final updatedSettings = _buildSettingsForPersist();

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

    // Asegurar que la impresión use los cambios del usuario.
    // UnifiedTicketPrinter lee desde DB, por lo que si el usuario no presiona
    // “Guardar”, el test podría salir con configuración anterior.
    try {
      final updatedSettings = _buildSettingsForPersist();
      await PrinterSettingsRepository.updateSettings(updatedSettings);
      if (mounted) {
        setState(() => _settings = updatedSettings);
      }
    } catch (e, st) {
      debugPrint(
        'Error persisting printer settings before test print: $e\n$st',
      );
    }

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

  void _showNoPrinterWarning() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccione una impresora'),
        content: const Text(
          'Seleccione una impresora térmica para poder imprimir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _applyTicketFormat(_TicketFormat format) {
    _updateSetting((s) {
      if (format == _TicketFormat.compact) {
        return s.copyWith(
          showClient: 0,
          showCashier: 0,
          showSubtotalItbisTotal: 0,
          showDiscounts: 0,
          showElectronicInvoiceReference: 0,
          showPaymentMethod: 1,
          showDatetime: 1,
          showCode: 1,
          showItbis: 1,
        );
      }

      return s.copyWith(
        showClient: 1,
        showCashier: 1,
        showSubtotalItbisTotal: 1,
        showDiscounts: 1,
        showElectronicInvoiceReference: 1,
        showPaymentMethod: 1,
        showDatetime: 1,
        showCode: 1,
        showItbis: 1,
      );
    });
  }

  void _updateSetting(
    PrinterSettingsModel Function(PrinterSettingsModel) update,
  ) {
    setState(() => _settings = update(_settings));
  }

  PrinterSettingsModel _buildSettingsForPersist() {
    return _settings.copyWith(
      headerExtra: _headerExtraCtrl.text.trim(),
      footerMessage: _footerCtrl.text.trim(),
      warrantyPolicy: _warrantyPolicyCtrl.text.trim(),
      // Guardar datos de empresa desde CompanyInfo (sin duplicar)
      headerBusinessName: _companyInfo?.name ?? 'FULLPOS',
      headerRnc: _companyInfo?.rnc,
      headerAddress: _companyInfo?.address,
      headerPhone: _companyInfo?.primaryPhone,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Theme(
        data: SettingsLayout.brandedTheme(context),
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Impresora y ticket'),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              max: 1360,
              child: _buildSettingsPanel(constraints),
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: _scheme.surface.withOpacity(0.98),
              border: Border(
                top: BorderSide(
                  color: _scheme.outlineVariant.withOpacity(0.45),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _saveSettings,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
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

  Widget _buildSettingsPanel(BoxConstraints constraints) {
    final gap = SettingsLayout.itemGap(constraints);
    final isDesktop = constraints.maxWidth >= 1120;
    final isTablet = constraints.maxWidth >= 760;
    final sectionWidth = isDesktop
        ? ((constraints.maxWidth - (gap * 2)) / 3)
        : isTablet
        ? ((constraints.maxWidth - gap) / 2)
        : constraints.maxWidth;

    final sections = <Widget>[
      _buildCompactSection(
        width: isDesktop ? (sectionWidth * 2) + gap : sectionWidth,
        child: _buildPrintSetupSection(),
      ),
      _buildCompactSection(width: sectionWidth, child: _buildBrandSection()),
      _buildCompactSection(width: sectionWidth, child: _buildTextSizeSection()),
      _buildCompactSection(width: sectionWidth, child: _buildFormatSection()),
      _buildCompactSection(
        width: isDesktop ? constraints.maxWidth : sectionWidth,
        child: _buildMessagesSection(),
      ),
    ];

    final content = Wrap(
      spacing: gap,
      runSpacing: gap,
      children: sections,
    );

    if (isTablet || isDesktop) {
      return Align(alignment: Alignment.topCenter, child: content);
    }

    return SingleChildScrollView(child: content);
  }

  Widget _buildPrintSetupSection() {
    return _buildSection(
      icon: Icons.print,
      title: 'Impresora',
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Seleccionar impresora',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.print_outlined),
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
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    _updateSetting((s) => s.copyWith(selectedPrinterName: value)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _refreshPrinters,
              icon: const Icon(Icons.refresh),
              tooltip: 'Buscar impresoras',
              style: IconButton.styleFrom(
                backgroundColor: _scheme.primaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, inner) {
            final stacked = inner.maxWidth < 720;
            final paperSelector = SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 58,
                  label: Text('58 mm'),
                  icon: Icon(Icons.receipt, size: 16),
                ),
                ButtonSegment(
                  value: 80,
                  label: Text('80 mm'),
                  icon: Icon(Icons.receipt_long, size: 16),
                ),
              ],
              selected: {_settings.paperWidthMm},
              onSelectionChanged: (values) {
                final width = values.first;
                final current = _settings.charsPerLine;
                final chars = width == 58 ? 32 : (current == 48 ? 48 : 42);
                _updateSetting(
                  (s) => s.copyWith(paperWidthMm: width, charsPerLine: chars),
                );
              },
            );

            final testButton = ElevatedButton.icon(
              onPressed: _printing ? null : _printTest,
              icon: _printing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.print, size: 18),
              label: Text(_printing ? 'Imprimiendo...' : 'Probar impresión'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _scheme.primary,
                foregroundColor: _scheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  paperSelector,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: testButton),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: paperSelector),
                const SizedBox(width: 12),
                testButton,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildBrandSection() {
    return _buildSection(
      icon: Icons.image,
      title: 'Logo y negocio',
      children: [
        SwitchListTile(
          title: const Text('Mostrar logo'),
          value: _settings.showLogo == 1,
          onChanged: (value) =>
              _updateSetting((s) => s.copyWith(showLogo: value ? 1 : 0)),
          activeThumbColor: _scheme.primary,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        if (_settings.showLogo == 1) ...[
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: _logoSizeSmall,
                label: Text('Pequeño'),
                icon: Icon(Icons.photo_size_select_small, size: 18),
              ),
              ButtonSegment(
                value: _logoSizeNormal,
                label: Text('Normal'),
                icon: Icon(Icons.photo_size_select_large, size: 18),
              ),
              ButtonSegment(
                value: _logoSizeLarge,
                label: Text('Grande'),
                icon: Icon(Icons.image_outlined, size: 18),
              ),
            ],
            selected: {_logoSizeBucket},
            onSelectionChanged: (values) =>
                _updateSetting((s) => s.copyWith(logoSize: values.first)),
          ),
          const SizedBox(height: 8),
        ],
        const Divider(),
        SwitchListTile(
          title: const Text('Mostrar datos del negocio'),
          value: _settings.showBusinessData == 1,
          onChanged: (value) => _updateSetting(
            (s) => s.copyWith(showBusinessData: value ? 1 : 0),
          ),
          activeThumbColor: _scheme.primary,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildTextSizeSection() {
    return _buildSection(
      icon: Icons.text_fields,
      title: 'Tamaño del texto',
      children: [
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
      ],
    );
  }

  Widget _buildFormatSection() {
    return _buildSection(
      icon: Icons.receipt_long,
      title: 'Formato del ticket',
      children: [
        SegmentedButton<_TicketFormat>(
          segments: const [
            ButtonSegment(
              value: _TicketFormat.compact,
              label: Text('Compacto'),
              icon: Icon(Icons.view_headline, size: 18),
            ),
            ButtonSegment(
              value: _TicketFormat.detailed,
              label: Text('Detallado'),
              icon: Icon(Icons.view_list, size: 18),
            ),
          ],
          selected: {_ticketFormat},
          onSelectionChanged: (values) => _applyTicketFormat(values.first),
        ),
      ],
    );
  }

  Widget _buildMessagesSection() {
    return _buildSection(
      icon: Icons.policy_outlined,
      title: 'Mensaje y garantía',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 760;
            if (stack) {
              return Column(
                children: [
                  TextField(
                    controller: _footerCtrl,
                    decoration: InputDecoration(
                      labelText: 'Mensaje final',
                      hintText: 'Ej: Gracias por su preferencia',
                      prefixIcon: const Icon(Icons.message_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _buildWarrantyField(),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _footerCtrl,
                    decoration: InputDecoration(
                      labelText: 'Mensaje final',
                      hintText: 'Ej: Gracias por su preferencia',
                      prefixIcon: const Icon(Icons.message_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildWarrantyField()),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildWarrantyField() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _scheme.surface.withOpacity(0.76),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.policy_outlined, size: 16, color: _scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Política de garantía',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Se imprimirá organizada al final de la factura.',
            style: TextStyle(fontSize: 11.5, color: _scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _warrantyPolicyCtrl,
            minLines: 4,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Texto de garantía',
              hintText: 'Ej:\nCambios solo con factura\nNo aplica en artículos en oferta',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSection({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _scheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

}

enum _TicketFormat { compact, detailed }
