import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../license/data/license_models.dart';
import '../../license/services/license_file_storage.dart';
import '../../license/services/license_storage.dart';
import '../../registration/services/business_identity_storage.dart';
import '../../registration/services/business_registration_service.dart';
import '../../registration/services/pending_registration_queue.dart';
import 'settings_layout.dart';

class SystemLicenseSummaryPage extends StatefulWidget {
  const SystemLicenseSummaryPage({super.key});

  @override
  State<SystemLicenseSummaryPage> createState() =>
      _SystemLicenseSummaryPageState();
}

class _SystemLicenseSummaryPageState extends State<SystemLicenseSummaryPage> {
  final LicenseStorage _licenseStorage = LicenseStorage();
  final LicenseFileStorage _licenseFileStorage = LicenseFileStorage();
  final BusinessIdentityStorage _identityStorage = BusinessIdentityStorage();
  final BusinessRegistrationService _registrationService =
      BusinessRegistrationService();

  bool _isLoading = true;
  LicenseInfo? _info;
  String? _source;
  String? _licenseFilePath;
  String? _businessId;

  @override
  void initState() {
    super.initState();
    _loadLicenseInfo();
  }

  Future<void> _loadLicenseInfo() async {
    try {
      final info = await _licenseStorage.getLastInfo();
      final source = await _licenseStorage.getLastInfoSource();
      final file = await _licenseFileStorage.file();
      final businessId = await _identityStorage.getBusinessId();

      if (!mounted) return;
      setState(() {
        _info = info;
        _source = source;
        _licenseFilePath = file.path;
        final normalized = (businessId ?? '').trim();
        _businessId = normalized.isEmpty ? null : normalized;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _debugResetLicense() async {
    if (!kDebugMode) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset licencia (debug)'),
        content: const Text(
          'Esto borrara la licencia y el estado de prueba local en esta PC. Solo disponible en debug.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resetear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _licenseFileStorage.delete();
    } catch (_) {}
    try {
      await _licenseStorage.clearAll();
    } catch (_) {}
    try {
      await BusinessIdentityStorage().clearAll();
    } catch (_) {}
    try {
      await PendingRegistrationQueue().clear();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _info = null;
      _source = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Licencia reseteada (debug).')),
    );
  }

  Future<void> _debugResendRegistrationToCloud() async {
    if (!kDebugMode) return;

    final identity = await _identityStorage.getIdentity();
    if (identity == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay identidad local para reenviar a nube.'),
        ),
      );
      return;
    }

    const appVersion = String.fromEnvironment(
      'FULLPOS_APP_VERSION',
      defaultValue: '1.0.0+1',
    );

    final payload = await _registrationService.buildPayload(
      businessName: identity.businessName,
      role: identity.role,
      ownerName: identity.ownerName,
      phone: identity.phone,
      email: identity.email,
      trialStart: identity.trialStart,
      appVersion: appVersion,
    );

    await _registrationService.registerNowOrQueue(payload);
    await _registrationService.retryPendingOnce();

    final pending = await PendingRegistrationQueue().load();
    if (!mounted) return;
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro reenviado a nube (debug).')),
      );
    } else {
      final lastError = (pending.last.lastError ?? '').trim();
      final msg = lastError.isEmpty
          ? 'No se pudo enviar ahora. Quedo en cola para reintento (debug).'
          : 'No se pudo enviar ahora. Motivo: $lastError';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'No disponible';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  String _maskLicenseKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'No disponible';
    if (trimmed.length <= 8) return '****';
    return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
  }

  String _humanizeDays(int totalDays) {
    if (totalDays <= 0) return '0 dias';

    final years = totalDays ~/ 365;
    final remainingAfterYears = totalDays % 365;
    final months = remainingAfterYears ~/ 30;
    final days = remainingAfterYears % 30;

    final parts = <String>[];
    if (years > 0) {
      parts.add('$years ${years == 1 ? 'ano' : 'anos'}');
    }
    if (months > 0) {
      parts.add('$months ${months == 1 ? 'mes' : 'meses'}');
    }
    if (days > 0 && years == 0) {
      parts.add('$days ${days == 1 ? 'dia' : 'dias'}');
    }

    if (parts.isEmpty) {
      return '$totalDays ${totalDays == 1 ? 'dia' : 'dias'}';
    }
    return parts.join(' ');
  }

  String _remainingTimeText(LicenseInfo? info) {
    if (info == null) return 'No disponible';
    final end = info.fechaFin;
    if (end == null) return 'Sin fecha de vencimiento';

    final now = DateTime.now();
    final daysDiff = end.difference(now).inDays;

    if (daysDiff < 0) return 'Vencida';
    if (daysDiff == 0) return 'Vence hoy';
    return _humanizeDays(daysDiff);
  }

  String _statusText(LicenseInfo? info) {
    if (info == null) return 'Sin licencia registrada';
    if (info.isExpired) return 'Vencida';
    if (info.isBlocked) return 'Bloqueada';
    if (info.isActive) return 'Activa';
    return 'Pendiente';
  }

  String _sourceText(String? source) {
    switch ((source ?? '').trim().toLowerCase()) {
      case 'cloud':
        return 'Servidor';
      case 'offline':
        return 'Archivo local';
      default:
        return 'No disponible';
    }
  }

  String _devicesText(LicenseInfo? info) {
    if (info == null) return 'No disponible';
    final usados = info.usados;
    final max = info.maxDispositivos;

    if (usados == null && max == null) return 'No reportado por servidor';
    if (usados == null && max != null) return 'No reportado de $max';
    if (usados != null && max == null) return '$usados en uso';
    return '$usados de $max';
  }

  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('Licencia')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        SettingsLayout.sectionHeading(
                          context,
                          title: 'Resumen de licencia',
                          subtitle:
                              'Consulta el estado actual, origen, vigencia y datos operativos de la licencia.',
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceVariant
                                .withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: const Text(
                            'Esta informacion es solo para consulta. No se puede editar ni eliminar desde aqui.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _infoRow(label: 'Estado', value: _statusText(_info)),
                        _infoRow(
                          label: 'Business ID',
                          value: _businessId ?? 'No disponible',
                        ),
                        _infoRow(
                          label: 'Tiempo restante',
                          value: _remainingTimeText(_info),
                        ),
                        _infoRow(
                          label: 'Tipo de licencia',
                          value: (_info?.tipo?.trim().isNotEmpty ?? false)
                              ? _info!.tipo!.trim().toUpperCase()
                              : 'No disponible',
                        ),
                        _infoRow(
                          label: 'Codigo',
                          value: (_info?.code?.trim().isNotEmpty ?? false)
                              ? _info!.code!.trim()
                              : 'No disponible',
                        ),
                        _infoRow(
                          label: 'Clave',
                          value: _maskLicenseKey(_info?.licenseKey ?? ''),
                        ),
                        _infoRow(label: 'Inicio', value: _formatDate(_info?.fechaInicio)),
                        _infoRow(label: 'Vence', value: _formatDate(_info?.fechaFin)),
                        _infoRow(label: 'Dispositivos', value: _devicesText(_info)),
                        _infoRow(label: 'Origen', value: _sourceText(_source)),
                        _infoRow(
                          label: 'Ubicacion archivo',
                          value: _licenseFilePath ?? 'No disponible',
                        ),
                        _infoRow(
                          label: 'Ultima revision',
                          value: _formatDate(_info?.lastCheckedAt),
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _debugResendRegistrationToCloud,
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('Reenviar registro nube (debug)'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _debugResetLicense,
                                icon: const Icon(Icons.restart_alt),
                                label: const Text('Reset licencia (debug)'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}