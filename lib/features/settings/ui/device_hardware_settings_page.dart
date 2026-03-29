import 'package:flutter/material.dart';

import '../../../core/security/security_config.dart';
import '../../../core/session/session_manager.dart';
import '../../tools/ui/cash_drawer_settings_page.dart';
import '../../tools/ui/scanner_settings_page.dart';
import '../data/printer_settings_repository.dart';
import 'printer_settings_page.dart';
import 'settings_layout.dart';

class DeviceHardwareSettingsPage extends StatefulWidget {
  const DeviceHardwareSettingsPage({super.key});

  @override
  State<DeviceHardwareSettingsPage> createState() =>
      _DeviceHardwareSettingsPageState();
}

class _DeviceHardwareSettingsPageState extends State<DeviceHardwareSettingsPage> {
  _DeviceTerminalOverview? _overview;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview() async {
    final companyId = await SessionManager.companyId() ?? 1;
    final terminalId =
        await SessionManager.terminalId() ??
        await SessionManager.ensureTerminalId();
    final printerSettings = await PrinterSettingsRepository.getOrCreate();
    final scannerConfig = await SecurityConfigRepository.load(
      companyId: companyId,
      terminalId: terminalId,
    );

    if (!mounted) return;
    setState(() {
      _overview = _DeviceTerminalOverview(
        terminalId: terminalId,
        printerName: (printerSettings.selectedPrinterName ?? '').trim(),
        autoPrintEnabled: printerSettings.autoPrintOnPayment == 1,
        autoDrawerEnabled:
            printerSettings.autoOpenDrawerOnChargeWithoutTicket == 1,
        scannerEnabled: scannerConfig.scannerEnabled,
        scannerPrefix: (scannerConfig.scannerPrefix ?? '').trim(),
        scannerSuffix: scannerConfig.scannerSuffix,
        scannerTimeoutMs: scannerConfig.scannerTimeoutMs,
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hardware y terminal'),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final spacing = SettingsLayout.sectionGap(constraints);
            final width = constraints.maxWidth;
            final columns = width >= 980 ? 2 : 1;
            final itemWidth = columns == 1
                ? width
                : (width - spacing) / 2;

            return SettingsLayout.pageFrame(
              constraints,
              max: 1180,
              child: _loading || overview == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estado del terminal',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Esta vista resume el equipo actual sin duplicar configuraciones. Cada ajuste se edita solo en su pantalla dueña.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            SizedBox(
                              width: itemWidth,
                              child: _HardwareStatusCard(
                                icon: Icons.computer_outlined,
                                title: 'Terminal activa',
                                lines: [
                                  'Identificador: ${overview.terminalId}',
                                ],
                                actionLabel: null,
                                onTap: null,
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _HardwareStatusCard(
                                icon: Icons.print_outlined,
                                title: 'Impresora',
                                lines: [
                                  overview.printerName.isEmpty
                                      ? 'Sin impresora seleccionada'
                                      : 'Impresora: ${overview.printerName}',
                                  overview.autoPrintEnabled
                                      ? 'Autoimpresión: activa'
                                      : 'Autoimpresión: inactiva',
                                ],
                                actionLabel: 'Abrir impresora',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const PrinterSettingsPage(),
                                    ),
                                  ).then((_) => _loadOverview());
                                },
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _HardwareStatusCard(
                                icon: Icons.point_of_sale_outlined,
                                title: 'Caja registradora',
                                lines: [
                                  overview.autoDrawerEnabled
                                      ? 'Apertura sin ticket: activa'
                                      : 'Apertura sin ticket: inactiva',
                                ],
                                actionLabel: 'Abrir caja',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CashDrawerSettingsPage(),
                                    ),
                                  ).then((_) => _loadOverview());
                                },
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _HardwareStatusCard(
                                icon: Icons.qr_code_scanner_rounded,
                                title: 'Scanner',
                                lines: [
                                  overview.scannerEnabled
                                      ? 'Scanner: habilitado'
                                      : 'Scanner: deshabilitado',
                                  'Prefijo: ${overview.scannerPrefix.isEmpty ? 'sin prefijo' : overview.scannerPrefix}',
                                  'Sufijo: ${_escapeScannerToken(overview.scannerSuffix)}',
                                  'Timeout: ${overview.scannerTimeoutMs} ms',
                                ],
                                actionLabel: 'Abrir scanner',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ScannerSettingsPage(),
                                    ),
                                  ).then((_) => _loadOverview());
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

String _escapeScannerToken(String value) {
  if (value == '\n') return r'\n';
  if (value == '\t') return r'\t';
  if (value.isEmpty) return 'vacío';
  return value;
}

class _DeviceTerminalOverview {
  const _DeviceTerminalOverview({
    required this.terminalId,
    required this.printerName,
    required this.autoPrintEnabled,
    required this.autoDrawerEnabled,
    required this.scannerEnabled,
    required this.scannerPrefix,
    required this.scannerSuffix,
    required this.scannerTimeoutMs,
  });

  final String terminalId;
  final String printerName;
  final bool autoPrintEnabled;
  final bool autoDrawerEnabled;
  final bool scannerEnabled;
  final String scannerPrefix;
  final String scannerSuffix;
  final int scannerTimeoutMs;
}

class _HardwareStatusCard extends StatelessWidget {
  const _HardwareStatusCard({
    required this.icon,
    required this.title,
    required this.lines,
    required this.onTap,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final line in lines) ...[
              Text(
                line,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (actionLabel != null && onTap != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}