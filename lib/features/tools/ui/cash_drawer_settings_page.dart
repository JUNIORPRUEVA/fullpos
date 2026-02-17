import 'package:flutter/material.dart';

import '../../../core/printing/unified_ticket_printer.dart';
import '../../settings/data/printer_settings_model.dart';
import '../../settings/data/printer_settings_repository.dart';

class CashDrawerSettingsPage extends StatefulWidget {
  const CashDrawerSettingsPage({super.key});

  @override
  State<CashDrawerSettingsPage> createState() => _CashDrawerSettingsPageState();
}

class _CashDrawerSettingsPageState extends State<CashDrawerSettingsPage> {
  PrinterSettingsModel? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await PrinterSettingsRepository.getOrCreate();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _setAutoOpen(bool enabled) async {
    final current = _settings;
    if (current == null) return;

    setState(() => _saving = true);
    final updated = current.copyWith(
      autoOpenDrawerOnChargeWithoutTicket: enabled ? 1 : 0,
    );

    await PrinterSettingsRepository.updateSettings(updated);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _saving = false;
    });
  }

  Future<void> _testOpenDrawer() async {
    setState(() => _testing = true);
    final result = await UnifiedTicketPrinter.openCashDrawerPulse();
    if (!mounted) return;
    setState(() => _testing = false);

    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? scheme.tertiary : scheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja registradora'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: const Text(
                      'Configura la apertura automática de la caja de dinero al cobrar cuando no se imprime el ticket.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: (_settings?.autoOpenDrawerOnChargeWithoutTicket ?? 0) ==
                        1,
                    onChanged: _saving ? null : _setAutoOpen,
                    title: const Text('Abrir caja al cobrar sin imprimir ticket'),
                    subtitle: const Text(
                      'Si está activa, al finalizar una venta sin imprimir se enviará pulso de apertura a la impresora configurada.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Impresora actual'),
                    subtitle: Text(
                      (_settings?.selectedPrinterName ?? '').trim().isEmpty
                          ? 'No hay impresora configurada'
                          : _settings!.selectedPrinterName!,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testOpenDrawer,
                    icon: const Icon(Icons.point_of_sale),
                    label: Text(
                      _testing ? 'Enviando pulso...' : 'Probar apertura de caja',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
