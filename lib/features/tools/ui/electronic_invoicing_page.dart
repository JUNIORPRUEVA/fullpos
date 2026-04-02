import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/services/empresa_service.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../settings/providers/business_settings_provider.dart';
import '../../facturacion_electronica/data/electronic_company_repository.dart';
import '../../facturacion_electronica/data/factura_electronica_repository.dart';
import '../../facturacion_electronica/data/models/electronic_company_model.dart';
import '../../facturacion_electronica/data/models/factura_electronica_model.dart';
import '../../settings/ui/business_sections_settings_page.dart';
import '../../settings/ui/settings_layout.dart';

class ElectronicInvoicingPage extends ConsumerStatefulWidget {
  const ElectronicInvoicingPage({super.key});

  @override
  ConsumerState<ElectronicInvoicingPage> createState() =>
      _ElectronicInvoicingPageState();
}

class _ElectronicInvoicingPageState
    extends ConsumerState<ElectronicInvoicingPage> {
  final _apiTokenController = TextEditingController();
  final _certificadoController = TextEditingController();

  ElectronicCompanyModel? _company;
  EmpresaConfig? _empresaConfig;
  Map<String, int> _summary = <String, int>{};
  List<FacturaElectronicaModel> _recentInvoices = <FacturaElectronicaModel>[];
  bool _loading = true;
  bool _saving = false;
  bool _savingVisibility = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _apiTokenController.dispose();
    _certificadoController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final results = await Future.wait<dynamic>([
      ElectronicCompanyRepository.getOrCreate(),
      FacturaElectronicaRepository.getStatusSummary(),
      FacturaElectronicaRepository.getRecent(limit: 18),
      EmpresaService.getEmpresaConfig(),
    ]);
    if (!mounted) return;

    final company = results[0] as ElectronicCompanyModel;
    final summary = results[1] as Map<String, int>;
    final invoices = results[2] as List<FacturaElectronicaModel>;
    final empresaConfig = results[3] as EmpresaConfig;

    _syncControllers(company);
    setState(() {
      _company = company;
      _empresaConfig = empresaConfig;
      _summary = summary;
      _recentInvoices = invoices;
      _loading = false;
    });
  }

  void _syncControllers(ElectronicCompanyModel company) {
    _apiTokenController.text = company.apiToken;
    _certificadoController.text = company.certificateName;
  }

  List<String> _missingCompanyFields() {
    final empresaConfig = _empresaConfig;
    if (empresaConfig == null) {
      return const <String>['Nombre empresa', 'RNC', 'Dirección'];
    }
    return empresaConfig.missingElectronicInvoicingFields();
  }

  Future<void> _openCompanySettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CompanyProfileSettingsPage(),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _save() async {
    final company = _company;
    if (company == null) return;

    setState(() => _saving = true);
    final saved = await ElectronicCompanyRepository.save(
      company.copyWith(
        apiToken: _apiTokenController.text.trim(),
        certificateName: _certificadoController.text.trim(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _company = saved;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuracion e-CF actualizada')),
    );
  }

  Future<void> _updateSalesVisibility(bool enabled) async {
    if (_savingVisibility) return;

    setState(() => _savingVisibility = true);
    try {
      await ref
          .read(businessSettingsProvider.notifier)
          .updateElectronicInvoicingEnabled(enabled);
    } finally {
      if (mounted) {
        setState(() => _savingVisibility = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessSettings = ref.watch(businessSettingsProvider);

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.pop();
                return;
              }
              context.go('/settings');
            },
          ),
          title: const Text('Facturacion electronica'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _loading || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              max: 1440,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          _buildHeader(
                            context,
                            salesVisibilityEnabled:
                                businessSettings.electronicInvoicingEnabled,
                          ),
                          const SizedBox(height: 16),
                          _buildSummary(),
                          const SizedBox(height: 16),
                          _buildSalesActivationSection(
                            context,
                            enabled:
                                businessSettings.electronicInvoicingEnabled,
                          ),
                          const SizedBox(height: 16),
                          _buildCompanyDataSection(context),
                          const SizedBox(height: 16),
                          _buildConfigForm(context),
                          const SizedBox(height: 16),
                          _buildRecentDocuments(context),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool salesVisibilityEnabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final statusTheme = Theme.of(context).extension<AppStatusTheme>();
    final resolvedStatus =
        statusTheme ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );
    final missing = _missingCompanyFields();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DGII lista para operar desde el POS',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Las ventas mantienen su flujo actual, pero la emision electronica ahora se registra como e-CF con estado dedicado.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusChip(
                label: salesVisibilityEnabled
                    ? 'Visible en ventas'
                    : 'Oculta en ventas',
                color: salesVisibilityEnabled
                    ? resolvedStatus.success
                    : resolvedStatus.warning,
              ),
              const SizedBox(height: 8),
              _StatusChip(
                label: missing.isEmpty
                    ? 'Configuracion completa'
                    : 'Faltan ${missing.length} campos',
                color: missing.isEmpty
                    ? resolvedStatus.info
                    : resolvedStatus.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalesActivationSection(
    BuildContext context, {
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Disponibilidad en ventas',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.28),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withOpacity(0.45),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Activar facturación electrónica',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Muestra las opciones de comprobante electrónico en ventas',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch.adaptive(
                  value: enabled,
                  onChanged: _savingVisibility ? null : _updateSalesVisibility,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final scheme = Theme.of(context).colorScheme;
    final statusTheme = Theme.of(context).extension<AppStatusTheme>();
    final resolvedStatus =
        statusTheme ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          label: 'Locales',
          value: (_summary[FacturaElectronicaModel.statusLocal] ?? 0)
              .toString(),
          color: resolvedStatus.info,
        ),
        _MetricCard(
          label: 'Pendientes DGII',
          value: (_summary[FacturaElectronicaModel.statusPending] ?? 0)
              .toString(),
          color: scheme.primary,
        ),
        _MetricCard(
          label: 'Aceptadas',
          value: (_summary[FacturaElectronicaModel.statusAccepted] ?? 0)
              .toString(),
          color: resolvedStatus.success,
        ),
        _MetricCard(
          label: 'Configurar',
          value: (_summary[FacturaElectronicaModel.statusConfigPending] ?? 0)
              .toString(),
          color: resolvedStatus.warning,
        ),
      ],
    );
  }

  Widget _buildConfigForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final company = _company!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuración DGII',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Aquí solo se administran parámetros propios de facturación electrónica.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FieldBox(
                width: 220,
                child: _EnvironmentField(
                  value: company.environment,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(
                      () => _company = company.copyWith(environment: value),
                    );
                  },
                ),
              ),
              _FieldBox(
                width: 320,
                child: _LabeledField(
                  label: 'Token DGII',
                  controller: _apiTokenController,
                ),
              ),
              _FieldBox(
                width: 320,
                child: _LabeledField(
                  label: 'Certificado / alias',
                  controller: _certificadoController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Emitir e-CF automaticamente'),
            subtitle: const Text(
              'Al cobrar un documento electrónico se guarda XML, firma y estado DGII.',
            ),
            value: company.automaticEmission == 1,
            onChanged: (value) {
              setState(
                () => _company = company.copyWith(
                  automaticEmission: value ? 1 : 0,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyDataSection(BuildContext context) {
    final empresaConfig = _empresaConfig;
    final missing = _missingCompanyFields();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withOpacity(0.45),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Datos de la empresa',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (empresaConfig == null || missing.isNotEmpty)
            _MissingCompanyDataState(onOpenSettings: _openCompanySettings)
          else
            Column(
              children: [
                _ReadOnlyDataItem(
                  label: 'Empresa',
                  value: empresaConfig.nombreEmpresa,
                ),
                const SizedBox(height: 8),
                _ReadOnlyDataItem(
                  label: 'RNC',
                  value: (empresaConfig.rnc ?? '').trim(),
                ),
                const SizedBox(height: 8),
                _ReadOnlyDataItem(
                  label: 'Dirección',
                  value: empresaConfig.direccionCompleta,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRecentDocuments(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Documentos recientes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_recentInvoices.isEmpty)
            Text(
              'Todavia no hay facturas electronicas registradas.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            ..._recentInvoices.map(
              (invoice) => Container(
                height: 60,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.30),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        invoice.localCode,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        invoice.clienteNombre ?? 'Consumidor final',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    if ((invoice.ecf ?? '').trim().isNotEmpty)
                      SizedBox(
                        width: 170,
                        child: Text(
                          invoice.ecf!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(width: 10),
                    _StatusChip(
                      label: invoice.statusLabel,
                      color: _statusColor(invoice.estadoDgii),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 130,
                      child: Text(
                        dateFormat.format(
                          DateTime.fromMillisecondsSinceEpoch(
                            invoice.createdAtMs,
                          ),
                        ),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    final scheme = Theme.of(context).colorScheme;
    final statusTheme = Theme.of(context).extension<AppStatusTheme>();
    final resolvedStatus =
        statusTheme ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );
    switch (status) {
      case FacturaElectronicaModel.statusAccepted:
        return resolvedStatus.success;
      case FacturaElectronicaModel.statusPending:
        return scheme.primary;
      case FacturaElectronicaModel.statusRejected:
        return resolvedStatus.error;
      case FacturaElectronicaModel.statusConfigPending:
        return resolvedStatus.warning;
      default:
        return resolvedStatus.info;
    }
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  final double width;
  final Widget child;

  const _FieldBox({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _LabeledField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _ReadOnlyDataItem extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyDataItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MissingCompanyDataState extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _MissingCompanyDataState({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withOpacity(0.45),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Complete la información de empresa en configuración',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Ir a configuración'),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentField extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _EnvironmentField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(labelText: 'Ambiente DGII'),
      items: const [
        DropdownMenuItem(value: 'pruebas', child: Text('Pruebas')),
        DropdownMenuItem(value: 'produccion', child: Text('Produccion')),
      ],
      onChanged: onChanged,
    );
  }
}
