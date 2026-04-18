import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/services/empresa_service.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/window/window_service.dart';
import '../../facturacion_electronica/data/electronic_certificate_repository.dart';
import '../../facturacion_electronica/data/electronic_invoicing_config_repository.dart';
import '../../facturacion_electronica/data/electronic_sequence_repository.dart';
import '../../facturacion_electronica/data/factura_electronica_repository.dart';
import '../../facturacion_electronica/data/models/electronic_company_model.dart';
import '../../facturacion_electronica/data/models/electronic_invoicing_config_model.dart';
import '../../facturacion_electronica/data/models/electronic_sequence_model.dart';
import '../../facturacion_electronica/data/models/factura_electronica_model.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/providers/business_settings_provider.dart';
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
  final _certificateAliasController = TextEditingController();
  final _certificatePasswordController = TextEditingController();
  final Map<String, TextEditingController> _sequencePrefixControllers = {};
  final Map<String, TextEditingController> _sequenceStartControllers = {};
  final Map<String, TextEditingController> _sequenceNumberControllers = {};
  final Map<String, TextEditingController> _sequenceEndControllers = {};
  final ElectronicCertificateRepository _certificateRepository =
      ElectronicCertificateRepository();
    final ElectronicInvoicingConfigRepository _configRepository =
      ElectronicInvoicingConfigRepository();
  final ElectronicSequenceRepository _sequenceRepository =
      ElectronicSequenceRepository();

  ElectronicCompanyModel? _company;
  EmpresaConfig? _empresaConfig;
  List<FacturaElectronicaModel> _recentInvoices = <FacturaElectronicaModel>[];
  List<ElectronicSequenceModel> _sequences = <ElectronicSequenceModel>[];
  ElectronicInvoicingReadiness _readiness =
      ElectronicInvoicingReadiness.localFallback(
        missing: const <String>[],
        messages: const <String>[],
      );

  bool _loading = true;
  bool _saving = false;
  bool _savingVisibility = false;
  bool _savingAutomaticEmission = false;
  bool _autoConfiguring = false;
  bool _uploadingCertificate = false;
  bool _showCertificatePassword = false;

  String? _creatingSequenceCode;
  String? _selectedCertificatePath;
  String? _certificateNotice;
  bool _certificateNoticeIsError = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _apiTokenController.dispose();
    _certificateAliasController.dispose();
    _certificatePasswordController.dispose();
    for (final controller in _sequencePrefixControllers.values) {
      controller.dispose();
    }
    for (final controller in _sequenceStartControllers.values) {
      controller.dispose();
    }
    for (final controller in _sequenceNumberControllers.values) {
      controller.dispose();
    }
    for (final controller in _sequenceEndControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final resolved = await _configRepository.loadResolvedConfig();
    final invoices = await FacturaElectronicaRepository.getRecent(limit: 18);
    final empresaConfig = await EmpresaService.getEmpresaConfig();
    if (!mounted) return;

    _syncControllers(resolved.company);
    _syncSequenceControllers(resolved.sequences);
    setState(() {
      _company = resolved.company;
      _empresaConfig = empresaConfig;
      _recentInvoices = invoices;
      _sequences = resolved.sequences;
      _readiness = resolved.readiness;
      _loading = false;
    });
  }

  void _syncControllers(ElectronicCompanyModel company) {
    _apiTokenController.text = company.apiToken;
    _certificateAliasController.text = company.certificateName.isEmpty
        ? 'Certificado DGII'
        : company.certificateName;
  }

  void _syncSequenceControllers(List<ElectronicSequenceModel> sequences) {
    final seeded = <ElectronicSequenceModel>[
      ...sequences,
      if (!sequences.any((sequence) => sequence.documentTypeCode == '31'))
        ElectronicSequenceModel.defaults('31'),
      if (!sequences.any((sequence) => sequence.documentTypeCode == '32'))
        ElectronicSequenceModel.defaults('32'),
    ];

    for (final sequence in seeded) {
      final prefixController = _sequencePrefixControllers.putIfAbsent(
        sequence.documentTypeCode,
        TextEditingController.new,
      );
      final startController = _sequenceStartControllers.putIfAbsent(
        sequence.documentTypeCode,
        TextEditingController.new,
      );
      final numberController = _sequenceNumberControllers.putIfAbsent(
        sequence.documentTypeCode,
        TextEditingController.new,
      );
      final endController = _sequenceEndControllers.putIfAbsent(
        sequence.documentTypeCode,
        TextEditingController.new,
      );
      prefixController.text = sequence.prefix;
      startController.text = sequence.startNumber.toString();
      numberController.text = sequence.currentNumber.toString();
      endController.text = sequence.endNumber?.toString() ?? '';
    }
  }

  List<String> _missingCompanyFields() {
    final empresaConfig = _empresaConfig;
    if (empresaConfig == null) {
      return const <String>['Empresa', 'RNC', 'Dirección'];
    }
    return empresaConfig.missingElectronicInvoicingFields();
  }

  bool _sequenceReadyForEmission(ElectronicSequenceModel sequence) {
    return sequence.isConfigured &&
        !sequence.isExhausted &&
        !sequence.isInactive;
  }

  ElectronicSequenceModel _sequenceFor(String documentTypeCode) {
    for (final sequence in _sequences) {
      if (sequence.documentTypeCode == documentTypeCode) {
        return sequence;
      }
    }
    return ElectronicSequenceModel.defaults(documentTypeCode);
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
    try {
      await _persistConfiguredSequences();
      final resolved = await _configRepository.saveConfig(
        company: company.copyWith(apiToken: _apiTokenController.text.trim()),
        electronicInvoicingEnabled:
            ref.read(businessSettingsProvider).electronicInvoicingEnabled,
      );

      if (!mounted) return;
      _syncControllers(resolved.company);
      _syncSequenceControllers(resolved.sequences);
      setState(() {
        _company = resolved.company;
        _sequences = resolved.sequences;
        _readiness = resolved.readiness;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada y validada')),
      );
    } on ElectronicInvoicingConfigException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error, stackTrace) {
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/save',
      );
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _pickCertificateFile() async {
    try {
      final result = await WindowService.runWithSystemDialog(
        () => FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['p12'],
          allowMultiple: false,
        ),
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null || file.path!.trim().isEmpty) return;

      setState(() {
        _selectedCertificatePath = file.path;
        _certificateNotice = null;
        _certificateNoticeIsError = false;
      });
    } catch (error, stackTrace) {
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/certificate_pick',
      );
    }
  }

  Future<void> _uploadCertificate() async {
    final company = _company;
    final filePath = _selectedCertificatePath;
    final alias = _certificateAliasController.text.trim();
    final password = _certificatePasswordController.text.trim();

    if (company == null) return;
    if (filePath == null || filePath.isEmpty) {
      setState(() {
        _certificateNotice = 'Seleccione el archivo';
        _certificateNoticeIsError = true;
      });
      return;
    }
    if (alias.isEmpty) {
      setState(() {
        _certificateNotice = 'Escriba un nombre';
        _certificateNoticeIsError = true;
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _certificateNotice = 'Escriba la contraseña';
        _certificateNoticeIsError = true;
      });
      return;
    }

    setState(() {
      _uploadingCertificate = true;
      _certificateNotice = null;
      _certificateNoticeIsError = false;
    });

    try {
      final result = await _certificateRepository.uploadCertificate(
        filePath: filePath,
        alias: alias,
        password: password,
      );
      final refreshed = await _configRepository.loadResolvedConfig();
      if (!mounted) return;

      _certificatePasswordController.clear();
      setState(() {
        _company = refreshed.company;
        _sequences = refreshed.sequences;
        _readiness = refreshed.readiness;
        _selectedCertificatePath = null;
        _certificateNotice = result.isExpired
            ? 'Certificado vencido'
            : 'Certificado cargado';
        _certificateNoticeIsError = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isExpired ? 'Certificado vencido' : 'Certificado cargado',
          ),
        ),
      );
    } on ElectronicCertificateUploadException catch (error) {
      if (!mounted) return;
      setState(() {
        _certificateNotice = error.userMessage;
        _certificateNoticeIsError = true;
      });
    } catch (error, stackTrace) {
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/certificate_upload',
      );
      if (!mounted) return;
      setState(() {
        _certificateNotice = 'No se pudo cargar el certificado';
        _certificateNoticeIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _uploadingCertificate = false);
      }
    }
  }

  Future<void> _updateSalesVisibility(bool enabled) async {
    if (_savingVisibility) return;

    final previousValue = ref.read(businessSettingsProvider).electronicInvoicingEnabled;
    setState(() => _savingVisibility = true);
    try {
      await ref
          .read(businessSettingsProvider.notifier)
          .updateElectronicInvoicingEnabled(enabled);
      await _saveCurrentRemoteConfig();
    } on ElectronicInvoicingConfigException catch (error) {
      await ref
          .read(businessSettingsProvider.notifier)
          .updateElectronicInvoicingEnabled(previousValue);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error, stackTrace) {
      await ref
          .read(businessSettingsProvider.notifier)
          .updateElectronicInvoicingEnabled(previousValue);
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/toggle_visibility',
      );
    } finally {
      if (mounted) {
        setState(() => _savingVisibility = false);
      }
    }
  }

  Future<void> _updateAutomaticEmission(bool enabled) async {
    final company = _company;
    if (company == null || _savingAutomaticEmission) return;

    final previousCompany = company;
    setState(() => _savingAutomaticEmission = true);
    try {
      final updatedCompany = company.copyWith(automaticEmission: enabled ? 1 : 0);
      if (!mounted) return;
      setState(() => _company = updatedCompany);
      await _saveCurrentRemoteConfig();
    } on ElectronicInvoicingConfigException catch (error) {
      if (!mounted) return;
      setState(() => _company = previousCompany);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _company = previousCompany);
      }
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/toggle_auto_send',
      );
    } finally {
      if (mounted) {
        setState(() => _savingAutomaticEmission = false);
      }
    }
  }

  Future<void> _autoConfigure() async {
    final company = _company;
    if (company == null || _autoConfiguring) return;

    setState(() => _autoConfiguring = true);
    try {
      final savedCompany = company.copyWith(environment: 'pruebas');
      final sequence31 = ElectronicSequenceModel.defaults('31').copyWith(
        prefix: 'E31',
        startNumber: 1,
        currentNumber: 0,
        endNumber: null,
        status: '',
      );
      final sequence32 = ElectronicSequenceModel.defaults('32').copyWith(
        prefix: 'E32',
        startNumber: 1,
        currentNumber: 0,
        endNumber: null,
        status: '',
      );
      await _configRepository.cacheDraftConfig(savedCompany);
      await _configRepository.cacheDraftSequences([sequence31, sequence32]);
      final resolved = await _configRepository.saveConfig(
        company: savedCompany.copyWith(apiToken: _apiTokenController.text.trim()),
        electronicInvoicingEnabled:
            ref.read(businessSettingsProvider).electronicInvoicingEnabled,
      );
      if (!mounted) return;

      _syncControllers(savedCompany);
      _syncSequenceControllers([sequence31, sequence32]);
      setState(() {
        _company = savedCompany;
        _sequences = [sequence31, sequence32];
        _readiness = resolved.readiness;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Secuencias sugeridas creadas. Complete el límite autorizado para facturar.',
          ),
        ),
      );
    } on ElectronicSequenceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error, stackTrace) {
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/auto_configure',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo completar la configuración automática'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _autoConfiguring = false);
      }
    }
  }

  Future<void> _showRecentDocumentsModal() async {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('dd/MM/yyyy');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Documentos recientes',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DocumentTableHeader(colorScheme: scheme),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _recentInvoices.isEmpty
                        ? Center(
                            child: Text(
                              'No hay documentos recientes',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : Scrollbar(
                            child: ListView.separated(
                              itemCount: _recentInvoices.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final invoice = _recentInvoices[index];
                                return _DocumentTableRow(
                                  number: (invoice.ecf ?? invoice.localCode)
                                      .trim(),
                                  type: _documentTypeLabel(
                                    invoice.tipoDocumento,
                                  ),
                                  client:
                                      invoice.clienteNombre
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? invoice.clienteNombre!.trim()
                                      : 'Consumidor final',
                                  status: invoice.statusLabel,
                                  statusColor: _statusColor(invoice.estadoDgii),
                                  date: dateFormat.format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      invoice.createdAtMs,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitSequence(String documentTypeCode) async {
    final prefix =
        _sequencePrefixControllers[documentTypeCode]?.text.trim() ?? '';
    final startNumber = int.tryParse(
      _sequenceStartControllers[documentTypeCode]?.text.trim() ?? '',
    );
    final currentNumber = int.tryParse(
      _sequenceNumberControllers[documentTypeCode]?.text.trim() ?? '',
    );
    final endNumber = int.tryParse(
      _sequenceEndControllers[documentTypeCode]?.text.trim() ?? '',
    );

    if (prefix.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escriba el prefijo de la secuencia')),
      );
      return;
    }
    if (startNumber == null || startNumber <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escriba el número inicial autorizado')),
      );
      return;
    }
    if (currentNumber == null || currentNumber < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escriba una secuencia válida')),
      );
      return;
    }
    if (endNumber == null || endNumber <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escriba el límite autorizado por DGII')),
      );
      return;
    }
    if (startNumber > endNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El número inicial no puede ser mayor al límite'),
        ),
      );
      return;
    }
    if (currentNumber > endNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La secuencia actual no puede exceder el límite'),
        ),
      );
      return;
    }

    setState(() => _creatingSequenceCode = documentTypeCode);
    try {
      final saved = await _sequenceRepository.createSequence(
        documentTypeCode: documentTypeCode,
        prefix: prefix,
        startNumber: startNumber,
        currentNumber: currentNumber,
        endNumber: endNumber,
        status: currentNumber >= endNumber ? 'EXHAUSTED' : 'ACTIVE',
      );
      if (!mounted) return;
      _replaceSequence(saved);
      final refreshed = await _configRepository.loadResolvedConfig();
      if (!mounted) return;
      _syncSequenceControllers(refreshed.sequences);
      setState(() {
        _company = refreshed.company;
        _sequences = refreshed.sequences;
        _readiness = refreshed.readiness;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved.hasLowAvailability
                ? 'Secuencia activa. Quedan pocos comprobantes disponibles'
                : '${_sequenceTitle(documentTypeCode)} lista',
          ),
        ),
      );
    } on ElectronicSequenceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error, stackTrace) {
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/sequence_create',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear la secuencia')),
      );
    } finally {
      if (mounted) {
        setState(() => _creatingSequenceCode = null);
      }
    }
  }

  void _replaceSequence(ElectronicSequenceModel saved) {
    final updated = <ElectronicSequenceModel>[];
    bool replaced = false;
    for (final sequence in _sequences) {
      if (sequence.documentTypeCode == saved.documentTypeCode) {
        updated.add(saved);
        replaced = true;
      } else {
        updated.add(sequence);
      }
    }
    if (!replaced) {
      updated.add(saved);
    }
    updated.sort((a, b) => a.documentTypeCode.compareTo(b.documentTypeCode));
    setState(() => _sequences = updated);
  }

  String _documentTypeLabel(String type) {
    switch (type.trim().toLowerCase()) {
      case '31':
      case 'credito_fiscal':
        return 'Crédito Fiscal';
      case '32':
      case 'venta':
      case 'consumo':
        return 'Consumo';
      case '33':
        return 'Débito';
      case '34':
        return 'Nota de crédito';
      default:
        return type.trim().isEmpty ? 'Documento' : type.trim();
    }
  }

  String _sequenceTitle(String documentTypeCode) {
    switch (documentTypeCode) {
      case '31':
        return '31 - Crédito Fiscal';
      case '32':
        return '32 - Consumo';
      default:
        return '$documentTypeCode - Secuencia';
    }
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

  Color _sequenceStatusColor(
    BuildContext context,
    ElectronicSequenceModel model,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (!model.hasAuthorizedRange) {
      return scheme.outline;
    }
    switch (model.status.trim().toUpperCase()) {
      case 'ACTIVE':
        return scheme.primary;
      case 'PAUSED':
      case 'INACTIVE':
        return scheme.tertiary;
      case 'EXHAUSTED':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }

  String _sequenceHelperMessage(ElectronicSequenceModel sequence) {
    if (!sequence.hasAuthorizedRange) {
      return 'No listo para facturar. Configure el límite autorizado por DGII.';
    }
    if (sequence.isExhausted) {
      return 'Secuencia agotada';
    }
    if (sequence.isInactive) {
      return 'Secuencia inactiva';
    }
    if (sequence.hasLowAvailability) {
      return 'Quedan pocos comprobantes disponibles';
    }
    return 'Secuencia activa';
  }

  _SystemStatusData _systemStatus(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_readiness.status) {
      case 'READY':
        return _SystemStatusData(
          label: 'LISTO',
          color: scheme.primary,
          icon: Icons.check_circle_outline,
        );
      case 'PARTIAL':
        return _SystemStatusData(
          label: 'PARCIAL',
          color: scheme.tertiary,
          icon: Icons.warning_amber_outlined,
        );
      default:
        return _SystemStatusData(
          label: 'NO LISTO',
          color: scheme.error,
          icon: Icons.cancel_outlined,
        );
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
          title: const Text('Facturación Electrónica'),
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
              max: 1240,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(
                      context,
                      constraints,
                      businessSettings: businessSettings,
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    BoxConstraints constraints, {
    required BusinessSettings businessSettings,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildHeroSection(context, businessSettings: businessSettings),
        const SizedBox(height: 10),
        _buildCertificateSection(context),
        const SizedBox(height: 10),
        _buildSequencesSection(context),
        const SizedBox(height: 10),
        _buildConfigSection(context),
        const SizedBox(height: 10),
        _buildCompanySummaryCard(context),
      ],
    );
  }

  Widget _buildHeroSection(
    BuildContext context, {
    required BusinessSettings businessSettings,
  }) {
    final company = _company!;
    final status = _systemStatus(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Facturación Electrónica',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _StatusBanner(
            label: status.label,
            color: status.color,
            icon: status.icon,
          ),
          if (_readiness.messages.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _readiness.messages.first,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (_readiness.missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _readiness.missing
                  .map(
                    (item) => _InlineMetaPill(
                      label: 'Falta',
                      value: item,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.22),
              borderRadius: BorderRadius.circular(18),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 620) {
                  return Column(
                    children: [
                      _PrimarySwitchTile(
                        label: 'Facturación electrónica',
                        value: businessSettings.electronicInvoicingEnabled,
                        onChanged: _savingVisibility
                            ? null
                            : _updateSalesVisibility,
                      ),
                      const SizedBox(height: 10),
                      _PrimarySwitchTile(
                        label: 'Enviar automáticamente a DGII',
                        value: company.automaticEmission == 1,
                        onChanged: _savingAutomaticEmission
                            ? null
                            : _updateAutomaticEmission,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: _PrimarySwitchTile(
                        label: 'Facturación electrónica',
                        value: businessSettings.electronicInvoicingEnabled,
                        onChanged: _savingVisibility
                            ? null
                            : _updateSalesVisibility,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PrimarySwitchTile(
                        label: 'Enviar automáticamente a DGII',
                        value: company.automaticEmission == 1,
                        onChanged: _savingAutomaticEmission
                            ? null
                            : _updateAutomaticEmission,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 620;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _autoConfiguring ? null : _autoConfigure,
                      icon: _autoConfiguring
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('Configurar automáticamente'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Se crean las sugerencias E31 y E32 con inicio en 1. Debe completar el límite autorizado para producción.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _showRecentDocumentsModal,
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('Ver documentos recientes'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.icon(
                          onPressed: _autoConfiguring ? null : _autoConfigure,
                          icon: _autoConfiguring
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_fix_high_outlined),
                          label: const Text('Configurar automáticamente'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Se crean las sugerencias E31 y E32 con inicio en 1. Debe completar el límite autorizado para producción.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _showRecentDocumentsModal,
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('Ver documentos recientes'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySummaryCard(BuildContext context) {
    final empresaConfig = _empresaConfig;
    final missing = _missingCompanyFields();
    final hasMissing = empresaConfig == null || missing.isNotEmpty;

    return _SectionCard(
      title: 'Datos de la empresa',
      trailing: hasMissing
          ? TextButton(
              onPressed: _openCompanySettings,
              child: const Text('Completar'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSummaryRow(
            label: 'Empresa',
            value: hasMissing
                ? 'Sin completar'
                : empresaConfig.nombreEmpresa.trim(),
          ),
          const SizedBox(height: 10),
          _ProfileSummaryRow(
            label: 'RNC',
            value: hasMissing
                ? 'Sin completar'
                : (empresaConfig.rnc ?? '').trim(),
          ),
          const SizedBox(height: 10),
          _ProfileSummaryRow(
            label: 'Dirección',
            value: hasMissing
                ? 'Sin completar'
                : empresaConfig.direccionCompleta.trim(),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection(BuildContext context) {
    final company = _company!;

    return _SectionCard(
      title: 'Configuración DGII',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 540;
          if (stacked) {
            return Column(
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('electronic-invoicing-environment-field'),
                  value: company.environment,
                  decoration: const InputDecoration(labelText: 'Ambiente'),
                  items: const [
                    DropdownMenuItem(
                      value: 'produccion',
                      child: Text('Producción'),
                    ),
                    DropdownMenuItem(
                      value: 'pruebas',
                      child: Text('Certificación'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _company = company.copyWith(environment: value);
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _apiTokenController,
                  decoration: const InputDecoration(labelText: 'Token DGII'),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  key: const Key('electronic-invoicing-environment-field'),
                  value: company.environment,
                  decoration: const InputDecoration(labelText: 'Ambiente'),
                  items: const [
                    DropdownMenuItem(
                      value: 'produccion',
                      child: Text('Producción'),
                    ),
                    DropdownMenuItem(
                      value: 'pruebas',
                      child: Text('Certificación'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _company = company.copyWith(environment: value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: _apiTokenController,
                  decoration: const InputDecoration(labelText: 'Token DGII'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCertificateSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final company = _company!;
    final validTo = company.certificateValidToMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(company.certificateValidToMs!);
    final isUploadingNewCertificate = _selectedCertificatePath != null;

    return _SectionCard(
      title: 'Certificado digital',
      trailing: _StatusChip(
        label: company.certificateStatus.trim() == 'active'
            ? 'Vigente'
            : 'No cargado',
        color: company.certificateStatus.trim() == 'active'
            ? scheme.primary
            : scheme.outline,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (company.certificateName.trim().isNotEmpty)
            _InlineMetaPill(
              label: 'Alias',
              value: company.certificateName.trim(),
            ),
          if (validTo != null) ...[
            const SizedBox(height: 10),
            _InlineMetaPill(
              label: 'Vence',
              value: DateFormat('dd/MM/yyyy').format(validTo),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _uploadingCertificate ? null : _pickCertificateFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Subir / Reemplazar certificado'),
            ),
          ),
          if (isUploadingNewCertificate) ...[
            const SizedBox(height: 10),
            TextFormField(
              key: const Key('electronic-certificate-password-field'),
              controller: _certificatePasswordController,
              obscureText: !_showCertificatePassword,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  key: const Key('electronic-certificate-password-toggle'),
                  tooltip: _showCertificatePassword
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña',
                  onPressed: () {
                    setState(() {
                      _showCertificatePassword = !_showCertificatePassword;
                    });
                  },
                  icon: Icon(
                    _showCertificatePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _uploadingCertificate ? null : _uploadCertificate,
                icon: _uploadingCertificate
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Confirmar certificado'),
              ),
            ),
          ],
          if (_certificateNotice != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _certificateNotice!,
                style: TextStyle(
                  color: _certificateNoticeIsError
                      ? scheme.error
                      : scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSequencesSection(BuildContext context) {
    final sequence31 = _sequenceFor('31');
    final sequence32 = _sequenceFor('32');

    return _SectionCard(
      title: 'Secuencias de Comprobantes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cada empresa debe configurar su rango real autorizado por DGII. Sin límite autorizado no se puede facturar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 860;
              final first = _SequenceSetupCard(
                title: '31 - Crédito Fiscal',
                prefixController: _sequencePrefixControllers['31']!,
                startController: _sequenceStartControllers['31']!,
                numberController: _sequenceNumberControllers['31']!,
                endController: _sequenceEndControllers['31']!,
                sequence: sequence31,
                busy: _creatingSequenceCode == '31',
                color: _sequenceStatusColor(context, sequence31),
                onPressed: () => _submitSequence('31'),
                helperMessage: _sequenceHelperMessage(sequence31),
                limitLabel: sequence31.endNumber?.toString() ?? 'Pendiente',
              );
              final second = _SequenceSetupCard(
                title: '32 - Consumo',
                prefixController: _sequencePrefixControllers['32']!,
                startController: _sequenceStartControllers['32']!,
                numberController: _sequenceNumberControllers['32']!,
                endController: _sequenceEndControllers['32']!,
                sequence: sequence32,
                busy: _creatingSequenceCode == '32',
                color: _sequenceStatusColor(context, sequence32),
                onPressed: () => _submitSequence('32'),
                helperMessage: _sequenceHelperMessage(sequence32),
                limitLabel: sequence32.endNumber?.toString() ?? 'Pendiente',
              );
              if (stacked) {
                return Column(
                  children: [first, const SizedBox(height: 10), second],
                );
              }
              return Row(
                children: [
                  Expanded(child: first),
                  const SizedBox(width: 10),
                  Expanded(child: second),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentRemoteConfig() async {
    final company = _company;
    if (company == null) return;

    final resolved = await _configRepository.saveConfig(
      company: company.copyWith(apiToken: _apiTokenController.text.trim()),
      electronicInvoicingEnabled:
          ref.read(businessSettingsProvider).electronicInvoicingEnabled,
    );
    if (!mounted) return;
    _syncControllers(resolved.company);
    _syncSequenceControllers(resolved.sequences);
    setState(() {
      _company = resolved.company;
      _sequences = resolved.sequences;
      _readiness = resolved.readiness;
    });
  }

  Future<void> _persistConfiguredSequences() async {
    final savedSequences = <ElectronicSequenceModel>[];
    for (final documentTypeCode in const ['31', '32']) {
      final draft = _buildSequenceDraft(documentTypeCode);
      if (draft == null) {
        continue;
      }
      final saved = await _sequenceRepository.createSequence(
        documentTypeCode: draft.documentTypeCode,
        prefix: draft.prefix,
        startNumber: draft.startNumber,
        currentNumber: draft.currentNumber,
        endNumber: draft.endNumber!,
        status: draft.status,
      );
      savedSequences.add(saved);
    }

    if (!mounted || savedSequences.isEmpty) return;
    for (final saved in savedSequences) {
      _replaceSequence(saved);
    }
  }

  ElectronicSequenceModel? _buildSequenceDraft(String documentTypeCode) {
    final prefix =
        _sequencePrefixControllers[documentTypeCode]?.text.trim().toUpperCase() ??
        '';
    final startNumber = int.tryParse(
      _sequenceStartControllers[documentTypeCode]?.text.trim() ?? '',
    );
    final currentNumber = int.tryParse(
      _sequenceNumberControllers[documentTypeCode]?.text.trim() ?? '',
    );
    final endNumber = int.tryParse(
      _sequenceEndControllers[documentTypeCode]?.text.trim() ?? '',
    );

    final hasAnyValue =
        prefix.isNotEmpty ||
        (startNumber != null && startNumber > 0) ||
        (currentNumber != null && currentNumber > 0) ||
        endNumber != null;
    if (!hasAnyValue) {
      return null;
    }

    if (prefix.isEmpty) {
      throw const ElectronicSequenceException(
        'Escriba el prefijo de la secuencia',
      );
    }
    if (startNumber == null || startNumber <= 0) {
      throw const ElectronicSequenceException(
        'Escriba el número inicial autorizado',
      );
    }
    if (currentNumber == null || currentNumber < 0) {
      throw const ElectronicSequenceException('Escriba una secuencia válida');
    }
    if (endNumber == null || endNumber <= currentNumber) {
      throw const ElectronicSequenceException(
        'Escriba un límite autorizado mayor que la secuencia actual',
      );
    }
    if (startNumber > endNumber) {
      throw const ElectronicSequenceException(
        'El número inicial no puede ser mayor al límite',
      );
    }

    return ElectronicSequenceModel.defaults(documentTypeCode).copyWith(
      prefix: prefix,
      startNumber: startNumber,
      currentNumber: currentNumber,
      endNumber: endNumber,
      status: currentNumber >= endNumber ? 'EXHAUSTED' : 'ACTIVE',
    );
  }
}

class _SystemStatusData {
  const _SystemStatusData({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({this.title, this.trailing, required this.child});

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

class _PrimarySwitchTile extends StatelessWidget {
  const _PrimarySwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ProfileSummaryRow extends StatelessWidget {
  const _ProfileSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.trim().isEmpty ? 'Sin completar' : value.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _InlineMetaPill extends StatelessWidget {
  const _InlineMetaPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: scheme.onSurface, fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SequenceSetupCard extends StatelessWidget {
  const _SequenceSetupCard({
    required this.title,
    required this.prefixController,
    required this.startController,
    required this.numberController,
    required this.endController,
    required this.sequence,
    required this.busy,
    required this.color,
    required this.onPressed,
    required this.helperMessage,
    required this.limitLabel,
  });

  final String title;
  final TextEditingController prefixController;
  final TextEditingController startController;
  final TextEditingController numberController;
  final TextEditingController endController;
  final ElectronicSequenceModel sequence;
  final bool busy;
  final Color color;
  final VoidCallback onPressed;
  final String helperMessage;
  final String limitLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _StatusChip(label: sequence.statusLabel, color: color),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InlineMetaPill(label: 'Tipo', value: title),
                    _InlineMetaPill(label: 'Prefijo', value: sequence.prefix),
                    _InlineMetaPill(
                      label: 'Actual',
                      value: sequence.currentNumber.toString(),
                    ),
                    _InlineMetaPill(label: 'Límite', value: limitLabel),
                    _InlineMetaPill(
                      label: 'Estado',
                      value: sequence.statusLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: prefixController,
                        decoration: const InputDecoration(labelText: 'Prefijo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: startController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Inicial'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: numberController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Actual'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: endController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Límite'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  helperMessage,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: busy ? null : onPressed,
                  child: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar secuencia'),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _StatusChip(label: sequence.statusLabel, color: color),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InlineMetaPill(label: 'Tipo', value: title),
                  _InlineMetaPill(label: 'Prefijo', value: sequence.prefix),
                  _InlineMetaPill(
                    label: 'Actual',
                    value: sequence.currentNumber.toString(),
                  ),
                  _InlineMetaPill(label: 'Límite', value: limitLabel),
                  _InlineMetaPill(label: 'Estado', value: sequence.statusLabel),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: prefixController,
                      decoration: const InputDecoration(labelText: 'Prefijo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: startController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Inicial'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: numberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Actual'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: endController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Límite'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      helperMessage,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: busy ? null : onPressed,
                    child: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar secuencia'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DocumentTableHeader extends StatelessWidget {
  const _DocumentTableHeader({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          _HeaderCell(flex: 3, text: 'Número'),
          _HeaderCell(flex: 2, text: 'Tipo'),
          _HeaderCell(flex: 3, text: 'Cliente'),
          _HeaderCell(flex: 2, text: 'Estado'),
          _HeaderCell(flex: 2, text: 'Fecha', alignEnd: true),
        ],
      ),
    );
  }
}

class _DocumentTableRow extends StatelessWidget {
  const _DocumentTableRow({
    required this.number,
    required this.type,
    required this.client,
    required this.status,
    required this.statusColor,
    required this.date,
  });

  final String number;
  final String type;
  final String client;
  final String status;
  final Color statusColor;
  final String date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          _BodyCell(flex: 3, text: number, weight: FontWeight.w800),
          _BodyCell(flex: 2, text: type),
          _BodyCell(flex: 3, text: client),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _StatusChip(label: status, color: statusColor),
            ),
          ),
          _BodyCell(
            flex: 2,
            text: date,
            alignEnd: true,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.flex,
    required this.text,
    this.alignEnd = false,
  });

  final int flex;
  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.flex,
    required this.text,
    this.weight = FontWeight.w600,
    this.alignEnd = false,
    this.color,
  });

  final int flex;
  final String text;
  final FontWeight weight;
  final bool alignEnd;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: TextStyle(fontWeight: weight, color: color),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

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
