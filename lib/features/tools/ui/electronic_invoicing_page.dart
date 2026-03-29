import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../facturacion_electronica/data/electronic_company_repository.dart';
import '../../facturacion_electronica/data/factura_electronica_repository.dart';
import '../../facturacion_electronica/data/models/electronic_company_model.dart';
import '../../facturacion_electronica/data/models/factura_electronica_model.dart';
import '../../settings/ui/settings_layout.dart';

class ElectronicInvoicingPage extends StatefulWidget {
  const ElectronicInvoicingPage({super.key});

  @override
  State<ElectronicInvoicingPage> createState() =>
      _ElectronicInvoicingPageState();
}

class _ElectronicInvoicingPageState extends State<ElectronicInvoicingPage> {
  final _formKey = GlobalKey<FormState>();
  final _razonSocialController = TextEditingController();
  final _nombreComercialController = TextEditingController();
  final _rncController = TextEditingController();
  final _direccionController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _apiTokenController = TextEditingController();
  final _certificadoController = TextEditingController();

  ElectronicCompanyModel? _company;
  Map<String, int> _summary = <String, int>{};
  List<FacturaElectronicaModel> _recentInvoices =
      <FacturaElectronicaModel>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _razonSocialController.dispose();
    _nombreComercialController.dispose();
    _rncController.dispose();
    _direccionController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _apiTokenController.dispose();
    _certificadoController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final company = await ElectronicCompanyRepository.getOrCreate();
    final summary = await FacturaElectronicaRepository.getStatusSummary();
    final invoices = await FacturaElectronicaRepository.getRecent(limit: 18);
    if (!mounted) return;

    _syncControllers(company);
    setState(() {
      _company = company;
      _summary = summary;
      _recentInvoices = invoices;
      _loading = false;
    });
  }

  void _syncControllers(ElectronicCompanyModel company) {
    _razonSocialController.text = company.businessName;
    _nombreComercialController.text = company.tradeName;
    _rncController.text = company.rnc;
    _direccionController.text = company.emissionAddress;
    _telefonoController.text = company.phone;
    _emailController.text = company.email;
    _apiTokenController.text = company.apiToken;
    _certificadoController.text = company.certificateName;
  }

  Future<void> _save() async {
    final company = _company;
    if (company == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final saved = await ElectronicCompanyRepository.save(
      company.copyWith(
        businessName: _razonSocialController.text.trim(),
        tradeName: _nombreComercialController.text.trim(),
        rnc: _rncController.text.trim(),
        emissionAddress: _direccionController.text.trim(),
        phone: _telefonoController.text.trim(),
        email: _emailController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
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
                          _buildHeader(context),
                          const SizedBox(height: 16),
                          _buildSummary(),
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

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final company = _company!;
    final missing = company.missingRequiredFields();

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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
                label: company.isEnabled ? 'Emision activa' : 'Emision pausada',
                color: company.isEnabled ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 8),
              _StatusChip(
                label: missing.isEmpty
                    ? 'Configuracion completa'
                    : 'Faltan ${missing.length} campos',
                color: missing.isEmpty ? Colors.blueGrey : Colors.redAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          label: 'Locales',
          value: (_summary[FacturaElectronicaModel.statusLocal] ?? 0)
              .toString(),
          color: Colors.blueGrey,
        ),
        _MetricCard(
          label: 'Pendientes DGII',
          value: (_summary[FacturaElectronicaModel.statusPending] ?? 0)
              .toString(),
          color: Colors.blue,
        ),
        _MetricCard(
          label: 'Aceptadas',
          value: (_summary[FacturaElectronicaModel.statusAccepted] ?? 0)
              .toString(),
          color: Colors.green,
        ),
        _MetricCard(
          label: 'Configurar',
          value: (_summary[FacturaElectronicaModel.statusConfigPending] ?? 0)
              .toString(),
          color: Colors.orange,
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Empresa emisora',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _FieldBox(
                  width: 360,
                  child: _LabeledField(
                    label: 'Razon social',
                    controller: _razonSocialController,
                    validator: _required,
                  ),
                ),
                _FieldBox(
                  width: 280,
                  child: _LabeledField(
                    label: 'Nombre comercial',
                    controller: _nombreComercialController,
                  ),
                ),
                _FieldBox(
                  width: 220,
                  child: _LabeledField(
                    label: 'RNC',
                    controller: _rncController,
                    validator: _required,
                  ),
                ),
                _FieldBox(
                  width: 420,
                  child: _LabeledField(
                    label: 'Direccion de emision',
                    controller: _direccionController,
                    validator: _required,
                  ),
                ),
                _FieldBox(
                  width: 220,
                  child: _LabeledField(
                    label: 'Telefono',
                    controller: _telefonoController,
                  ),
                ),
                _FieldBox(
                  width: 280,
                  child: _LabeledField(
                    label: 'Correo',
                    controller: _emailController,
                  ),
                ),
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
                'Al cobrar un documento electronico se guarda XML, firma y estado DGII.',
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

  String? _required(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Requerido';
    return null;
  }

  Color _statusColor(String status) {
    switch (status) {
      case FacturaElectronicaModel.statusAccepted:
        return Colors.green;
      case FacturaElectronicaModel.statusPending:
        return Colors.blue;
      case FacturaElectronicaModel.statusRejected:
        return Colors.redAccent;
      case FacturaElectronicaModel.statusConfigPending:
        return Colors.orange;
      default:
        return Colors.blueGrey;
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
  final String? Function(String?)? validator;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(labelText: label),
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