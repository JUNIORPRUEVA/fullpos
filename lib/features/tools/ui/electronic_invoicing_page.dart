import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/services/empresa_service.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/utils/currency_display.dart';
import '../../../core/window/window_service.dart';
import '../../facturacion_electronica/data/electronic_certificate_repository.dart';
import '../../facturacion_electronica/data/dgii_certification_repository.dart';
import '../../facturacion_electronica/data/electronic_invoicing_diagnostics_repository.dart';
import '../../facturacion_electronica/data/electronic_invoicing_config_repository.dart';
import '../../facturacion_electronica/data/electronic_sequence_repository.dart';
import '../../facturacion_electronica/data/electronic_signer_repository.dart';
import '../../facturacion_electronica/data/factura_electronica_repository.dart';
import '../../facturacion_electronica/data/models/dgii_certification_model.dart';
import '../../facturacion_electronica/data/models/electronic_company_model.dart';
import '../../facturacion_electronica/data/models/electronic_invoicing_config_model.dart';
import '../../facturacion_electronica/data/models/electronic_sequence_model.dart';
import '../../facturacion_electronica/data/models/electronic_signer_model.dart';
import '../../facturacion_electronica/data/models/factura_electronica_model.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/providers/business_settings_provider.dart';
import '../../settings/ui/business_sections_settings_page.dart';
import '../../settings/ui/settings_layout.dart';

class ElectronicInvoicingPage extends ConsumerStatefulWidget {
  const ElectronicInvoicingPage({
    super.key,
    this.loadResolvedConfig,
    this.loadRecentInvoices,
    this.loadEmpresaConfig,
    this.businessSettingsOverride,
  });

  final Future<ElectronicInvoicingResolvedConfig> Function()?
  loadResolvedConfig;
  final Future<List<FacturaElectronicaModel>> Function()? loadRecentInvoices;
  final Future<EmpresaConfig> Function()? loadEmpresaConfig;
  final BusinessSettings? businessSettingsOverride;

  @override
  ConsumerState<ElectronicInvoicingPage> createState() =>
      _ElectronicInvoicingPageState();
}

class _ElectronicInvoicingPageState
    extends ConsumerState<ElectronicInvoicingPage> {
  final _apiTokenController = TextEditingController();
  final _aiApiKeyController = TextEditingController();
  final _aiModelController = TextEditingController();
  final _certificateAliasController = TextEditingController();
  final _certificatePasswordController = TextEditingController();
  final _signerFullNameController = TextEditingController();
  final _signerDocumentNumberController = TextEditingController();
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
  final ElectronicSignerRepository _signerRepository =
      ElectronicSignerRepository();
  final ElectronicInvoicingDiagnosticsRepository _diagnosticsRepository =
      ElectronicInvoicingDiagnosticsRepository();
  final DgiiCertificationRepository _certificationRepository =
      DgiiCertificationRepository();

  ElectronicCompanyModel? _company;
  EmpresaConfig? _empresaConfig;
  Map<String, String?> _resolvedCompanySummary = const <String, String?>{};
  List<FacturaElectronicaModel> _recentInvoices = <FacturaElectronicaModel>[];
  List<ElectronicSequenceModel> _sequences = <ElectronicSequenceModel>[];
  List<DgiiCertificationBatchModel> _certificationBatches =
      <DgiiCertificationBatchModel>[];
  List<DgiiCertificationCaseModel> _certificationCases =
      <DgiiCertificationCaseModel>[];
  DgiiCertificationBatchModel? _selectedCertificationBatch;
  DgiiCertificationBatchSummary? _certificationSummary;
  DgiiCertificationDiagnosticsModel? _certificationDiagnostics;
  DgiiCertificationBatchPreflightModel? _certificationBatchPreflight;
  final Map<int, DgiiCertificationCasePreflightModel> _certificationPreflights =
      <int, DgiiCertificationCasePreflightModel>{};
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
  bool _savingSigner = false;
  bool _showCertificatePassword = false;
  bool _testingBackend = false;
  bool _testingDgiiAuth = false;
  bool _showCertificationSection = false;
  bool _loadingCertification = false;
  bool _importingCertificationExcel = false;
  bool _generatingBatchXml = false;
  bool _resettingBatchXml = false;
  bool _signingBatchXml = false;
  bool _downloadingDgiiSeed = false;
  bool _uploadingDgiiSignedSeed = false;
  bool _sendingBatchXml = false;
  bool _queryingBatchResults = false;
  bool _preflightingBatch = false;
  bool _reprocessingAndSendingBatch = false;
  bool _auditingBatch = false;
  bool _aiAuditingBatch = false;
  bool _aiSuggestingFixBatch = false;
  int? _generatingCaseXmlId;
  int? _validatingCaseXmlId;
  int? _resettingCaseXmlId;
  int? _exportingCaseXmlId;
  int? _importingSignedCaseXmlId;
  int? _signingCaseXmlId;
  int? _sendingCaseXmlId;
  int? _queryingCaseResultId;
  int? _preflightingCaseId;
  int? _auditingCaseId;
  int? _aiAuditingCaseId;
  int? _aiSuggestingFixCaseId;
  int? _applyingCertifiedFixCaseId;

  String? _creatingSequenceCode;
  String? _selectedCertificatePath;
  String? _certificateNotice;
  bool _certificateNoticeIsError = false;
  int? _localCompanyId;
  DateTime? _lastBackendRefreshAt;
  ElectronicBackendDiagnosticResult? _backendDiagnostic;
  ElectronicDgiiAuthDiagnosticResult? _dgiiAuthDiagnostic;
  ElectronicSignerModel _signer = ElectronicSignerModel.empty();
  ElectronicSignerCertificateComparison? _certificateComparison;
  String _lastDiagnosticOperation = 'Carga inicial';
  String? _lastDiagnosticErrorCode;
  String? _lastDiagnosticErrorMessage;
  DateTime? _lastSuccessfulDiagnosticAt;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _apiTokenController.dispose();
    _aiApiKeyController.dispose();
    _aiModelController.dispose();
    _certificateAliasController.dispose();
    _certificatePasswordController.dispose();
    _signerFullNameController.dispose();
    _signerDocumentNumberController.dispose();
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
    final resolved = await (widget.loadResolvedConfig != null
        ? widget.loadResolvedConfig!()
        : _configRepository.loadResolvedConfig());
    final invoices = await (widget.loadRecentInvoices != null
        ? widget.loadRecentInvoices!()
        : FacturaElectronicaRepository.loadRecentResolved(limit: 18));
    final empresaConfig = await (widget.loadEmpresaConfig != null
        ? widget.loadEmpresaConfig!()
        : EmpresaService.getEmpresaConfig());
    final localCompanyId = await SessionManager.companyId();
    List<DgiiCertificationBatchModel> certificationBatches =
        const <DgiiCertificationBatchModel>[];
    try {
      certificationBatches = await _certificationRepository
          .getCertificationBatches();
    } catch (_) {
      certificationBatches = const <DgiiCertificationBatchModel>[];
    }
    if (!mounted) return;

    _syncControllers(resolved.company);
    _syncSequenceControllers(resolved.sequences);
    setState(() {
      _storeResolvedConfig(resolved);
      _empresaConfig = empresaConfig;
      _localCompanyId = localCompanyId;
      _recentInvoices = invoices;
      _certificationBatches = certificationBatches;
      DgiiCertificationBatchModel? selectedBatch;
      for (final batch in certificationBatches) {
        if (batch.id == _selectedCertificationBatch?.id) {
          selectedBatch = batch;
          break;
        }
      }
      _selectedCertificationBatch =
          selectedBatch ??
          (certificationBatches.isNotEmpty ? certificationBatches.first : null);
      if (resolved.readiness.backendValidated) {
        _lastBackendRefreshAt = DateTime.now();
        _lastSuccessfulDiagnosticAt ??= _lastBackendRefreshAt;
      }
      _lastDiagnosticOperation = resolved.readiness.backendValidated
          ? 'Configuración validada con backend'
          : 'Mostrando fallback local/caché';
      if (resolved.readiness.messages.isNotEmpty) {
        _lastDiagnosticErrorMessage = resolved.readiness.messages.first;
      }
      _loading = false;
    });
    final selectedBatch = _selectedCertificationBatch;
    if (selectedBatch != null) {
      await _loadCertificationCases(selectedBatch);
    }
  }

  void _syncControllers(ElectronicCompanyModel company) {
    _apiTokenController.text = company.apiToken;
    final settings = ref.read(businessSettingsProvider);
    _aiApiKeyController.text = settings.aiApiKey ?? '';
    _aiModelController.text = (settings.aiModel?.trim().isNotEmpty ?? false)
        ? settings.aiModel!
        : 'gpt-4.1-mini';
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
      if (!sequences.any((sequence) => sequence.documentTypeCode == '34'))
        ElectronicSequenceModel.defaults('34'),
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

  void _storeResolvedConfig(ElectronicInvoicingResolvedConfig resolved) {
    _company = resolved.company;
    _sequences = resolved.sequences;
    _readiness = resolved.readiness;
    _resolvedCompanySummary = resolved.companySummary;
    _signer = resolved.signer;
    _certificateComparison = resolved.certificateComparison;
    _syncSignerControllers(resolved.signer);
  }

  void _syncSignerControllers(ElectronicSignerModel signer) {
    _signerFullNameController.text = signer.signerFullName;
    _signerDocumentNumberController.text = signer.signerDocumentNumber;
  }

  String _normalizeSummaryValue(String? value) {
    return value?.trim() ?? '';
  }

  bool get _hasBackendCompanySummary {
    if (!_readiness.backendValidated) {
      return false;
    }
    return _resolvedCompanySummary.values.any(
      (value) => _normalizeSummaryValue(value).isNotEmpty,
    );
  }

  String _resolvedCompanyName() {
    if (_hasBackendCompanySummary) {
      final backendName = _normalizeSummaryValue(
        _resolvedCompanySummary['companyName'],
      );
      if (backendName.isNotEmpty) {
        return backendName;
      }
      final companyName = _company?.businessName.trim() ?? '';
      if (companyName.isNotEmpty) {
        return companyName;
      }
    }

    final empresaConfig = _empresaConfig;
    if (empresaConfig != null) {
      final businessName = empresaConfig.nombreEmpresa.trim();
      if (businessName.isNotEmpty) {
        return businessName;
      }
    }

    return _company?.businessName.trim() ?? '';
  }

  String _resolvedCompanyRnc() {
    if (_hasBackendCompanySummary) {
      final backendRnc = _normalizeSummaryValue(_resolvedCompanySummary['rnc']);
      if (backendRnc.isNotEmpty) {
        return backendRnc;
      }
      final companyRnc = _company?.rnc.trim() ?? '';
      if (companyRnc.isNotEmpty) {
        return companyRnc;
      }
    }

    return (_empresaConfig?.rnc ?? '').trim();
  }

  String _resolvedCompanyAddress() {
    if (_hasBackendCompanySummary) {
      final backendAddress = _normalizeSummaryValue(
        _resolvedCompanySummary['address'],
      );
      if (backendAddress.isNotEmpty) {
        return backendAddress;
      }
      final companyAddress = _company?.emissionAddress.trim() ?? '';
      if (companyAddress.isNotEmpty) {
        return companyAddress;
      }
    }

    return _empresaConfig?.direccionCompleta.trim() ?? '';
  }

  List<String> _companySummaryMissingFields() {
    final missing = <String>[];
    if (_resolvedCompanyName().isEmpty) {
      missing.add('Empresa');
    }
    if (_resolvedCompanyRnc().isEmpty) {
      missing.add('RNC');
    }
    if (_resolvedCompanyAddress().isEmpty) {
      missing.add('Dirección');
    }
    return missing;
  }

  String? _companySummaryHint() {
    final empresaConfig = _empresaConfig;
    if (_hasBackendCompanySummary) {
      final backendName = _resolvedCompanyName().toLowerCase();
      final backendRnc = _resolvedCompanyRnc();
      final backendAddress = _resolvedCompanyAddress().toLowerCase();
      final localName = empresaConfig?.nombreEmpresa.trim().toLowerCase() ?? '';
      final localRnc = (empresaConfig?.rnc ?? '').trim();
      final localAddress =
          empresaConfig?.direccionCompleta.trim().toLowerCase() ?? '';
      final differsFromLocal =
          (localName.isNotEmpty && localName != backendName) ||
          (localRnc.isNotEmpty && localRnc != backendRnc) ||
          (localAddress.isNotEmpty && localAddress != backendAddress);
      if (differsFromLocal) {
        return 'Mostrando la empresa validada en el backend. Si no coincide con Ajustes de empresa, revise la identidad sincronizada.';
      }
      return 'Mostrando la empresa validada en el backend.';
    }

    if (empresaConfig == null) {
      return 'Mostrando datos locales incompletos. Todavía no hay validación backend.';
    }
    return 'Mostrando datos locales. El estado final se confirma cuando el backend valida la empresa activa.';
  }

  bool _sequenceDraftHasAnyValue(String documentTypeCode) {
    final prefix =
        _sequencePrefixControllers[documentTypeCode]?.text.trim() ?? '';
    final startRaw =
        _sequenceStartControllers[documentTypeCode]?.text.trim() ?? '';
    final currentRaw =
        _sequenceNumberControllers[documentTypeCode]?.text.trim() ?? '';
    final endRaw = _sequenceEndControllers[documentTypeCode]?.text.trim() ?? '';
    return prefix.isNotEmpty ||
        startRaw.isNotEmpty ||
        currentRaw.isNotEmpty ||
        endRaw.isNotEmpty;
  }

  bool _sequenceDraftMatchesSaved(
    String documentTypeCode,
    ElectronicSequenceModel sequence,
  ) {
    final prefix =
        _sequencePrefixControllers[documentTypeCode]?.text
            .trim()
            .toUpperCase() ??
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

    return prefix == sequence.prefix.trim().toUpperCase() &&
        startNumber == sequence.startNumber &&
        currentNumber == sequence.currentNumber &&
        endNumber == sequence.endNumber;
  }

  bool _sequenceDraftIsComplete(String documentTypeCode) {
    final prefix =
        _sequencePrefixControllers[documentTypeCode]?.text
            .trim()
            .toUpperCase() ??
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

    if (prefix.isEmpty || startNumber == null || currentNumber == null) {
      return false;
    }
    if (startNumber <= 0 || currentNumber < 0 || endNumber == null) {
      return false;
    }
    return startNumber <= endNumber && endNumber > currentNumber;
  }

  String _sequenceDraftStatusLabel(
    String documentTypeCode,
    ElectronicSequenceModel sequence,
  ) {
    final hasDraft = _sequenceDraftHasAnyValue(documentTypeCode);
    if (!hasDraft || _sequenceDraftMatchesSaved(documentTypeCode, sequence)) {
      return sequence.statusLabel;
    }
    if (_sequenceDraftIsComplete(documentTypeCode)) {
      return 'Lista para guardar';
    }
    return 'Borrador incompleto';
  }

  String _sequenceStateHint(
    String documentTypeCode,
    ElectronicSequenceModel sequence,
  ) {
    final hasDraft = _sequenceDraftHasAnyValue(documentTypeCode);
    if (!hasDraft || _sequenceDraftMatchesSaved(documentTypeCode, sequence)) {
      return 'Estado y checklist muestran la secuencia guardada en backend.';
    }
    if (_sequenceDraftIsComplete(documentTypeCode)) {
      return 'Los campos tienen un borrador completo, pero todavia no esta guardado. Hasta guardar, el checklist seguira usando la secuencia persistida.';
    }
    return 'Los campos muestran un borrador local incompleto. Hasta completar el limite y guardar, la secuencia seguira figurando como no configurada.';
  }

  void _refreshSequenceDraftUi() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _testBackendDiagnostics() async {
    if (_testingBackend) return;
    setState(() {
      _testingBackend = true;
      _lastDiagnosticOperation = 'Probando backend';
      _lastDiagnosticErrorCode = null;
      _lastDiagnosticErrorMessage = null;
    });
    final result = await _diagnosticsRepository.testBackend();
    if (!mounted) return;
    if (result.ok && result.response.isNotEmpty) {
      final resolved = ElectronicInvoicingResolvedConfig.fromBackendMap(
        result.response,
        localApiToken: _company?.apiToken ?? _apiTokenController.text.trim(),
      );
      _syncControllers(resolved.company);
      _syncSequenceControllers(resolved.sequences);
      _storeResolvedConfig(resolved);
      _lastBackendRefreshAt = result.testedAt;
      _lastSuccessfulDiagnosticAt = result.testedAt;
    }
    setState(() {
      _backendDiagnostic = result;
      _testingBackend = false;
      _lastDiagnosticOperation = 'Probar backend';
      _lastDiagnosticErrorCode = result.errorCode;
      _lastDiagnosticErrorMessage = result.ok ? null : result.message;
    });
  }

  Future<void> _testDgiiAuthDiagnostics() async {
    if (_testingDgiiAuth) return;
    final company = _company;
    if (company == null) return;
    setState(() {
      _testingDgiiAuth = true;
      _lastDiagnosticOperation = 'Probando token DGII';
      _lastDiagnosticErrorCode = null;
      _lastDiagnosticErrorMessage = null;
    });
    final result = await _diagnosticsRepository.testDgiiAuth(
      environment: company.environment,
    );
    if (!mounted) return;
    setState(() {
      _dgiiAuthDiagnostic = result;
      _testingDgiiAuth = false;
      _lastDiagnosticOperation = 'Probar token DGII';
      _lastDiagnosticErrorCode = result.errorCode;
      _lastDiagnosticErrorMessage = result.ok ? null : result.message;
      if (result.ok) {
        _lastSuccessfulDiagnosticAt = result.testedAt;
      }
    });
  }

  Future<void> _copyDiagnostics(BusinessSettings businessSettings) async {
    final summary = _buildDiagnosticCopyText(businessSettings);
    await Clipboard.setData(ClipboardData(text: summary));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnóstico copiado sin secretos')),
    );
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
      final currentSettings = ref.read(businessSettingsProvider);
      await ref.read(businessSettingsProvider.notifier).saveSettings(
        currentSettings.copyWith(
          aiApiKey: _aiApiKeyController.text.trim().isEmpty
              ? null
              : _aiApiKeyController.text.trim(),
          aiModel: _aiModelController.text.trim().isEmpty
              ? 'gpt-4.1-mini'
              : _aiModelController.text.trim(),
        ),
      );
      await _persistConfiguredSequences();
      final activeEnabled = ref
          .read(businessSettingsProvider)
          .electronicInvoicingEnabled;
      final resolved = await _configRepository.saveConfig(
        company: company.copyWith(apiToken: _apiTokenController.text.trim()),
        active: activeEnabled,
        outboundEnabled: company.automaticEmission == 1,
      );

      if (!mounted) return;
      _syncControllers(resolved.company);
      _syncSequenceControllers(resolved.sequences);
      setState(() {
        _storeResolvedConfig(resolved);
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
    } on ElectronicSequenceException catch (error) {
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

  Future<void> _saveSigner() async {
    if (_savingSigner) return;
    final fullName = _signerFullNameController.text.trim();
    final documentNumber = _signerDocumentNumberController.text
        .trim()
        .replaceAll(RegExp(r'[-\s]'), '');

    if (fullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escriba el nombre completo del firmante'),
        ),
      );
      return;
    }
    if (documentNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escriba el documento del firmante')),
      );
      return;
    }

    setState(() => _savingSigner = true);
    try {
      final saved = await _signerRepository.saveSigner(
        signer: _signer.copyWith(
          signerFullName: fullName,
          signerDocumentType: _signer.signerDocumentType,
          signerDocumentNumber: documentNumber,
        ),
      );
      final resolved = await _configRepository.loadResolvedConfig();
      if (!mounted) return;
      setState(() {
        _signer = saved;
        _storeResolvedConfig(resolved);
        _savingSigner = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Responsable de firma guardado')),
      );
    } on ElectronicSignerException catch (error) {
      if (!mounted) return;
      setState(() => _savingSigner = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error, stackTrace) {
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/signer_save',
      );
      if (!mounted) return;
      setState(() => _savingSigner = false);
    }
  }

  void _useCertificateIdentity() {
    final comparison = _certificateComparison;
    if (comparison == null) return;
    final suggestedName = comparison.certificateSignerName?.trim() ?? '';
    final suggestedDocument =
        comparison.certificateDocumentNumber?.trim() ?? '';
    if (suggestedName.isEmpty && suggestedDocument.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se detectó identidad del certificado'),
        ),
      );
      return;
    }
    setState(() {
      if (suggestedName.isNotEmpty) {
        _signerFullNameController.text = suggestedName;
      }
      if (suggestedDocument.isNotEmpty) {
        _signerDocumentNumberController.text = suggestedDocument;
      }
    });
  }

  Future<void> _pickCertificateFile() async {
    try {
      final result = await WindowService.runWithSystemDialog(
        () => FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['p12', 'pfx'],
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
        _storeResolvedConfig(refreshed);
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

  Future<void> _refreshCertificationBatches() async {
    setState(() => _loadingCertification = true);
    try {
      final diagnostics = await _certificationRepository
          .getCertificationDiagnostics();
      final batches = await _certificationRepository.getCertificationBatches();
      if (!mounted) return;
      final selectedId = _selectedCertificationBatch?.id;
      DgiiCertificationBatchModel? selected;
      for (final batch in batches) {
        if (batch.id == selectedId) {
          selected = batch;
          break;
        }
      }
      setState(() {
        _certificationDiagnostics = diagnostics;
        _certificationBatches = batches;
        _selectedCertificationBatch =
            selected ?? (batches.isNotEmpty ? batches.first : null);
        if (_selectedCertificationBatch == null) {
          _certificationCases = const <DgiiCertificationCaseModel>[];
        }
      });
      final batch = _selectedCertificationBatch;
      if (batch != null) {
        await _loadCertificationCases(batch);
      }
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _loadingCertification = false);
    }
  }

  Future<void> _loadCertificationCases(
    DgiiCertificationBatchModel batch,
  ) async {
    setState(() {
      _selectedCertificationBatch = batch;
      _loadingCertification = true;
    });
    try {
      final diagnosticsFuture = _certificationRepository
          .getCertificationDiagnostics();
      final cases = await _certificationRepository.getCertificationBatchCases(
        batch.id,
      );
      final summary = await _certificationRepository
          .getCertificationBatchSummary(batch.id);
      final diagnostics = await diagnosticsFuture;
      if (!mounted) return;
      setState(() {
        _certificationDiagnostics = diagnostics;
        _certificationCases = cases;
        _certificationSummary = summary;
        _certificationBatchPreflight = null;
        _certificationPreflights.clear();
      });
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _loadingCertification = false);
    }
  }

  Future<void> _pickAndImportCertificationExcel() async {
    if (_importingCertificationExcel) return;
    try {
      final result = await WindowService.runWithSystemDialog(
        () => FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          allowMultiple: false,
        ),
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      if (path == null || path.trim().isEmpty) return;
      if (!path.toLowerCase().endsWith('.xlsx')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccione un archivo Excel .xlsx')),
        );
        return;
      }

      setState(() => _importingCertificationExcel = true);
      final imported = await _certificationRepository.importCertificationExcel(
        path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported.warnings.isEmpty
                ? 'Archivo DGII importado: ${imported.imported} casos'
                : 'Archivo importado con ${imported.warnings.length} advertencias',
          ),
        ),
      );
      await _refreshCertificationBatches();
      await _loadCertificationCases(imported.batch);
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error, stackTrace) {
      await ErrorHandler.instance.handle(
        error,
        stackTrace: stackTrace,
        context: context,
        module: 'electronic_invoicing/certification_import',
      );
    } finally {
      if (mounted) setState(() => _importingCertificationExcel = false);
    }
  }

  Future<void> _downloadDgiiManualSeed() async {
    if (_downloadingDgiiSeed) return;
    setState(() => _downloadingDgiiSeed = true);
    try {
      final seedXml = await _certificationRepository.downloadManualDgiiSeed();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar semilla DGII',
        fileName: 'dgii-semilla.xml',
        bytes: Uint8List.fromList(utf8.encode(seedXml)),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semilla descargada. Fírmala con la app oficial DGII.'),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _downloadingDgiiSeed = false);
    }
  }

  Future<void> _uploadDgiiManualSignedSeed() async {
    if (_uploadingDgiiSignedSeed) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() => _uploadingDgiiSignedSeed = true);
    try {
      final result = await _certificationRepository
          .uploadManualSignedDgiiSeed(path);
      final diagnostics = await _certificationRepository
          .getCertificationDiagnostics();
      if (!mounted) return;
      setState(() => _certificationDiagnostics = diagnostics);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ??
                'Semilla firmada validada. Token/Auth listo para probar un caso.',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _uploadingDgiiSignedSeed = false);
    }
  }

  Future<void> _deleteCertificationBatch(
    DgiiCertificationBatchModel batch,
  ) async {
    try {
      await _certificationRepository.deleteCertificationBatch(batch.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lote de certificacion eliminado')),
      );
      await _refreshCertificationBatches();
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  void _replaceCertificationCase(DgiiCertificationCaseModel updated) {
    setState(() {
      _certificationCases = _certificationCases
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
      _certificationPreflights.remove(updated.id);
      _certificationBatchPreflight = null;
    });
    final batch = _selectedCertificationBatch;
    if (batch != null) {
      _certificationRepository
          .getCertificationBatchSummary(batch.id)
          .then((summary) {
            if (!mounted) return;
            setState(() => _certificationSummary = summary);
          })
          .catchError((_) {});
    }
  }

  Future<void> _generateCertificationCaseXml(
    DgiiCertificationCaseModel item,
  ) async {
    if (_generatingCaseXmlId != null) return;
    setState(() => _generatingCaseXmlId = item.id);
    try {
      final updated = await _certificationRepository
          .generateCertificationCaseXml(item.id);
      if (!mounted) return;
      _replaceCertificationCase(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('XML generado')));
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      final batch = _selectedCertificationBatch;
      if (batch != null) await _loadCertificationCases(batch);
    } finally {
      if (mounted) setState(() => _generatingCaseXmlId = null);
    }
  }

  Future<void> _resetCertificationCaseXml(
    DgiiCertificationCaseModel item,
  ) async {
    if (_resettingCaseXmlId != null) return;
    final forceReset = const {
      'ACCEPTED',
      'ACCEPTED_CONDITIONAL',
      'REJECTED',
    }.contains(item.status);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar XML generado'),
        content: Text(
          'Esto borra el XML, la validacion y cualquier firma/envio guardado '
          'para ${item.encf}. El caso vuelve a IMPORTED para generarlo de nuevo.'
          '${forceReset ? '\n\nEste caso tiene resultado final DGII. Se reiniciara explicitamente para repetir la prueba de certificacion.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpiar XML'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingCaseXmlId = item.id);
    try {
      final updated = await _certificationRepository.resetCertificationCase(
        item.id,
        force: forceReset,
      );
      if (!mounted) return;
      _replaceCertificationCase(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('XML limpiado. Ya puedes generar el caso nuevamente.'),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      final batch = _selectedCertificationBatch;
      if (batch != null) await _loadCertificationCases(batch);
    } finally {
      if (mounted) setState(() => _resettingCaseXmlId = null);
    }
  }

  Future<void> _generateCertificationBatchXml() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _generatingBatchXml) return;
    setState(() => _generatingBatchXml = true);
    try {
      final result = await _certificationRepository
          .generateCertificationBatchXml(batch.id);
      if (!mounted) return;
      await _loadCertificationCases(batch);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'XML generados: ${result.generated}/${result.total}. Fallidos: ${result.failed}',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _generatingBatchXml = false);
    }
  }

  Future<void> _resetCertificationBatchXml() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _resettingBatchXml) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar XML del lote'),
        content: Text(
          'Esto limpia XML, validaciones, firmas y TrackId de los casos no finales '
          'del lote "${batch.fileName}". El Excel importado y las filas se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpiar lote'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingBatchXml = true);
    try {
      final result = await _certificationRepository.resetCertificationBatch(
        batch.id,
      );
      if (!mounted) return;
      await _loadCertificationCases(batch);
      final reset = result['reset'] ?? 0;
      final blocked = result['blockedFinal'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lote limpiado: $reset casos. Finales protegidos: $blocked.',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _resettingBatchXml = false);
    }
  }

  Future<void> _signCertificationCase(DgiiCertificationCaseModel item) async {
    if (_signingCaseXmlId != null) return;
    setState(() => _signingCaseXmlId = item.id);
    try {
      final updated = await _certificationRepository.signCertificationCase(
        item.id,
      );
      if (!mounted) return;
      _replaceCertificationCase(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('XML firmado')));
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      final batch = _selectedCertificationBatch;
      if (batch != null) await _loadCertificationCases(batch);
    } finally {
      if (mounted) setState(() => _signingCaseXmlId = null);
    }
  }

  Future<void> _validateCertificationCaseXml(
    DgiiCertificationCaseModel item,
  ) async {
    if (_validatingCaseXmlId != null) return;
    setState(() => _validatingCaseXmlId = item.id);
    try {
      final result = await _certificationRepository
          .validateCertificationCaseXml(item.id);
      if (!mounted) return;
      final batch = _selectedCertificationBatch;
      if (batch != null) await _loadCertificationCases(batch);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.canSign ? 'XML validado' : 'XML no listo para firmarse',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _validatingCaseXmlId = null);
    }
  }

  Future<void> _signCertificationBatch() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _signingBatchXml) return;
    setState(() => _signingBatchXml = true);
    try {
      final result = await _certificationRepository.signCertificationBatch(
        batch.id,
      );
      if (!mounted) return;
      await _loadCertificationCases(batch);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Firmados: ${result.signed}/${result.total}. Omitidos: ${result.skipped}. Fallidos: ${result.failed}',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _signingBatchXml = false);
    }
  }

  Future<void> _preflightCertificationCase(
    DgiiCertificationCaseModel item,
  ) async {
    if (_preflightingCaseId != null) return;
    setState(() => _preflightingCaseId = item.id);
    try {
      final result = await _certificationRepository.preflightCertificationCase(
        item.id,
      );
      if (!mounted) return;
      setState(() => _certificationPreflights[item.id] = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.canSend
                ? 'Preflight aprobado para enviar'
                : 'Preflight bloqueado: ${result.blockers.length} pendiente(s)',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _preflightingCaseId = null);
    }
  }

  Future<void> _preflightCertificationBatch() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _preflightingBatch) return;
    setState(() => _preflightingBatch = true);
    try {
      final diagnosticsFuture = _certificationRepository
          .getCertificationDiagnostics();
      final result = await _certificationRepository.preflightCertificationBatch(
        batch.id,
      );
      final diagnostics = await diagnosticsFuture;
      if (!mounted) return;
      setState(() {
        _certificationDiagnostics = diagnostics;
        _certificationBatchPreflight = result;
        _certificationPreflights
          ..clear()
          ..addEntries(result.cases.map((item) => MapEntry(item.caseId, item)));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Preflight: ${result.readyToSend}/${result.total} listo(s), ${result.blocked} bloqueado(s)',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _preflightingBatch = false);
    }
  }

  Future<void> _auditCertificationCase(
    DgiiCertificationCaseModel item, {
    bool ai = false,
  }) async {
    if ((_auditingCaseId ?? _aiAuditingCaseId) != null) return;
    setState(() {
      if (ai) {
        _aiAuditingCaseId = item.id;
      } else {
        _auditingCaseId = item.id;
      }
    });
    try {
      final result = ai
          ? await _certificationRepository.aiAuditCertificationCase(
              item.id,
              aiApiKey: _aiApiKeyController.text.trim(),
              aiModel: _aiModelController.text.trim(),
            )
          : await _certificationRepository.auditCertificationCase(item.id);
      if (!mounted) return;
      await _showCertificationAuditDialog(
        title: ai
            ? 'Auditoría IA ${item.encf ?? item.id}'
            : 'Auditoría ${item.encf ?? item.id}',
        result: result,
        currentCase: item,
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _auditingCaseId = null;
          _aiAuditingCaseId = null;
        });
      }
    }
  }

  Future<void> _auditCertificationBatch({bool ai = false}) async {
    final batch = _selectedCertificationBatch;
    if (batch == null) return;
    if (ai ? _aiAuditingBatch : _auditingBatch) return;
    setState(() {
      if (ai) {
        _aiAuditingBatch = true;
      } else {
        _auditingBatch = true;
      }
    });
    try {
      final result = ai
          ? await _certificationRepository.aiAuditCertificationBatch(
              batch.id,
              aiApiKey: _aiApiKeyController.text.trim(),
              aiModel: _aiModelController.text.trim(),
            )
          : await _certificationRepository.auditCertificationBatch(batch.id);
      if (!mounted) return;
      final cases = (result['cases'] is List)
          ? (result['cases'] as List)
                .whereType<Map>()
                .map(
                  (item) => DgiiCertificationAuditResult.fromMap(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <DgiiCertificationAuditResult>[];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(ai ? 'Auditar lote con IA' : 'Auditar lote'),
          content: SizedBox(
            width: 920,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Estado: ${result['status'] ?? 'N/D'}\nAptos: ${result['aptos'] ?? 0}/${result['total'] ?? 0}\nNo aptos: ${result['noAptos'] ?? 0}',
                  ),
                  if (result['ai'] is Map) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(result['ai'] as Map),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ...cases.map(
                    (audit) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${audit.encf ?? audit.caseId} · ${audit.status}'),
                        subtitle: Text(audit.summary),
                        trailing: Text(
                          audit.aptoParaEnviar ? 'OK' : 'ERROR',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: audit.aptoParaEnviar
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final payload = const JsonEncoder.withIndent('  ').convert(result);
                await Clipboard.setData(ClipboardData(text: payload));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reporte copiado')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copiar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _auditingBatch = false;
          _aiAuditingBatch = false;
        });
      }
    }
  }

  Future<void> _suggestCertificationFixCase(
    DgiiCertificationCaseModel item,
  ) async {
    if ((_aiSuggestingFixCaseId ?? _applyingCertifiedFixCaseId) != null) {
      return;
    }
    setState(() => _aiSuggestingFixCaseId = item.id);
    try {
      final result = await _certificationRepository
          .aiFixSuggestionCertificationCase(
            item.id,
            aiApiKey: _aiApiKeyController.text.trim(),
            aiModel: _aiModelController.text.trim(),
          );
      if (!mounted) return;
      await _showCertificationFixSuggestionDialog(item: item, result: result);
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      if (error.userMessage.contains('llave de conexion del POS')) {
        try {
          final audit = await _certificationRepository.auditCertificationCase(
            item.id,
          );
          if (!mounted) return;
          await _showCertificationFixSuggestionDialog(
            item: item,
            result: {
              'caseId': audit.caseId,
              'eNCF': audit.encf,
              'tipoEcf': audit.tipoEcf,
              'audit': {
                'caseId': audit.caseId,
                'eNCF': audit.encf,
                'tipoEcf': audit.tipoEcf,
                'filename': audit.filename,
                'filenameValid': audit.filenameValid,
                'xsdValid': audit.xsdValid,
                'requiredFieldsPresent': audit.requiredFieldsPresent,
                'noPlaceholders': audit.noPlaceholders,
                'totalsMatchExcel': audit.totalsMatchExcel,
                'totalsMatchItems': audit.totalsMatchItems,
                'aptoParaEnviar': audit.aptoParaEnviar,
                'status': audit.status,
                'summary': audit.summary,
                'warnings': audit.warnings,
                'errors': audit.errors,
                'mismatches': audit.mismatches
                    .map(
                      (m) => {
                        'field': m.field,
                        'excelExpected': m.excelExpected,
                        'xmlGenerated': m.xmlGenerated,
                        'calculatedFromItems': m.calculatedFromItems,
                        'difference': m.difference,
                        'severity': m.severity,
                      },
                    )
                    .toList(growable: false),
                'excelValues': audit.excelValues,
                'xmlValues': audit.xmlValues,
                'calculatedValues': audit.calculatedValues,
              },
              'suggestion': _localCertificationFixSuggestion(item, audit),
            },
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La llave rechazada es la del POS/backend, no la de IA. Se mostró una sugerencia técnica local.',
              ),
            ),
          );
          return;
        } on DgiiCertificationException {
          // fall through to original message
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _aiSuggestingFixCaseId = null);
    }
  }

  Future<void> _applyCertifiedFix(DgiiCertificationCaseModel item) async {
    if (_applyingCertifiedFixCaseId != null) return;
    setState(() => _applyingCertifiedFixCaseId = item.id);
    try {
      final result = await _certificationRepository
          .applyCertifiedFixCertificationCase(item.id);
      if (!mounted) return;
      final caseMap = result['case'];
      if (caseMap is Map) {
        _replaceCertificationCase(
          DgiiCertificationCaseModel.fromMap(caseMap.cast<String, dynamic>()),
        );
      } else {
        final batch = _selectedCertificationBatch;
        if (batch != null) await _loadCertificationCases(batch);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['aptoParaEnviar'] == true
                ? 'Corrección certificada aplicada y caso apto para enviar.'
                : 'Corrección aplicada. Revisa la auditoría técnica antes de firmar.',
          ),
        ),
      );
      final auditMap = result['audit'];
      if (auditMap is Map<String, dynamic>) {
        await _showCertificationAuditDialog(
          title: 'Auditoría tras corrección ${item.encf ?? item.id}',
          result: DgiiCertificationAuditResult.fromMap(auditMap),
          currentCase: caseMap is Map
              ? DgiiCertificationCaseModel.fromMap(
                  caseMap.cast<String, dynamic>(),
                )
              : item,
        );
      }
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _applyingCertifiedFixCaseId = null);
    }
  }

  Future<void> _suggestCertificationFixBatch() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _aiSuggestingFixBatch) return;
    setState(() => _aiSuggestingFixBatch = true);
    try {
      final result = await _certificationRepository
          .aiFixSuggestionCertificationBatch(
            batch.id,
            aiApiKey: _aiApiKeyController.text.trim(),
            aiModel: _aiModelController.text.trim(),
          );
      if (!mounted) return;
      final payload = const JsonEncoder.withIndent('  ').convert(result);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sugerir correcciones lote con IA'),
          content: SizedBox(
            width: 960,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Total: ${result['total'] ?? 0}\n'
                    'Corregibles automáticamente: ${result['automaticFixable'] ?? 0}\n'
                    'Revisión manual: ${result['manualReview'] ?? 0}\n'
                    'Ya aptos: ${result['alreadyReady'] ?? 0}',
                  ),
                  const SizedBox(height: 12),
                  if (result['repeatedCauses'] is List)
                    ...(result['repeatedCauses'] as List)
                        .whereType<Map>()
                        .map(
                          (item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item['cause']?.toString() ?? 'Sin causa'),
                            trailing: Text('${item['count'] ?? 0}'),
                          ),
                        ),
                  if (result['ai'] is Map) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(result['ai'] as Map),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SelectableText(
                    payload,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'RobotoMono',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: payload));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reporte copiado')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copiar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      if (error.userMessage.contains('llave de conexion del POS')) {
        try {
          final result = await _certificationRepository.auditCertificationBatch(
            batch.id,
          );
          if (!mounted) return;
          final cases = (result['cases'] is List)
              ? (result['cases'] as List)
                    .whereType<Map>()
                    .map(
                      (item) => DgiiCertificationAuditResult.fromMap(
                        item.cast<String, dynamic>(),
                      ),
                    )
                    .toList(growable: false)
              : const <DgiiCertificationAuditResult>[];
          final summary = {
            'total': cases.length,
            'automaticFixable': cases
                .where((item) => _localSuggestionCanAutoFix(item))
                .length,
            'manualReview': cases
                .where(
                  (item) => !_localSuggestionCanAutoFix(item) && !item.aptoParaEnviar,
                )
                .length,
            'alreadyReady': cases.where((item) => item.aptoParaEnviar).length,
            'repeatedCauses': _localBatchRepeatedCauses(cases),
            'cases': cases
                .map(
                  (item) => {
                    'caseId': item.caseId,
                    'eNCF': item.encf,
                    'tipoEcf': item.tipoEcf,
                    'aptoParaEnviar': item.aptoParaEnviar,
                    'puedeCorregirseAutomaticamente':
                        _localSuggestionCanAutoFix(item),
                    'causaPrincipal': _localSuggestionCause(item),
                  },
                )
                .toList(growable: false),
          };
          final payload = const JsonEncoder.withIndent('  ').convert(summary);
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sugerir correcciones lote con IA'),
              content: SizedBox(
                width: 900,
                child: SingleChildScrollView(
                  child: SelectableText(payload),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: payload));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reporte copiado')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copiar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La llave rechazada es la del POS/backend, no la de IA. Se mostró un resumen técnico local.',
              ),
            ),
          );
          return;
        } on DgiiCertificationException {
          // fall through
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _aiSuggestingFixBatch = false);
    }
  }

  Future<void> _sendCertificationCase(DgiiCertificationCaseModel item) async {
    if (_sendingCaseXmlId != null) return;
    setState(() => _sendingCaseXmlId = item.id);
    try {
      final updated = await _certificationRepository.sendCertificationCase(
        item.id,
      );
      if (!mounted) return;
      _replaceCertificationCase(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enviado a DGII${updated.trackId == null ? '' : ': ${updated.trackId}'}',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      final batch = _selectedCertificationBatch;
      if (batch != null) await _loadCertificationCases(batch);
    } finally {
      if (mounted) setState(() => _sendingCaseXmlId = null);
    }
  }

  Future<void> _sendCertificationBatch() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _sendingBatchXml) return;
    setState(() => _sendingBatchXml = true);
    var sent = 0;
    var rejected = 0;
    var failed = 0;
    var skipped = 0;
    final errors = <String>[];
    try {
      final readyCaseIds = _certificationBatchPreflight?.cases
              .where((item) => item.canSend)
              .map((item) => item.caseId)
              .toSet() ??
          const <int>{};
      final candidates = _certificationCases
          .where(
            (item) =>
                (item.status == 'SIGNED' ||
                    (item.status == 'ERROR' &&
                        (item.trackId?.trim().isEmpty ?? true))) &&
                (item.xmlSigned?.trim().isNotEmpty ?? false) &&
                (readyCaseIds.isEmpty || readyCaseIds.contains(item.id)),
          )
          .toList(growable: false);

      for (final item in candidates) {
        if (!mounted) break;
        setState(() => _sendingCaseXmlId = item.id);
        try {
          final updated = await _certificationRepository.sendCertificationCase(
            item.id,
          );
          if (!mounted) break;
          _replaceCertificationCase(updated);
          if (updated.status == 'SENT' || updated.status == 'EN_PROCESO') {
            sent += 1;
          } else if (updated.status == 'REJECTED') {
            rejected += 1;
          } else if (updated.status == 'ERROR') {
            failed += 1;
            errors.add(
              '${updated.encf ?? 'Caso ${updated.id}'}: ${updated.errorMessage ?? 'DGII no devolvio una respuesta valida'}',
            );
          } else {
            skipped += 1;
          }
        } on DgiiCertificationException catch (error) {
          failed += 1;
          errors.add('${item.encf ?? 'Caso ${item.id}'}: ${error.userMessage}');
        }
      }

      if (!mounted) return;
      await _loadCertificationCases(batch);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Envio DGII: enviados $sent/${candidates.length}, rechazados $rejected, omitidos $skipped, fallidos $failed',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      await _loadCertificationCases(batch);
    } finally {
      if (mounted && errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errors.take(2).join('\n'))),
        );
      }
      if (mounted) setState(() => _sendingCaseXmlId = null);
      if (mounted) setState(() => _sendingBatchXml = false);
    }
  }

  Future<void> _reprocessAndSendCertificationBatch() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _reprocessingAndSendingBatch) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reprocesar y enviar lote'),
        content: Text(
          'Vamos a limpiar, generar XML, firmar, verificar y enviar los casos no finales '
          'del lote "${batch.fileName}". Los casos finales se quedan protegidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ejecutar todo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _reprocessingAndSendingBatch = true);
    try {
      final result = await _certificationRepository
          .reprocessAndSendCertificationBatch(batch.id);
      if (!mounted) return;
      await _loadCertificationCases(batch);

      final reset = (result['reset'] as num?)?.toInt() ?? 0;
      final blockedFinal = (result['blockedFinal'] as num?)?.toInt() ?? 0;
      final generated = (result['generated'] as num?)?.toInt() ?? 0;
      final generationFailed = (result['generationFailed'] as num?)?.toInt() ?? 0;
      final signed = (result['signed'] as num?)?.toInt() ?? 0;
      final signingFailed = (result['signingFailed'] as num?)?.toInt() ?? 0;
      final readyToSend = (result['readyToSend'] as num?)?.toInt() ?? 0;
      final blocked = (result['blocked'] as num?)?.toInt() ?? 0;
      final sent = (result['sent'] as num?)?.toInt() ?? 0;
      final sendFailed = (result['sendFailed'] as num?)?.toInt() ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Proceso completo: limpiados $reset, XML $generated, firmados $signed, '
            'listos $readyToSend, enviados $sent. Bloqueados $blocked, fallos XML $generationFailed, '
            'fallos firma $signingFailed, fallos envio $sendFailed, finales protegidos $blockedFinal.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );

      final sendErrors = result['sendErrors'];
      final generationErrors = result['generationErrors'];
      final signingErrors = result['signingErrors'];
      final blockedCases = result['blockedCases'];
      String readMapValue(dynamic item, List<String> keys) {
        if (item is! Map) return item?.toString() ?? '';
        final map = item.cast<dynamic, dynamic>();
        for (final key in keys) {
          final value = map[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString();
          }
        }
        return '';
      }
      final details = <String>[
        if (generationErrors is List && generationErrors.isNotEmpty)
          'XML: ${readMapValue(generationErrors.first, ['humanReadableMessage', 'message'])}',
        if (signingErrors is List && signingErrors.isNotEmpty)
          'Firma: ${readMapValue(signingErrors.first, ['message'])}',
        if (blockedCases is List && blockedCases.isNotEmpty)
          'Bloqueado: ${readMapValue(blockedCases.first, ['encf']).isEmpty ? 'caso' : readMapValue(blockedCases.first, ['encf'])} -> ${((blockedCases.first is Map ? blockedCases.first['blockers'] : null) as List?)?.join(', ') ?? ''}',
        if (sendErrors is List && sendErrors.isNotEmpty)
          'Envio: ${readMapValue(sendErrors.first, ['message'])}',
      ];
      if (details.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(details.take(2).join('\n')),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _reprocessingAndSendingBatch = false);
    }
  }

  bool _hasCertificationCasesReadyToSend() {
    return _certificationCases.any(
      (item) =>
          (item.status == 'SIGNED' ||
              (item.status == 'ERROR' &&
                  (item.trackId?.trim().isEmpty ?? true))) &&
          (item.xmlSigned?.trim().isNotEmpty ?? false),
    );
  }

  Future<void> _queryCertificationCaseResult(
    DgiiCertificationCaseModel item,
  ) async {
    if (_queryingCaseResultId != null) return;
    setState(() => _queryingCaseResultId = item.id);
    try {
      final updated = await _certificationRepository
          .queryCertificationCaseResult(item.id);
      if (!mounted) return;
      _replaceCertificationCase(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Resultado DGII: ${_certificationStatusLabel(updated.status)}',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _queryingCaseResultId = null);
    }
  }

  Future<void> _queryCertificationBatchResults() async {
    final batch = _selectedCertificationBatch;
    if (batch == null || _queryingBatchResults) return;
    setState(() => _queryingBatchResults = true);
    try {
      final result = await _certificationRepository
          .queryCertificationBatchResults(batch.id);
      if (!mounted) return;
      await _loadCertificationCases(batch);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Consultados: ${result.queried}/${result.total}. Aceptados: ${result.accepted}. Rechazados: ${result.rejected}. En proceso: ${result.processing}',
          ),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } finally {
      if (mounted) setState(() => _queryingBatchResults = false);
    }
  }

  Future<void> _showCertificationXml(
    DgiiCertificationCaseModel item, {
    bool signed = false,
  }) async {
    try {
      final cached = signed ? item.xmlSigned : item.xmlGenerated;
      final xml = cached?.trim().isNotEmpty == true
          ? cached!
          : signed
          ? await _certificationRepository.getCertificationCaseSignedXml(
              item.id,
            )
          : await _certificationRepository.getCertificationCaseXml(item.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '${signed ? 'XML firmado' : 'XML'} ${item.encf ?? item.id}',
          ),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: SelectableText(
                xml,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'RobotoMono'),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: xml));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('XML copiado')));
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copiar XML'),
            ),
            TextButton.icon(
              onPressed: () => _downloadCertificationXml(item, xml),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar XML'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  Future<void> _showCertificationAuditDialog({
    required String title,
    required DgiiCertificationAuditResult result,
    DgiiCertificationCaseModel? currentCase,
  }) async {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'caseId': result.caseId,
      'eNCF': result.encf,
      'tipoEcf': result.tipoEcf,
      'filename': result.filename,
      'filenameValid': result.filenameValid,
      'xsdValid': result.xsdValid,
      'requiredFieldsPresent': result.requiredFieldsPresent,
      'noPlaceholders': result.noPlaceholders,
      'totalsMatchExcel': result.totalsMatchExcel,
      'totalsMatchItems': result.totalsMatchItems,
      'aptoParaEnviar': result.aptoParaEnviar,
      'status': result.status,
      'summary': result.summary,
      'warnings': result.warnings,
      'errors': result.errors,
      'mismatches': result.mismatches
          .map(
            (item) => {
              'field': item.field,
              'excelExpected': item.excelExpected,
              'xmlGenerated': item.xmlGenerated,
              'calculatedFromItems': item.calculatedFromItems,
              'difference': item.difference,
              'severity': item.severity,
            },
          )
          .toList(growable: false),
      'excelValues': result.excelValues,
      'xmlValues': result.xmlValues,
      'calculatedValues': result.calculatedValues,
      'ai': result.ai,
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 920,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      label: result.status,
                      color: result.aptoParaEnviar ? Colors.green : Colors.red,
                    ),
                    _InlineMetaPill(
                      label: 'Archivo',
                      value: result.filename ?? 'N/D',
                    ),
                    _InlineMetaPill(
                      label: 'XSD',
                      value: result.xsdValid ? 'Válido' : 'Inválido',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(result.summary, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (result.mismatches.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...result.mismatches.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: item.severity == 'ERROR'
                              ? Colors.red.withOpacity(0.06)
                              : Colors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: item.severity == 'ERROR'
                                ? Colors.red.withOpacity(0.20)
                                : Colors.orange.withOpacity(0.24),
                          ),
                        ),
                        child: SelectableText(
                          '${item.field}\nExcel: ${item.excelExpected ?? 'N/D'}\nXML: ${item.xmlGenerated ?? 'N/D'}\nItems: ${item.calculatedFromItems ?? 'N/D'}\nDiferencia: ${item.difference ?? '0.00'}',
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SelectableText(
                  payload,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'RobotoMono',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (currentCase != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _suggestCertificationFixCase(currentCase);
              },
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Sugerir corrección con IA'),
            ),
          if (currentCase != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _applyCertifiedFix(currentCase);
              },
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Aplicar corrección certificada'),
            ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reporte copiado')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
      );
  }

  Map<String, dynamic> _localCertificationFixSuggestion(
    DgiiCertificationCaseModel item,
    DgiiCertificationAuditResult audit,
  ) {
    List<Map<String, dynamic>> suggestedItems = [];

    void addBucket(
      String field,
      String indicador,
      String nombre,
    ) {
      final raw = audit.excelValues[field]?.toString().trim();
      if (raw == null || raw.isEmpty) return;
      final parsed = double.tryParse(raw.replaceAll(',', ''));
      if (parsed == null || parsed <= 0) return;
      suggestedItems.add({
        'NumeroLinea': suggestedItems.length + 1,
        'IndicadorFacturacion': indicador,
        'NombreItem': nombre,
        'IndicadorBienoServicio': '2',
        'CantidadItem': '1.00',
        'PrecioUnitarioItem': raw,
        'MontoItem': raw,
      });
    }

    addBucket('MontoGravadoI1', '1', 'Ajuste gravado 18 DGII');
    addBucket('MontoGravadoI2', '2', 'Ajuste gravado 16 DGII');
    addBucket('MontoGravadoI3', '3', 'Ajuste gravado 0 DGII');
    addBucket('MontoExento', '4', 'Ajuste exento DGII');

    final canAutoFix = _localSuggestionCanAutoFix(audit);

    return {
      'modo': 'Sugerir corrección DGII',
      'aptoParaEnviar': audit.aptoParaEnviar,
      'puedeCorregirseAutomaticamente': canAutoFix,
      'causaPrincipal': _localSuggestionCause(audit),
      'correccionRecomendada': canAutoFix
          ? 'Reconstruir DetallesItems desde los buckets del Excel, regenerar XML, validar XSD y repetir auditoría.'
          : 'Revisar campos obligatorios faltantes o diferencias que no pueden corregirse automáticamente.',
      'itemsSugeridos': suggestedItems,
      'totalesSugeridos': audit.excelValues,
      'camposOpcionalesAOmitir': _rawPlaceholderKeys(item),
      'camposObligatoriosFaltantes': item.missingXmlFields,
      'diferenciasQueSeResolverian': audit.mismatches
          .map((m) => m.field)
          .toSet()
          .toList(growable: false),
      'riesgoDGII': audit.aptoParaEnviar
          ? 'BAJO'
          : (canAutoFix ? 'MEDIO' : 'ALTO'),
      'pasosParaCorregir': [
        'Usar los valores del Excel DGII como fuente oficial.',
        if (suggestedItems.isNotEmpty)
          'Reconstruir DetallesItems usando un item por bucket fiscal.',
        if (item.missingXmlFields.isNotEmpty)
          'Completar los campos obligatorios faltantes.',
        'Regenerar XML.',
        'Validar contra XSD.',
        'Verificar nuevamente Excel vs XML vs Totales calculados.',
      ],
    };
  }

  bool _localSuggestionCanAutoFix(DgiiCertificationAuditResult audit) {
    final hasBuckets = [
      audit.excelValues['MontoGravadoI1'],
      audit.excelValues['MontoGravadoI2'],
      audit.excelValues['MontoGravadoI3'],
      audit.excelValues['MontoExento'],
    ].any((value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return false;
      final parsed = double.tryParse(text.replaceAll(',', ''));
      return parsed != null && parsed > 0;
    });
    return !audit.aptoParaEnviar &&
        audit.filenameValid &&
        audit.requiredFieldsPresent &&
        hasBuckets;
  }

  String _localSuggestionCause(DgiiCertificationAuditResult audit) {
    if (!audit.filenameValid) {
      return 'El nombre del archivo no cumple el formato DGII.';
    }
    if (!audit.requiredFieldsPresent) {
      return 'Faltan campos obligatorios para construir el XML.';
    }
    if (!audit.xsdValid) {
      return 'El XML no valida contra el XSD DGII.';
    }
    if (!audit.totalsMatchExcel || !audit.totalsMatchItems) {
      return 'Los Totales y los DetallesItems no reproducen la fila oficial del Excel.';
    }
    if (!audit.noPlaceholders) {
      return 'El XML conserva placeholders inválidos.';
    }
    return audit.summary;
  }

  List<String> _rawPlaceholderKeys(DgiiCertificationCaseModel item) {
    const placeholderValues = {'#e', '#n/a', 'n/a', 'null', 'undefined', ''};
    return item.rawRowJson.entries
        .where((entry) {
          if (entry.key.startsWith('__')) return false;
          final normalized = entry.value?.toString().trim().toLowerCase() ?? '';
          return placeholderValues.contains(normalized) &&
              !item.missingXmlFields.contains(entry.key);
        })
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _localBatchRepeatedCauses(
    List<DgiiCertificationAuditResult> audits,
  ) {
    final counts = <String, int>{};
    for (final audit in audits) {
      final cause = _localSuggestionCause(audit);
      counts[cause] = (counts[cause] ?? 0) + 1;
    }
    final rows = counts.entries
        .map((entry) => {'cause': entry.key, 'count': entry.value})
        .toList(growable: false);
    rows.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return rows;
  }

  Future<void> _showCertificationFixSuggestionDialog({
    required DgiiCertificationCaseModel item,
    required Map<String, dynamic> result,
  }) async {
    final suggestion = result['suggestion'] is Map
        ? (result['suggestion'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final audit = result['audit'] is Map
        ? (result['audit'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final payload = const JsonEncoder.withIndent('  ').convert(result);
    final items = suggestion['itemsSugeridos'] is List
        ? (suggestion['itemsSugeridos'] as List).whereType<Map>().toList()
        : const <Map>[];
    final pasos = suggestion['pasosParaCorregir'] is List
        ? (suggestion['pasosParaCorregir'] as List)
              .map((value) => value.toString())
              .toList(growable: false)
        : const <String>[];
    final diferencias = suggestion['diferenciasQueSeResolverian'] is List
        ? (suggestion['diferenciasQueSeResolverian'] as List)
              .map((value) => value.toString())
              .toList(growable: false)
        : const <String>[];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sugerir corrección con IA ${item.encf ?? item.id}'),
        content: SizedBox(
          width: 960,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      label: suggestion['aptoParaEnviar'] == true
                          ? 'APTO PARA ENVIAR'
                          : (suggestion['puedeCorregirseAutomaticamente'] == true
                                ? 'REQUIERE CORRECCIÓN'
                                : 'NO APTO PARA ENVIAR'),
                      color: suggestion['aptoParaEnviar'] == true
                          ? Colors.green
                          : (suggestion['puedeCorregirseAutomaticamente'] == true
                                ? Colors.orange
                                : Colors.red),
                    ),
                    _InlineMetaPill(
                      label: 'Riesgo DGII',
                      value: suggestion['riesgoDGII']?.toString() ?? 'N/D',
                    ),
                    _InlineMetaPill(
                      label: 'Auto fix',
                      value: suggestion['puedeCorregirseAutomaticamente'] == true
                          ? 'Sí'
                          : 'No',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Problema principal: ${suggestion['causaPrincipal'] ?? audit['summary'] ?? 'N/D'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'Corrección recomendada: ${suggestion['correccionRecomendada'] ?? 'N/D'}',
                ),
                if (diferencias.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Diferencias que se resolverían',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...diferencias.map((value) => SelectableText('• $value')),
                ],
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Items sugeridos',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...items.map(
                    (itemMap) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.withOpacity(0.18)),
                      ),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(itemMap),
                      ),
                    ),
                  ),
                ],
                if (pasos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Pasos para corregir',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...pasos.map((value) => SelectableText('• $value')),
                ],
                const SizedBox(height: 12),
                SelectableText(
                  payload,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'RobotoMono',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (suggestion['puedeCorregirseAutomaticamente'] == true)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _applyCertifiedFix(item);
              },
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Aplicar corrección certificada'),
            ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reporte copiado')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCertificationXml(
    DgiiCertificationCaseModel item,
    String xml,
  ) async {
    try {
      final safeName =
          (item.encf?.trim().isNotEmpty == true
                  ? item.encf!.trim()
                  : 'dgii_case_${item.id}')
              .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar XML DGII',
        fileName: '$safeName.xml',
        bytes: Uint8List.fromList(utf8.encode(xml)),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('XML descargado')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo descargar el XML')),
      );
    }
  }

  Future<void> _exportGeneratedCertificationXml(
    DgiiCertificationCaseModel item,
  ) async {
    if (_exportingCaseXmlId != null) return;
    setState(() => _exportingCaseXmlId = item.id);
    try {
      final xml = item.xmlGenerated?.trim().isNotEmpty == true
          ? item.xmlGenerated!
          : await _certificationRepository.getCertificationCaseXml(item.id);
      final safeName =
          (item.encf?.trim().isNotEmpty == true
                  ? item.encf!.trim()
                  : 'dgii_case_${item.id}')
              .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exportar XML sin firmar',
        fileName: '$safeName-sin-firmar.xml',
        bytes: Uint8List.fromList(utf8.encode(xml)),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('XML exportado. Firmalo con la app DGII y luego importalo.'),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _exportingCaseXmlId = null);
    }
  }

  Future<void> _importManualSignedCertificationXml(
    DgiiCertificationCaseModel item,
  ) async {
    if (_importingSignedCaseXmlId != null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() => _importingSignedCaseXmlId = item.id);
    try {
      final updated = await _certificationRepository
          .uploadManualSignedCertificationCaseXml(item.id, path);
      if (!mounted) return;
      _replaceCertificationCase(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('XML firmado importado. Ya puedes enviar solo este caso.'),
        ),
      );
    } on DgiiCertificationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _importingSignedCaseXmlId = null);
    }
  }

  Future<void> _showCertificationCaseDetail(
    DgiiCertificationCaseModel item,
  ) async {
    DgiiCertificationCaseModel detail = item;
    try {
      detail = await _certificationRepository.getCertificationCase(item.id);
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          detail.encf?.trim().isNotEmpty == true ? detail.encf! : 'Caso DGII',
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DiagnosticLine(label: 'eNCF', value: detail.encf ?? 'N/D'),
                _DiagnosticLine(
                  label: 'Tipo e-CF',
                  value: detail.tipoEcf ?? 'N/D',
                ),
                _DiagnosticLine(label: 'Hoja', value: detail.sheetName),
                _DiagnosticLine(
                  label: 'Fila',
                  value: detail.rowNumber.toString(),
                ),
                _DiagnosticLine(
                  label: 'Estado',
                  value: _certificationStatusLabel(detail.status),
                ),
                _DiagnosticLine(
                  label: 'TrackId',
                  value: detail.trackId ?? 'N/D',
                ),
                _DiagnosticLine(
                  label: 'Codigo DGII',
                  value: detail.dgiiStatusCode ?? 'N/D',
                ),
                _DiagnosticLine(
                  label: 'Mensaje DGII',
                  value: detail.dgiiStatusMessage ?? 'N/D',
                ),
                _DiagnosticLine(
                  label: 'Validacion XML',
                  value: _xmlValidationLabel(detail),
                ),
                _DiagnosticLine(
                  label: 'XSD usado',
                  value: detail.effectiveXsdFileUsed ?? 'N/D',
                ),
                _DiagnosticLine(
                  label: 'Codigo rechazo',
                  value: detail.rejectionCode ?? 'N/D',
                ),
                _DiagnosticLine(
                  label: 'Motivo rechazo',
                  value:
                      detail.rejectionMessage ??
                      detail.xmlGenerationHumanMessage ??
                      'N/D',
                ),
                if (detail.dgiiRawResponseJson?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Respuesta cruda DGII',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        detail.formattedDgiiRawResponseJson(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'RobotoMono',
                            ),
                      ),
                    ),
                  ),
                ],
                if (detail.parsedXsdElementHint?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Elemento XSD reportado',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(detail.parsedXsdElementHint!),
                ],
                if (detail.effectiveRawXmllintOutput?.trim().isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Error XSD / xmllint',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      detail.effectiveRawXmllintOutput!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'RobotoMono'),
                    ),
                  ),
                ],
                if (detail.xmlValidationWarnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Advertencias de validacion',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    detail.xmlValidationWarnings
                        .map((value) => '- $value')
                        .join('\n'),
                  ),
                ],
                if (detail.missingXmlFields.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Campos faltantes',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(detail.missingXmlFields.join(', ')),
                ],
                if (detail.extractedXmlFields.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Campos detectados',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(_formatCompactJson(detail.extractedXmlFields)),
                ],
                const SizedBox(height: 10),
                Text(
                  'Resumen rawRowJson',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  detail.rawRowKeys.take(40).join(', '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _DiagnosticLine(
                  label: 'RNC emisor',
                  value: detail.rncEmisor ?? 'N/D',
                ),
                _DiagnosticLine(
                  label: 'RNC comprador',
                  value: detail.rncComprador ?? 'N/D',
                ),
                _DiagnosticLine(
                  label: 'Fecha emision',
                  value: detail.fechaEmision == null
                      ? 'N/D'
                      : DateFormat('dd/MM/yyyy').format(detail.fechaEmision!),
                ),
                _DiagnosticLine(
                  label: 'Monto total',
                  value: detail.montoTotal == null
                      ? 'N/D'
                      : CurrencyDisplay.format(detail.montoTotal!),
                ),
                const SizedBox(height: 10),
                Text(
                  'Raw row JSON',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  detail.formattedRawJson(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'RobotoMono'),
                ),
                const SizedBox(height: 12),
                Text('XML', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                if (detail.xmlGenerated?.trim().isNotEmpty == true) ...[
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        detail.xmlGenerated!.length > 4000
                            ? '${detail.xmlGenerated!.substring(0, 4000)}\n...'
                            : detail.xmlGenerated!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'RobotoMono',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (detail.xmlGenerated?.trim().isNotEmpty == true) ...[
                      OutlinedButton.icon(
                        onPressed: () => _showCertificationXml(detail),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Ver XML'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _validateCertificationCaseXml(detail),
                        icon: const Icon(Icons.rule_outlined),
                        label: const Text('Validar XML'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: detail.xmlGenerated!),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('XML copiado')),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copiar XML'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _downloadCertificationXml(
                          detail,
                          detail.xmlGenerated!,
                        ),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Descargar XML'),
                      ),
                      OutlinedButton.icon(
                        onPressed: const <String>{
                                  'ACCEPTED',
                                  'ACCEPTED_CONDITIONAL',
                                  'REJECTED',
                                }.contains(detail.status.toUpperCase())
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                _importManualSignedCertificationXml(detail);
                              },
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Subir XML firmado'),
                      ),
                    ],
                    if (detail.xmlSigned?.trim().isNotEmpty == true) ...[
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showCertificationXml(detail, signed: true),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Ver XML firmado'),
                      ),
                    ],
                    if (detail.status.toUpperCase() == 'XML_GENERATED')
                      FilledButton.icon(
                        onPressed: _certificationXmlCanBeSigned(detail)
                            ? () {
                                Navigator.of(context).pop();
                                _signCertificationCase(detail);
                              }
                            : null,
                        icon: const Icon(Icons.draw_outlined),
                        label: const Text('Firmar XML'),
                      ),
                    if (detail.status.toUpperCase() == 'SIGNED')
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _sendCertificationCase(detail);
                        },
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Enviar a DGII'),
                      ),
                    if (detail.status.toUpperCase() == 'SENT' ||
                        detail.status.toUpperCase() == 'EN_PROCESO')
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _queryCertificationCaseResult(detail);
                        },
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Consultar resultado'),
                      ),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _generateCertificationCaseXml(detail);
                      },
                      icon: const Icon(Icons.code_outlined),
                      label: Text(
                        detail.xmlGenerated?.trim().isNotEmpty == true
                            ? 'Regenerar XML'
                            : 'Generar XML',
                      ),
                    ),
                    if (detail.xmlGenerated?.trim().isNotEmpty == true &&
                        !const <String>{
                          'ACCEPTED',
                          'ACCEPTED_CONDITIONAL',
                          'REJECTED',
                        }.contains(detail.status.toUpperCase()))
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _resetCertificationCaseXml(detail);
                        },
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Limpiar XML'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _suggestCertificationFixCase(item);
            },
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Sugerir corrección con IA'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSalesVisibility(bool enabled) async {
    if (_savingVisibility) return;

    final previousValue = ref
        .read(businessSettingsProvider)
        .electronicInvoicingEnabled;
    setState(() => _savingVisibility = true);
    try {
      await ref
          .read(businessSettingsProvider.notifier)
          .updateElectronicInvoicingEnabled(enabled);
      await _saveCurrentRemoteConfig(visibilityEnabled: enabled);
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
      final updatedCompany = company.copyWith(
        automaticEmission: enabled ? 1 : 0,
      );
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

  Future<void> _saveCurrentRemoteConfig({bool? visibilityEnabled}) async {
    final company = _company;
    if (company == null) return;

    final effectiveVisibility =
        visibilityEnabled ??
        ref.read(businessSettingsProvider).electronicInvoicingEnabled;

    final resolved = await _configRepository.saveConfig(
      company: company.copyWith(apiToken: _apiTokenController.text.trim()),
      active: effectiveVisibility,
      outboundEnabled: company.automaticEmission == 1,
    );
    if (!mounted) return;

    _syncControllers(resolved.company);
    _syncSequenceControllers(resolved.sequences);
    setState(() {
      _storeResolvedConfig(resolved);
    });
  }

  Future<void> _persistConfiguredSequences() async {
    final savedSequences = <ElectronicSequenceModel>[];
    for (final documentTypeCode in const ['31', '32', '34']) {
      final draft = _buildSequenceDraft(documentTypeCode);
      if (draft == null) {
        continue;
      }
      if (_sequenceDraftMatchesSaved(
        documentTypeCode,
        _sequenceFor(documentTypeCode),
      )) {
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
      final sequence34 = ElectronicSequenceModel.defaults('34').copyWith(
        prefix: 'E34',
        startNumber: 1,
        currentNumber: 0,
        endNumber: null,
        status: '',
      );
      await _configRepository.cacheDraftConfig(savedCompany);
      await _configRepository.cacheDraftSequences([
        sequence31,
        sequence32,
        sequence34,
      ]);
      final resolved = await _configRepository.saveConfig(
        company: savedCompany.copyWith(
          apiToken: _apiTokenController.text.trim(),
        ),
      );
      if (!mounted) return;

      _syncControllers(resolved.company);
      _syncSequenceControllers(resolved.sequences);
      setState(() {
        _storeResolvedConfig(resolved);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Secuencias sugeridas E31, E32 y E34 creadas. Complete el límite autorizado para facturar.',
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
    final scrollController = ScrollController();
    try {
      final latestSequences = await _sequenceRepository.listLocal();
      final latestInvoices =
          await FacturaElectronicaRepository.loadRecentResolved(limit: 18);
      if (!mounted) return;
      _syncSequenceControllers(latestSequences);
      setState(() {
        _sequences = latestSequences;
        _recentInvoices = latestInvoices;
      });

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
                              controller: scrollController,
                              child: ListView.separated(
                                controller: scrollController,
                                itemCount: _recentInvoices.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final invoice = _recentInvoices[index];
                                  final statusDetail = (() {
                                    final isRejected =
                                        invoice.estadoDgii ==
                                        FacturaElectronicaModel.statusRejected;
                                    final isSendError =
                                        invoice.estadoDgii ==
                                        FacturaElectronicaModel.statusSendError;
                                    if (!isRejected && !isSendError) {
                                      return null;
                                    }

                                    final code = (invoice.codigoDgii ?? '')
                                        .trim();
                                    final message = (invoice.mensajeDgii ?? '')
                                        .trim();
                                    if (code.isEmpty && message.isEmpty) {
                                      return null;
                                    }
                                    if (code.isEmpty) return message;
                                    if (message.isEmpty) return code;
                                    return '$code - $message';
                                  })();
                                  return _DocumentTableRow(
                                    number: invoice.numeroDocumento.trim(),
                                    type: invoice.tipoDescriptivoResuelto,
                                    secondaryType: _documentTypeLabel(
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
                                    statusDetail: statusDetail,
                                    onViewStatusDetail:
                                        statusDetail?.trim().isNotEmpty == true
                                        ? () => _showStatusDetailDialog(
                                            invoice.statusLabel,
                                            statusDetail!,
                                          )
                                        : null,
                                    statusColor: _statusColor(
                                      invoice.estadoDgii,
                                    ),
                                    accentColor: _documentAccentColor(
                                      context,
                                      invoice,
                                    ),
                                    amount: CurrencyDisplay.format(
                                      invoice.montoTotal,
                                      symbol: 'RD\$',
                                    ),
                                    reference:
                                        invoice.referenciaDocumento
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? invoice.referenciaDocumento!.trim()
                                        : null,
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
    } finally {
      scrollController.dispose();
    }
  }

  Future<void> _showStatusDetailDialog(String status, String detail) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Detalle de $status')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SelectableText(
              detail,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
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
    if (currentNumber >= endNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El límite debe ser mayor que la secuencia actual'),
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
        status: 'ACTIVE',
      );
      if (!mounted) return;
      _replaceSequence(saved);
      final refreshed = await _configRepository.loadResolvedConfig();
      if (!mounted) return;
      _syncSequenceControllers(refreshed.sequences);
      setState(() {
        _storeResolvedConfig(refreshed);
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
        return 'E31';
      case '32':
      case 'venta':
      case 'consumo':
        return 'E32';
      case '33':
        return 'Débito';
      case '34':
        return 'E34';
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
      case '34':
        return '34 - Nota de crédito';
      default:
        return '$documentTypeCode - Secuencia';
    }
  }

  Color _documentAccentColor(
    BuildContext context,
    FacturaElectronicaModel invoice,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (invoice.isCreditNote) {
      return scheme.tertiary;
    }
    return scheme.primary;
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
    final readiness = _effectiveReadiness();
    final scheme = Theme.of(context).colorScheme;
    switch (readiness.status) {
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
    final BusinessSettings businessSettings =
        widget.businessSettingsOverride ?? ref.watch(businessSettingsProvider);
    final bool isDebug = kDebugMode;
    // Runtime gate: keep this section hidden for clients while still compiling
    // the original implementation (avoids stale/unused warnings).
    final bool showConstructionOnly = DateTime.now().millisecondsSinceEpoch >=
        0;

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
          actions: showConstructionOnly
              ? const []
              : [
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
        body: showConstructionOnly
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.construction_outlined),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Esta sección está en construcción',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isDebug
                                ? 'Modo DEBUG: por ahora no se muestra la configuración de Facturación Electrónica.'
                                : 'Modo PRODUCCIÓN: esta sección está temporalmente oculta para evitar confusión al cliente.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  return SettingsLayout.pageFrame(
                    constraints,
                    max: 1500,
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
      cacheExtent: 2400,
      children: [
        _buildModeSelector(context),
        const SizedBox(height: 10),
        if (_showCertificationSection)
          _buildCertificationSection(context)
        else ...[
          _buildHeroSection(context, businessSettings: businessSettings),
          const SizedBox(height: 10),
          _buildDiagnosticsSection(context, businessSettings),
          const SizedBox(height: 10),
          _buildSequencesSection(context),
        ],
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('Configuracion normal'),
            icon: Icon(Icons.tune_outlined),
          ),
          ButtonSegment(
            value: true,
            label: Text('Certificacion DGII'),
            icon: Icon(Icons.assignment_turned_in_outlined),
          ),
        ],
        selected: {_showCertificationSection},
        onSelectionChanged: (selection) {
          final next = selection.first;
          setState(() => _showCertificationSection = next);
          if (next && _certificationBatches.isEmpty) {
            _refreshCertificationBatches();
          }
        },
      ),
    );
  }

  Widget _buildCertificationSection(BuildContext context) {
    final theme = Theme.of(context);
    final selectedBatch = _selectedCertificationBatch;
    final summary = _certificationSummary;
    final diagnostics = _certificationDiagnostics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Certificacion DGII',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Importa el archivo Excel de pruebas descargado desde DGII para preparar los casos ECF y RFCE de esta empresa.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _importingCertificationExcel
                        ? null
                        : _pickAndImportCertificationExcel,
                    icon: _importingCertificationExcel
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: const Text('Importar Excel DGII'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadingCertification
                        ? null
                        : _refreshCertificationBatches,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Actualizar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _generatingBatchXml
                        ? null
                        : _generateCertificationBatchXml,
                    icon: _generatingBatchXml
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.code_outlined),
                    label: const Text('Generar XML de todos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _resettingBatchXml
                        ? null
                        : _resetCertificationBatchXml,
                    icon: _resettingBatchXml
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Limpiar XML del lote'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _signingBatchXml
                        ? null
                        : _signCertificationBatch,
                    icon: _signingBatchXml
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.draw_outlined),
                    label: const Text('Firmar todos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _preflightingBatch
                        ? null
                        : _preflightCertificationBatch,
                    icon: _preflightingBatch
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.rule_outlined),
                    label: const Text('Verificar antes de enviar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _auditingBatch
                        ? null
                        : () => _auditCertificationBatch(),
                    icon: _auditingBatch
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_outlined),
                    label: const Text('Auditar lote'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _aiAuditingBatch
                        ? null
                        : () => _auditCertificationBatch(ai: true),
                    icon: _aiAuditingBatch
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Auditar lote con IA'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _aiSuggestingFixBatch
                        ? null
                        : _suggestCertificationFixBatch,
                    icon: _aiSuggestingFixBatch
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('Sugerir correcciones lote con IA'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        selectedBatch == null || _reprocessingAndSendingBatch
                        ? null
                        : _reprocessAndSendCertificationBatch,
                    icon: _reprocessingAndSendingBatch
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('Reprocesar y enviar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadingDgiiSeed
                        ? null
                        : _downloadDgiiManualSeed,
                    icon: _downloadingDgiiSeed
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.key_outlined),
                    label: const Text('Descargar semilla DGII'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _uploadingDgiiSignedSeed
                        ? null
                        : _uploadDgiiManualSignedSeed,
                    icon: _uploadingDgiiSignedSeed
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_outlined),
                    label: const Text('Subir semilla firmada'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        selectedBatch == null ||
                            _sendingBatchXml ||
                            diagnostics?.canSubmitToDgii != true ||
                            !_hasCertificationCasesReadyToSend()
                        ? null
                        : _sendCertificationBatch,
                    icon: _sendingBatchXml
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: const Text('Enviar todos firmados'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedBatch == null || _queryingBatchResults
                        ? null
                        : _queryCertificationBatchResults,
                    icon: _queryingBatchResults
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check_outlined),
                    label: const Text('Consultar todos'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 820;
                  final apiKeyField = TextFormField(
                    controller: _aiApiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'API key IA para auditoría',
                      hintText: 'sk-...',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  );
                  final modelField = TextFormField(
                    controller: _aiModelController,
                    decoration: const InputDecoration(
                      labelText: 'Modelo IA',
                      prefixIcon: Icon(Icons.memory_outlined),
                    ),
                  );
                  if (stacked) {
                    return Column(
                      children: [
                        apiKeyField,
                        const SizedBox(height: 8),
                        modelField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: apiKeyField),
                      const SizedBox(width: 8),
                      SizedBox(width: 180, child: modelField),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'Diagnostico de certificacion',
          child: _buildCertificationDiagnosticsCard(context, diagnostics),
        ),
        const SizedBox(height: 10),
        if (selectedBatch != null && summary != null) ...[
          _SectionCard(
            title: 'Progreso del lote',
            child: _buildCertificationDashboard(context, summary),
          ),
          const SizedBox(height: 10),
        ],
        _SectionCard(
          title: 'Lotes importados',
          child: _certificationBatches.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Aun no has importado el archivo de pruebas DGII. Descargalo desde el portal de certificacion e importalo aqui.',
                  ),
                )
              : Column(
                  children: _certificationBatches
                      .map(
                        (batch) => _CertificationBatchTile(
                          batch: batch,
                          selected: batch.id == selectedBatch?.id,
                          onTap: () => _loadCertificationCases(batch),
                          onDelete: () => _deleteCertificationBatch(batch),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'Casos del lote',
          child: selectedBatch == null
              ? const Text('Seleccione un lote importado para ver sus casos.')
              : _loadingCertification
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _certificationCases.isEmpty
              ? const Text('No se detectaron casos en este lote.')
              : _buildCertificationCasesList(context),
        ),
      ],
    );
  }

  Widget _buildCertificationDiagnosticsCard(
    BuildContext context,
    DgiiCertificationDiagnosticsModel? diagnostics,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (diagnostics == null) {
      return const Text('Actualiza para consultar el diagnostico del backend.');
    }
    final migrationOk = diagnostics.databaseHasNewFields == true;
    final batchPreflight = _certificationBatchPreflight;
    final summary = _certificationSummary;
    final signedCasesCount = diagnostics.signedCasesCount > 0
        ? diagnostics.signedCasesCount
        : summary?.signed ?? 0;
    final totalCasesCount = diagnostics.totalCasesCount > 0
        ? diagnostics.totalCasesCount
        : summary?.totalCases ?? 0;
    final signatureOk =
        signedCasesCount > 0 &&
        diagnostics.signingEngineAvailable &&
        diagnostics.certificateConfigured;
    final endpointBlockers = diagnostics.submitBlockers
        .where(
          (item) =>
              item.contains('ENDPOINT') ||
              item.contains('RECEPCION') ||
              item.contains('SUBMIT') ||
              item.contains('RESULT'),
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InlineMetaPill(
              label: 'Migracion DB',
              value: migrationOk
                  ? 'Aplicada'
                  : diagnostics.databaseHasNewFields == null
                  ? 'No verificable'
                  : 'Pendiente',
            ),
            _InlineMetaPill(
              label: 'XSD disponibles',
              value: '${diagnostics.xsdFilesFound}',
            ),
            _InlineMetaPill(
              label: 'Motor XSD',
              value: diagnostics.xsdValidationEngineAvailable ? 'Si' : 'No',
            ),
            _InlineMetaPill(
              label: 'RFCE disponible',
              value: diagnostics.rfceGenerationAvailable ? 'Si' : 'No',
            ),
            _InlineMetaPill(
              label: 'Listo para enviar DGII',
              value: diagnostics.canSubmitToDgii ? 'Si' : 'No',
            ),
            _InlineMetaPill(
              label: 'Firmados',
              value: '$signedCasesCount/$totalCasesCount',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _DiagnosticLine(label: 'DB', value: migrationOk ? '✅' : '❌'),
            _DiagnosticLine(
              label: 'XSD',
              value:
                  diagnostics.xsdFilesFound > 0 &&
                      diagnostics.xsdValidationEngineAvailable
                  ? '✅'
                  : '❌',
            ),
            _DiagnosticLine(label: 'Firma', value: signatureOk ? '✅' : '❌'),
            _DiagnosticLine(
              label: 'Endpoint',
              value: diagnostics.dgiiEndpointConfigExists ? '✅' : '❌',
            ),
            _DiagnosticLine(
              label: 'Token/Auth',
              value:
                  diagnostics.dgiiAuthConfigExists &&
                      diagnostics.dgiiAuthLastErrorCode == null &&
                      diagnostics.dgiiAuthLastErrorMessage == null
                  ? '✅'
                  : '❌',
            ),
            _DiagnosticLine(
              label: 'Certificado',
              value: diagnostics.activeCertificateExists ? '✅' : '❌',
            ),
          ],
        ),
        if (batchPreflight != null) ...[
          const SizedBox(height: 10),
          Text(
            'Preflight: ${batchPreflight.readyToSend}/${batchPreflight.total} listo(s), ${batchPreflight.blocked} bloqueado(s)',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
        if (!diagnostics.dgiiEndpointConfigExists &&
            endpointBlockers.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DiagnosticNotice(
            color: Colors.orange,
            text: 'Endpoint pendiente: ${endpointBlockers.join(', ')}',
          ),
        ],
        if (!diagnostics.canSubmitToDgii &&
            diagnostics.submitBlockers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Bloqueos para envio DGII',
            style: TextStyle(
              color: scheme.error,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          ...diagnostics.submitBlockers.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '- $item',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        if (diagnostics.dgiiAuthLastErrorMessage?.trim().isNotEmpty ==
            true) ...[
          const SizedBox(height: 10),
          _DiagnosticNotice(
            color: Colors.orange,
            text:
                'Ultimo error Token/Auth: ${diagnostics.dgiiAuthLastErrorCode ?? 'DGII_AUTH'} - ${diagnostics.dgiiAuthLastErrorMessage}',
          ),
        ],
        if (diagnostics.lastSigningError?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 10),
          _DiagnosticNotice(
            color: Colors.orange,
            text: 'Ultimo error de firma: ${diagnostics.lastSigningError}',
          ),
        ],
        if (diagnostics.hasMigrationWarning) ...[
          const SizedBox(height: 10),
          _DiagnosticNotice(
            color: scheme.error,
            text: diagnostics.pendingMigrationWarning?.trim().isNotEmpty == true
                ? diagnostics.pendingMigrationWarning!
                : 'La migración de certificación DGII no está aplicada en la base de datos real.',
          ),
        ],
        if (diagnostics.xsdFilesFound == 0) ...[
          const SizedBox(height: 10),
          _DiagnosticNotice(
            color: Colors.orange,
            text:
                'No hay archivos XSD oficiales en resources/dgii/xsd. La validacion XSD seguira como XSD_NOT_AVAILABLE.',
          ),
        ],
      ],
    );
  }

  Widget _buildCertificationDashboard(
    BuildContext context,
    DgiiCertificationBatchSummary summary,
  ) {
    final value = (summary.progressPercentage.clamp(0, 100)) / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InlineMetaPill(
              label: 'Total casos',
              value: '${summary.totalCases}',
            ),
            _InlineMetaPill(
              label: 'XML generados',
              value: '${summary.xmlGenerated}',
            ),
            _InlineMetaPill(label: 'Firmados', value: '${summary.signed}'),
            _InlineMetaPill(label: 'Enviados', value: '${summary.sent}'),
            _InlineMetaPill(label: 'Aceptados', value: '${summary.accepted}'),
            _InlineMetaPill(label: 'Rechazados', value: '${summary.rejected}'),
            _InlineMetaPill(
              label: 'En proceso',
              value: '${summary.processing}',
            ),
            _InlineMetaPill(label: 'Errores', value: '${summary.error}'),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: value),
        const SizedBox(height: 8),
        Text(
          'Importado -> XML -> Firmado -> Enviado -> Resultado',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          _certificationNextAction(summary),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  String _certificationNextAction(DgiiCertificationBatchSummary summary) {
    if (summary.error > 0) return 'Revisa los errores del lote';
    if (summary.rejected > 0) return 'Revisa el motivo de rechazo';
    if (summary.imported > 0) return 'Genera los XML';
    if (summary.xmlGenerated > summary.signed) return 'Firma los XML';
    if (summary.signed > summary.sent) return 'Envia a DGII';
    if (summary.processing > 0 ||
        summary.sent >
            summary.accepted + summary.rejected + summary.acceptedConditional) {
      return 'Consulta resultados';
    }
    return 'Lote sin bloqueos pendientes';
  }

  String _certificationStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'IMPORTED':
        return 'Importado';
      case 'XML_GENERATED':
        return 'XML generado';
      case 'SIGNED':
        return 'Firmado';
      case 'SENT':
        return 'Enviado';
      case 'ACCEPTED':
        return 'Aceptado';
      case 'ACCEPTED_CONDITIONAL':
        return 'Aceptado condicional';
      case 'REJECTED':
        return 'Rechazado';
      case 'EN_PROCESO':
        return 'En proceso';
      case 'ERROR':
        return 'Error';
      default:
        return status;
    }
  }

  String _xmlValidationLabel(DgiiCertificationCaseModel item) {
    switch ((item.xmlValidationStatus ?? 'NOT_VALIDATED').toUpperCase()) {
      case 'XML_INVALID':
        return 'XML invalido';
      case 'XSD_NOT_AVAILABLE':
        return 'XSD no disponible';
      case 'XSD_VALID':
        return 'XSD valido';
      case 'XSD_INVALID':
        return 'XSD invalido';
      case 'XML_VALID':
        return 'XML valido';
      default:
        return 'Sin validar';
    }
  }

  String _formatCompactJson(Map<String, dynamic> value) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  }

  bool _certificationXmlCanBeSigned(DgiiCertificationCaseModel item) {
    final status = (item.xmlValidationStatus ?? '').toUpperCase();
    return item.xmlGenerated?.trim().isNotEmpty == true &&
        status != 'XML_INVALID' &&
        status != 'XSD_INVALID' &&
        status != 'NOT_VALIDATED';
  }

  Future<void> _showCertificationValidationErrors(
    DgiiCertificationCaseModel item,
  ) async {
    final errors = item.xmlValidationErrors;
    final warnings = item.xmlValidationWarnings;
    final rawOutput = item.effectiveRawXmllintOutput;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Validacion XML'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              [
                'Estado: ${_xmlValidationLabel(item)}',
                'XSD usado: ${item.effectiveXsdFileUsed ?? 'N/D'}',
                if (item.parsedXsdElementHint?.trim().isNotEmpty == true)
                  '\nElemento XSD:',
                if (item.parsedXsdElementHint?.trim().isNotEmpty == true)
                  item.parsedXsdElementHint!,
                if (errors.isNotEmpty) '\nErrores:',
                ...errors.map((value) => '- $value'),
                if (rawOutput?.trim().isNotEmpty == true) '\nSalida xmllint:',
                if (rawOutput?.trim().isNotEmpty == true) rawOutput!,
                if (warnings.isNotEmpty) '\nAdvertencias:',
                ...warnings.map((value) => '- $value'),
                if (errors.isEmpty && warnings.isEmpty)
                  'Sin errores registrados.',
              ].join('\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCertificationXsdError(
    DgiiCertificationCaseModel item,
  ) async {
    final text = [
      'eNCF: ${item.encf ?? 'N/D'}',
      'Tipo e-CF: ${item.tipoEcf ?? 'N/D'}',
      'Hoja: ${item.sheetName}',
      'Estado validacion: ${_xmlValidationLabel(item)}',
      'XSD usado: ${item.effectiveXsdFileUsed ?? 'N/D'}',
      if (item.parsedXsdElementHint?.trim().isNotEmpty == true)
        '\n${item.parsedXsdElementHint}',
      if (item.effectiveRawXmllintOutput?.trim().isNotEmpty == true)
        '\n${item.effectiveRawXmllintOutput}',
      if (item.xmlValidationErrors.isNotEmpty)
        '\nErrores:\n${item.xmlValidationErrors.map((value) => '- $value').join('\n')}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Error XSD copiado')));
  }

  Future<void> _showCertificationPreflight(
    DgiiCertificationCasePreflightModel preflight,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preflight DGII'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              [
                'Listo para enviar: ${preflight.canSend ? 'Si' : 'No'}',
                'Endpoint: ${preflight.endpointType ?? 'N/D'} ${preflight.endpointUrlMasked ?? ''}'
                    .trim(),
                'Certificado: ${preflight.certificateStatus ?? 'N/D'}',
                'XML: ${preflight.xmlValidationStatus ?? 'N/D'}',
                'Firma: ${preflight.signatureStatus ?? 'N/D'}',
                if (preflight.blockers.isNotEmpty) '\nBloqueos:',
                ...preflight.blockers.map((value) => '- $value'),
                if (preflight.warnings.isNotEmpty) '\nAdvertencias:',
                ...preflight.warnings.map((value) => '- $value'),
              ].join('\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Color _certificationStatusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
        return Colors.green;
      case 'ACCEPTED_CONDITIONAL':
        return Colors.teal;
      case 'REJECTED':
      case 'ERROR':
        return scheme.error;
      case 'SENT':
      case 'EN_PROCESO':
        return Colors.orange;
      case 'SIGNED':
        return Colors.indigo;
      case 'XML_GENERATED':
        return scheme.primary;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  List<Widget> _certificationCaseActions(DgiiCertificationCaseModel item) {
    final status = item.status.toUpperCase();
    final busyXml = _generatingCaseXmlId == item.id;
    final busyValidate = _validatingCaseXmlId == item.id;
    final busyReset = _resettingCaseXmlId == item.id;
    final busyExport = _exportingCaseXmlId == item.id;
    final busyImportSigned = _importingSignedCaseXmlId == item.id;
    final busySign = _signingCaseXmlId == item.id;
    final busySend = _sendingCaseXmlId == item.id;
    final busyQuery = _queryingCaseResultId == item.id;
    final busyPreflight = _preflightingCaseId == item.id;
    final busyAudit = _auditingCaseId == item.id;
    final busyAiAudit = _aiAuditingCaseId == item.id;
    final busyFixSuggestion = _aiSuggestingFixCaseId == item.id;
    final busyApplyFix = _applyingCertifiedFixCaseId == item.id;
    final hasXml = item.xmlGenerated?.trim().isNotEmpty == true;
    final validationStatus = (item.xmlValidationStatus ?? '').toUpperCase();
    final hasInvalidGeneratedXml =
        status == 'XML_GENERATED' &&
        (validationStatus == 'XSD_INVALID' ||
            validationStatus == 'XML_INVALID');
    final canResetGeneratedXml =
        hasXml &&
        !const <String>{'ACCEPTED', 'ACCEPTED_CONDITIONAL'}.contains(status);
    final preflight = _certificationPreflights[item.id];
    Widget iconAction({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        visualDensity: VisualDensity.compact,
      );
    }

    return [
      iconAction(
        tooltip: 'Detalle',
        icon: Icons.visibility_outlined,
        onPressed: () => _showCertificationCaseDetail(item),
      ),
      if (status == 'IMPORTED' || status == 'ERROR')
        iconAction(
          tooltip: busyXml ? 'Generando XML' : 'Generar XML',
          icon: Icons.code_outlined,
          onPressed: busyXml ? null : () => _generateCertificationCaseXml(item),
        ),
      if (hasInvalidGeneratedXml)
        iconAction(
          tooltip: busyXml ? 'Regenerando XML' : 'Regenerar XML',
          icon: Icons.refresh_outlined,
          onPressed: busyXml ? null : () => _generateCertificationCaseXml(item),
        ),
      if (canResetGeneratedXml)
        iconAction(
          tooltip: busyReset ? 'Limpiando XML' : 'Limpiar XML',
          icon: Icons.cleaning_services_outlined,
          onPressed: busyReset ? null : () => _resetCertificationCaseXml(item),
        ),
      if (hasXml)
        iconAction(
          tooltip: 'Ver XML',
          icon: Icons.article_outlined,
          onPressed: () => _showCertificationXml(item),
        ),
      if (hasXml)
        iconAction(
          tooltip: busyExport ? 'Exportando XML' : 'Exportar XML sin firmar',
          icon: Icons.file_download_outlined,
          onPressed:
              busyExport ? null : () => _exportGeneratedCertificationXml(item),
        ),
      if (hasXml &&
          !const <String>{'ACCEPTED', 'ACCEPTED_CONDITIONAL', 'REJECTED'}
              .contains(status) &&
          item.trackId?.trim().isNotEmpty != true)
        iconAction(
          tooltip: busyImportSigned
              ? 'Importando XML firmado'
              : 'Importar XML firmado DGII',
          icon: Icons.file_upload_outlined,
          onPressed: busyImportSigned
              ? null
              : () => _importManualSignedCertificationXml(item),
        ),
      if (hasXml)
        iconAction(
          tooltip: busyValidate ? 'Validando XML' : 'Validar XML',
          icon: Icons.rule_outlined,
          onPressed: busyValidate
              ? null
              : () => _validateCertificationCaseXml(item),
        ),
      if (item.xmlValidationJson != null)
        iconAction(
          tooltip: 'Ver validacion',
          icon: Icons.remove_red_eye_outlined,
          onPressed: () => _showCertificationValidationErrors(item),
        ),
      iconAction(
        tooltip: busyAudit ? 'Auditando' : 'Auditoría técnica',
        icon: Icons.search_outlined,
        onPressed: busyAudit ? null : () => _auditCertificationCase(item),
      ),
      iconAction(
        tooltip: busyAiAudit ? 'Auditando con IA' : 'Validar con IA',
        icon: Icons.auto_awesome_outlined,
        onPressed: busyAiAudit
            ? null
            : () => _auditCertificationCase(item, ai: true),
      ),
      iconAction(
        tooltip: busyFixSuggestion
            ? 'Sugiriendo corrección'
            : 'Sugerir corrección con IA',
        icon: Icons.auto_fix_high_outlined,
        onPressed: busyFixSuggestion
            ? null
            : () => _suggestCertificationFixCase(item),
      ),
      if (hasXml)
        iconAction(
          tooltip: busyApplyFix
              ? 'Aplicando corrección'
              : 'Aplicar corrección certificada',
          icon: Icons.build_circle_outlined,
          onPressed: busyApplyFix ? null : () => _applyCertifiedFix(item),
        ),
      if (item.effectiveRawXmllintOutput?.trim().isNotEmpty == true ||
          item.xmlValidationErrors.isNotEmpty ||
          item.xmlValidationStatus?.toUpperCase() == 'XSD_INVALID')
        iconAction(
          tooltip: 'Copiar error XSD',
          icon: Icons.copy_outlined,
          onPressed: () => _copyCertificationXsdError(item),
        ),
      if (status == 'XML_GENERATED')
        iconAction(
          tooltip: busySign ? 'Firmando XML' : 'Firmar XML',
          icon: Icons.draw_outlined,
          onPressed: busySign || !_certificationXmlCanBeSigned(item)
              ? null
              : () => _signCertificationCase(item),
        ),
      if (item.xmlSigned?.trim().isNotEmpty == true || status == 'SIGNED')
        iconAction(
          tooltip: 'Ver XML firmado',
          icon: Icons.verified_outlined,
          onPressed: () => _showCertificationXml(item, signed: true),
        ),
      if (item.xmlSigned?.trim().isNotEmpty == true || status == 'SIGNED')
        iconAction(
          tooltip: busyPreflight ? 'Verificando' : 'Verificar antes de enviar',
          icon: Icons.fact_check_outlined,
          onPressed: busyPreflight
              ? null
              : () => _preflightCertificationCase(item),
        ),
      if (preflight != null)
        iconAction(
          tooltip: preflight.canSend ? 'Preflight OK' : 'Ver bloqueos',
          icon: preflight.canSend
              ? Icons.check_circle_outline
              : Icons.error_outline,
          onPressed: () => _showCertificationPreflight(preflight),
        ),
      if (status == 'SIGNED')
        iconAction(
          tooltip: busySend ? 'Enviando' : 'Enviar solo este caso a DGII',
          icon: Icons.send_outlined,
          onPressed:
              busySend ||
                  preflight?.canSend == false ||
                  _certificationDiagnostics?.canSubmitToDgii != true
              ? null
              : () => _sendCertificationCase(item),
        ),
      if (status == 'SENT' || status == 'EN_PROCESO')
        iconAction(
          tooltip: busyQuery ? 'Consultando' : 'Consultar resultado',
          icon: Icons.manage_search_outlined,
          onPressed: busyQuery
              ? null
              : () => _queryCertificationCaseResult(item),
        ),
    ];
  }

  Widget _buildCertificationCasesList(BuildContext context) {
    return Column(
      children: _certificationCases
          .map(
            (item) => _CertificationCaseCard(
              item: item,
              statusLabel: _certificationStatusLabel(item.status),
              statusColor: _certificationStatusColor(context, item.status),
              validationLabel: _xmlValidationLabel(item),
              amountLabel: item.montoTotal == null
                  ? 'N/D'
                  : CurrencyDisplay.format(item.montoTotal!),
              actions: _certificationCaseActions(item),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildDiagnosticsSection(
    BuildContext context,
    BusinessSettings businessSettings,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final company = _company;
    final backendUrl =
        _backendDiagnostic?.backendUrl ??
        _dgiiAuthDiagnostic?.backendUrl ??
        CloudSyncService.instance.debugResolveCloudBaseUrl(businessSettings);
    final cloudKey = businessSettings.cloudApiKey?.trim();
    final cloudKeyExists = cloudKey != null && cloudKey.isNotEmpty;
    final backendAcceptedKey = _backendDiagnostic?.backendAcceptedKey;
    final validTo = company?.certificateValidToMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(company!.certificateValidToMs!);
    final certificateExpired =
        validTo != null && validTo.isBefore(DateTime.now());
    final dgiiAuth = _dgiiAuthDiagnostic?.dgiiAuth ?? const <String, dynamic>{};
    final dgiiConfig = _dgiiAuthDiagnostic?.config ?? const <String, dynamic>{};
    final dgiiSigner = _dgiiAuthDiagnostic?.signer ?? const <String, dynamic>{};
    final dgiiSignerContext =
        _dgiiAuthDiagnostic?.signerContext ?? const <String, dynamic>{};
    final sourceLabel = _readiness.backendValidated
        ? 'Datos validados por backend'
        : 'Fallback local/caché';
    final identityWarning = _identityWarning(businessSettings);

    return _SectionCard(
      title: 'Diagnóstico de conexión y DGII',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Use estas pruebas para separar conexión POS/backend, empresa, certificado, ambiente DGII y token.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _testingBackend ? null : _testBackendDiagnostics,
                icon: _testingBackend
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
                label: const Text('Probar backend'),
              ),
              FilledButton.tonalIcon(
                onPressed: _testingDgiiAuth ? null : _testDgiiAuthDiagnostics,
                icon: _testingDgiiAuth
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.vpn_key_outlined),
                label: const Text('Probar token DGII'),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyDiagnostics(businessSettings),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copiar diagnóstico'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DiagnosticGroup(
            title: 'Backend/runtime',
            children: [
              _DiagnosticLine(label: 'URL efectiva', value: backendUrl),
              _DiagnosticLine(
                label: 'Endpoint config',
                value: _backendDiagnostic == null
                    ? 'Sin probar en esta sesión'
                    : (_backendDiagnostic!.ok ? 'Responde OK' : 'Falló'),
              ),
              _DiagnosticLine(
                label: 'HTTP último config',
                value:
                    _backendDiagnostic?.statusCode?.toString() ??
                    'No disponible',
              ),
              _DiagnosticLine(
                label: 'Código/mensaje backend',
                value: _joinCodeMessage(
                  _backendDiagnostic?.errorCode,
                  _backendDiagnostic?.message,
                ),
              ),
              _DiagnosticLine(
                label: 'Último refresh backend',
                value: _formatDateTime(_lastBackendRefreshAt),
              ),
              _DiagnosticLine(label: 'Datos mostrados', value: sourceLabel),
              if (_backendDiagnostic != null && !_backendDiagnostic!.ok)
                _DiagnosticNotice(
                  color: scheme.error,
                  text: _backendDiagnostic!.classification,
                ),
            ],
          ),
          _DiagnosticGroup(
            title: 'Auth/llave POS',
            children: [
              _DiagnosticLine(
                label: 'x-cloud-key local',
                value: cloudKeyExists
                    ? 'Existe (${maskElectronicSecret(cloudKey)})'
                    : 'No configurada',
              ),
              _DiagnosticLine(
                label: 'Backend aceptó la llave',
                value: backendAcceptedKey == null
                    ? 'No probado'
                    : (backendAcceptedKey ? 'Sí' : 'No'),
              ),
              if (backendAcceptedKey == false)
                _DiagnosticNotice(
                  color: scheme.error,
                  text: 'La llave de conexión con el backend no fue aceptada',
                ),
            ],
          ),
          _DiagnosticGroup(
            title: 'Empresa/localizadores',
            children: [
              _DiagnosticLine(
                label: 'local companyId',
                value: _localCompanyId?.toString() ?? 'No disponible',
              ),
              _DiagnosticLine(
                label: 'cloudCompanyId',
                value:
                    businessSettings.cloudCompanyId?.trim().isNotEmpty == true
                    ? businessSettings.cloudCompanyId!.trim()
                    : 'No configurado',
              ),
              _DiagnosticLine(
                label: 'companyRnc',
                value: businessSettings.rnc?.trim().isNotEmpty == true
                    ? businessSettings.rnc!.trim()
                    : 'No configurado',
              ),
              _DiagnosticLine(
                label: 'Backend companyId',
                value:
                    _resolvedCompanySummary['companyId'] ??
                    _dgiiAuthDiagnostic?.companyResolved?['id']?.toString() ??
                    'No resuelto',
              ),
              _DiagnosticLine(
                label: 'Backend RNC/nombre',
                value:
                    '${_resolvedCompanySummary['rnc'] ?? _dgiiAuthDiagnostic?.companyResolved?['rnc'] ?? 'Sin RNC'} / ${_resolvedCompanySummary['companyName'] ?? _dgiiAuthDiagnostic?.companyResolved?['name'] ?? 'Sin nombre'}',
              ),
              if (identityWarning != null)
                _DiagnosticNotice(
                  color: scheme.tertiary,
                  text: identityWarning,
                ),
            ],
          ),
          _DiagnosticGroup(
            title: 'Certificado',
            children: [
              _DiagnosticLine(
                label: 'Existe',
                value:
                    company?.hasCertificateConfigured == true ||
                        _dgiiAuthDiagnostic?.certificate['found'] == true
                    ? 'Sí'
                    : 'No',
              ),
              _DiagnosticLine(
                label: 'Estado',
                value:
                    _dgiiAuthDiagnostic?.certificate['status']?.toString() ??
                    company?.certificateStatus ??
                    'No disponible',
              ),
              _DiagnosticLine(
                label: 'Alias',
                value:
                    _dgiiAuthDiagnostic?.certificate['alias']?.toString() ??
                    company?.certificateName ??
                    'No disponible',
              ),
              _DiagnosticLine(
                label: 'Vence',
                value:
                    _dgiiAuthDiagnostic?.certificate['validTo']?.toString() ??
                    (validTo == null
                        ? 'No disponible'
                        : DateFormat('dd/MM/yyyy').format(validTo)),
              ),
              _DiagnosticLine(
                label: 'Vencido',
                value:
                    (_dgiiAuthDiagnostic?.certificate['expired'] == true ||
                        certificateExpired)
                    ? 'Sí'
                    : 'No',
              ),
              _DiagnosticLine(
                label: 'Listo según backend',
                value:
                    _dgiiAuthDiagnostic?.certificate['ready'] == true ||
                        _readiness.checklist['certificateReady'] == true
                    ? 'Sí'
                    : 'No',
              ),
            ],
          ),
          _DiagnosticGroup(
            title: 'Responsable de firma',
            children: [
              _DiagnosticLine(
                label: 'Configurado',
                value: _boolLabel(
                  _readiness.checklist['signerConfigured'] ??
                      ((_signer.signerFullName.trim().isNotEmpty) ||
                              (dgiiSigner['signerFullName']
                                      ?.toString()
                                      .trim()
                                      .isNotEmpty ==
                                  true)
                          ? true
                          : false),
                ),
              ),
              _DiagnosticLine(
                label: 'Documento guardado',
                value: _signer.signerDocumentNumber.trim().isNotEmpty
                    ? _signer.signerDocumentNumber
                    : (dgiiSignerContext['signerDocumentMasked']?.toString() ??
                          'N/D'),
              ),
              _DiagnosticLine(
                label: 'Doc. coincide con certificado',
                value: _boolLabel(
                  _certificateComparison?.signerDocumentMatchesCertificate ??
                      dgiiSignerContext['signerDocumentMatchesCertificate'],
                ),
              ),
              _DiagnosticLine(
                label: 'Autorización DGII confirmada',
                value: _boolLabel(
                  _signer.signerAuthorizedForDgii ||
                      dgiiSigner['signerAuthorizedForDgii'] == true,
                ),
              ),
              if ((dgiiSignerContext['recommendation']
                      ?.toString()
                      .trim()
                      .isNotEmpty ??
                  false))
                _DiagnosticNotice(
                  color: scheme.tertiary,
                  text: dgiiSignerContext['recommendation'].toString(),
                ),
            ],
          ),
          _DiagnosticGroup(
            title: 'Ambiente DGII',
            children: [
              _DiagnosticLine(
                label: 'Ambiente',
                value: _environmentLabel(company?.environment ?? 'pruebas'),
              ),
              _DiagnosticLine(
                label: 'Producción bloqueada',
                value: dgiiConfig['productionBlocked'] == true
                    ? 'Sí'
                    : 'No/No aplica',
              ),
              _DiagnosticLine(
                label: 'Auth seed URL',
                value: _boolLabel(dgiiAuth['seedUrlConfigured']),
              ),
              _DiagnosticLine(
                label: 'Auth validate URL',
                value: _boolLabel(dgiiAuth['validateUrlConfigured']),
              ),
              _DiagnosticLine(
                label: 'Submit URL',
                value: _boolLabel(dgiiAuth['submitUrlConfigured']),
              ),
              _DiagnosticLine(
                label: 'Result URL',
                value: _boolLabel(dgiiAuth['resultUrlConfigured']),
              ),
              _DiagnosticLine(
                label: 'Seed / firma / validación / token',
                value:
                    '${_boolLabel(dgiiAuth['seedOk'])} / ${_boolLabel(dgiiAuth['signOk'])} / ${_boolLabel(dgiiAuth['validateOk'])} / ${_boolLabel(dgiiAuth['tokenFound'])}',
              ),
              _DiagnosticLine(
                label: 'HTTP/payload/root/firma',
                value:
                    '${dgiiAuth['httpStatus'] ?? 'N/D'} / ${dgiiAuth['payloadMode'] ?? 'N/D'} / ${dgiiAuth['rootElement'] ?? 'N/D'} / ${_boolLabel(dgiiAuth['hasSignature'])}',
              ),
              if (_dgiiAuthDiagnostic != null && !_dgiiAuthDiagnostic!.ok)
                _DiagnosticNotice(
                  color: scheme.error,
                  text: _dgiiAuthDiagnostic!.classification,
                ),
            ],
          ),
          _DiagnosticGroup(
            title: 'Secuencias backend/caché',
            children: const ['31', '32', '34']
                .map((code) {
                  final sequence = _sequenceFor(code);
                  return _DiagnosticLine(
                    label: 'E$code',
                    value: _sequenceDiagnosticSummary(sequence),
                  );
                })
                .toList(growable: false),
          ),
          _DiagnosticGroup(
            title: 'Diagnóstico reciente',
            children: [
              _DiagnosticLine(
                label: 'Última operación',
                value: _lastDiagnosticOperation,
              ),
              _DiagnosticLine(
                label: 'Último código',
                value: _lastDiagnosticErrorCode ?? 'Sin error',
              ),
              _DiagnosticLine(
                label: 'Último mensaje',
                value: _lastDiagnosticErrorMessage ?? 'Sin error',
              ),
              _DiagnosticLine(
                label: 'Última prueba exitosa',
                value: _formatDateTime(_lastSuccessfulDiagnosticAt),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context, {
    required BusinessSettings businessSettings,
  }) {
    final company = _company!;
    final readiness = _effectiveReadiness();
    final status = _systemStatus(context);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

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
          _StatusBanner(
            label: status.label,
            color: status.color,
            icon: status.icon,
          ),
          const SizedBox(height: 8),
          Text(
            readiness.backendValidated
                ? 'Estado validado con el backend para la empresa activa.'
                : 'Estado calculado con datos locales mientras se recupera la validación backend.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (readiness.messages.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              readiness.messages.first,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (readiness.missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: readiness.missing
                  .map((item) => _InlineMetaPill(label: 'Falta', value: item))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 860;
              final switchesColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Controles',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _PrimarySwitchTile(
                    label: 'Facturación electrónica',
                    value: businessSettings.electronicInvoicingEnabled,
                    dense: true,
                    onChanged: _savingVisibility
                        ? null
                        : _updateSalesVisibility,
                  ),
                  const SizedBox(height: 8),
                  _PrimarySwitchTile(
                    label: 'Enviar automáticamente a DGII',
                    value: company.automaticEmission == 1,
                    dense: true,
                    onChanged: _savingAutomaticEmission
                        ? null
                        : _updateAutomaticEmission,
                  ),
                ],
              );

              final companyPanel = _buildInlineCompanySummary(context);

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    switchesColumn,
                    const SizedBox(height: 12),
                    companyPanel,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 270, child: switchesColumn),
                  const SizedBox(width: 14),
                  Expanded(child: companyPanel),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 620;
              if (stacked) {
                return Column(
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
                      'Se crean las sugerencias E31, E32 y E34 con inicio en 1. Debe completar el límite autorizado para producción.',
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
                          'Se crean las sugerencias E31, E32 y E34 con inicio en 1. Debe completar el límite autorizado para producción.',
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
          const SizedBox(height: 12),
          _buildSignerSection(context),
          const SizedBox(height: 12),
          _buildCertificateSection(context),
        ],
      ),
    );
  }

  Widget _buildSignerSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final comparison = _certificateComparison;
    final warningCodes = comparison?.warningCodes ?? const <String>[];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Responsable de firma digital',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Debe coincidir con el titular real del certificado cargado en el backend.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final fields = [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _signerFullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _signer.signerDocumentType,
                    decoration: const InputDecoration(labelText: 'Tipo doc.'),
                    items: const [
                      DropdownMenuItem(value: 'CEDULA', child: Text('Cédula')),
                      DropdownMenuItem(
                        value: 'PASSPORT',
                        child: Text('Pasaporte'),
                      ),
                      DropdownMenuItem(value: 'RNC', child: Text('RNC')),
                      DropdownMenuItem(value: 'OTHER', child: Text('Otro')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _signer = _signer.copyWith(signerDocumentType: value);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _signerDocumentNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Número de documento',
                    ),
                  ),
                ),
              ];

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fields[0],
                    const SizedBox(height: 8),
                    fields[1],
                    const SizedBox(height: 8),
                    fields[2],
                  ],
                );
              }

              return Row(children: fields);
            },
          ),
          const SizedBox(height: 8),
          CheckboxListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Confirmo que este firmante está autorizado ante DGII',
            ),
            value: _signer.signerAuthorizedForDgii,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _signer = _signer.copyWith(signerAuthorizedForDgii: value);
              });
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _savingSigner ? null : _saveSigner,
                icon: _savingSigner
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: const Text('Guardar firmante'),
              ),
              OutlinedButton.icon(
                onPressed: comparison == null ? null : _useCertificateIdentity,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Usar datos del certificado'),
              ),
            ],
          ),
          if (comparison != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineMetaPill(
                  label: 'Nombre vs certificado',
                  value: comparison.signerNameMatchesCertificate
                      ? 'Coincide'
                      : 'No coincide',
                ),
                _InlineMetaPill(
                  label: 'Documento vs certificado',
                  value: comparison.signerDocumentMatchesCertificate
                      ? 'Coincide'
                      : 'No coincide',
                ),
                if ((comparison.certificateDocumentNumber ?? '').isNotEmpty)
                  _InlineMetaPill(
                    label: 'Doc. certificado',
                    value: comparison.certificateDocumentNumber!,
                  ),
              ],
            ),
          ],
          if (warningCodes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DiagnosticNotice(
              color: scheme.tertiary,
              text: 'Advertencias: ${warningCodes.join(', ')}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineCompanySummary(BuildContext context) {
    final missing = _companySummaryMissingFields();
    final hasMissing = missing.isNotEmpty;
    final hint = _companySummaryHint();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Empresa cargada',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (hasMissing)
                TextButton(
                  onPressed: _openCompanySettings,
                  child: const Text('Completar'),
                ),
            ],
          ),
          if (hint != null) ...[
            Text(
              hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileSummaryRow(
                      label: 'Empresa',
                      value: _resolvedCompanyName(),
                    ),
                    const SizedBox(height: 8),
                    _ProfileSummaryRow(
                      label: 'RNC',
                      value: _resolvedCompanyRnc(),
                    ),
                    const SizedBox(height: 8),
                    _ProfileSummaryRow(
                      label: 'Dirección',
                      value: _resolvedCompanyAddress(),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _ProfileSummaryRow(
                      label: 'Empresa',
                      value: _resolvedCompanyName(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _ProfileSummaryRow(
                      label: 'RNC',
                      value: _resolvedCompanyRnc(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: _ProfileSummaryRow(
                      label: 'Dirección',
                      value: _resolvedCompanyAddress(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Certificado digital y DGII',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 860;
              final certificateInfo = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusChip(
                    label: company.certificateStatus.trim() == 'active'
                        ? 'Vigente'
                        : 'No cargado',
                    color: company.certificateStatus.trim() == 'active'
                        ? scheme.primary
                        : scheme.outline,
                  ),
                  if (company.certificateName.trim().isNotEmpty)
                    _InlineMetaPill(
                      label: 'Alias',
                      value: company.certificateName.trim(),
                    ),
                  if (validTo != null)
                    _InlineMetaPill(
                      label: 'Vence',
                      value: DateFormat('dd/MM/yyyy').format(validTo),
                    ),
                ],
              );

              final uploadButton = FilledButton.icon(
                onPressed: _uploadingCertificate ? null : _pickCertificateFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  company.certificateStatus.trim() == 'active'
                      ? 'Cambiar'
                      : 'Subir',
                ),
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    uploadButton,
                    const SizedBox(height: 10),
                    certificateInfo,
                  ],
                );
              }

              return Row(
                children: [
                  uploadButton,
                  const SizedBox(width: 12),
                  Expanded(child: certificateInfo),
                ],
              );
            },
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
            FilledButton.icon(
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
          ],
          const SizedBox(height: 12),
          Text(
            'Configuración DGII',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 720;
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
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _apiTokenController,
                      decoration: const InputDecoration(
                        labelText: 'Token DGII manual (opcional)',
                        helperText:
                            'Solo para override temporal. El backend intentara autenticacion automatica con el certificado activo.',
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    flex: 2,
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
                    flex: 3,
                    child: TextFormField(
                      controller: _apiTokenController,
                      decoration: const InputDecoration(
                        labelText: 'Token DGII manual (opcional)',
                        helperText:
                            'Solo para override temporal. El backend intentara autenticacion automatica con el certificado activo.',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
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
                  fontSize: 12,
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
    final sequence34 = _sequenceFor('34');

    return _SectionCard(
      title: 'Comprobantes fiscales',
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
                statusLabel: _sequenceDraftStatusLabel('31', sequence31),
                busy: _creatingSequenceCode == '31',
                color: _sequenceStatusColor(context, sequence31),
                onPressed: () => _submitSequence('31'),
                helperMessage: _sequenceHelperMessage(sequence31),
                stateHint: _sequenceStateHint('31', sequence31),
                limitLabel: sequence31.endNumber?.toString() ?? 'Pendiente',
                onDraftChanged: _refreshSequenceDraftUi,
              );
              final second = _SequenceSetupCard(
                title: '32 - Consumo',
                prefixController: _sequencePrefixControllers['32']!,
                startController: _sequenceStartControllers['32']!,
                numberController: _sequenceNumberControllers['32']!,
                endController: _sequenceEndControllers['32']!,
                sequence: sequence32,
                statusLabel: _sequenceDraftStatusLabel('32', sequence32),
                busy: _creatingSequenceCode == '32',
                color: _sequenceStatusColor(context, sequence32),
                onPressed: () => _submitSequence('32'),
                helperMessage: _sequenceHelperMessage(sequence32),
                stateHint: _sequenceStateHint('32', sequence32),
                limitLabel: sequence32.endNumber?.toString() ?? 'Pendiente',
                onDraftChanged: _refreshSequenceDraftUi,
              );
              final third = _SequenceSetupCard(
                title: '34 - Nota de crédito',
                prefixController: _sequencePrefixControllers['34']!,
                startController: _sequenceStartControllers['34']!,
                numberController: _sequenceNumberControllers['34']!,
                endController: _sequenceEndControllers['34']!,
                sequence: sequence34,
                statusLabel: _sequenceDraftStatusLabel('34', sequence34),
                busy: _creatingSequenceCode == '34',
                color: _sequenceStatusColor(context, sequence34),
                onPressed: () => _submitSequence('34'),
                helperMessage: _sequenceHelperMessage(sequence34),
                stateHint: _sequenceStateHint('34', sequence34),
                limitLabel: sequence34.endNumber?.toString() ?? 'Pendiente',
                onDraftChanged: _refreshSequenceDraftUi,
              );

              if (stacked) {
                return Column(
                  children: [
                    first,
                    const SizedBox(height: 10),
                    second,
                    const SizedBox(height: 10),
                    third,
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: first),
                      const SizedBox(width: 10),
                      Expanded(child: second),
                    ],
                  ),
                  const SizedBox(height: 10),
                  third,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  ElectronicSequenceModel? _buildSequenceDraft(String documentTypeCode) {
    final prefix =
        _sequencePrefixControllers[documentTypeCode]?.text
            .trim()
            .toUpperCase() ??
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
      status: 'ACTIVE',
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'No disponible';
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(value);
  }

  String _joinCodeMessage(String? code, String? message) {
    final normalizedCode = code?.trim() ?? '';
    final normalizedMessage = message?.trim() ?? '';
    if (normalizedCode.isEmpty && normalizedMessage.isEmpty) {
      return 'Sin error';
    }
    if (normalizedCode.isEmpty) return normalizedMessage;
    if (normalizedMessage.isEmpty) return normalizedCode;
    return '$normalizedCode - $normalizedMessage';
  }

  String _boolLabel(Object? value) {
    if (value == true) return 'Sí';
    if (value == false) return 'No';
    return 'N/D';
  }

  String _environmentLabel(String value) {
    return value.trim().toLowerCase() == 'produccion'
        ? 'production'
        : 'precertification';
  }

  String? _identityWarning(BusinessSettings settings) {
    final backendRnc = (_resolvedCompanySummary['rnc'] ?? '').trim();
    final localRnc = (settings.rnc ?? '').trim();
    final backendCloudId = (_resolvedCompanySummary['companyCloudId'] ?? '')
        .trim();
    final localCloudId = (settings.cloudCompanyId ?? '').trim();
    if (backendRnc.isNotEmpty &&
        localRnc.isNotEmpty &&
        backendRnc != localRnc) {
      return 'El RNC local no coincide con el RNC resuelto por backend.';
    }
    if (backendCloudId.isNotEmpty &&
        localCloudId.isNotEmpty &&
        backendCloudId != localCloudId) {
      return 'El cloudCompanyId local no coincide con el backend.';
    }
    if (!_readiness.backendValidated) {
      return 'La pantalla está usando caché local; confirme con Probar backend.';
    }
    return null;
  }

  String _sequenceDiagnosticSummary(ElectronicSequenceModel sequence) {
    final end = sequence.endNumber;
    final remaining = end == null ? null : end - sequence.currentNumber;
    final issues = <String>[];
    if (sequence.status.trim().toUpperCase() != 'ACTIVE') {
      issues.add('inactiva');
    }
    if (end == null) {
      issues.add('sin límite');
    } else if (remaining != null && remaining <= 0) {
      issues.add('agotada');
    }
    final base =
        '${sequence.statusLabel}, actual ${sequence.currentNumber}, límite ${end ?? 'N/D'}, restantes ${remaining ?? 'N/D'}';
    if (issues.isEmpty) return base;
    return '$base — advertencia: ${issues.join(', ')}';
  }

  String _buildDiagnosticCopyText(BusinessSettings settings) {
    final buffer = StringBuffer()
      ..writeln('Diagnóstico Facturación Electrónica FULLPOS')
      ..writeln('Timestamp: ${DateTime.now().toIso8601String()}')
      ..writeln(
        'Backend URL: ${_backendDiagnostic?.backendUrl ?? _dgiiAuthDiagnostic?.backendUrl ?? CloudSyncService.instance.debugResolveCloudBaseUrl(settings)}',
      )
      ..writeln('Request backend: ${_backendDiagnostic?.requestId ?? 'N/D'}')
      ..writeln('Request DGII: ${_dgiiAuthDiagnostic?.requestId ?? 'N/D'}')
      ..writeln(
        'Datos: ${_readiness.backendValidated ? 'backend validado' : 'fallback local/caché'}',
      )
      ..writeln(
        'x-cloud-key: ${(settings.cloudApiKey?.trim().isNotEmpty ?? false) ? maskElectronicSecret(settings.cloudApiKey) : 'No configurada'}',
      )
      ..writeln('localCompanyId: ${_localCompanyId ?? 'N/D'}')
      ..writeln(
        'companyRnc: ${settings.rnc?.trim().isNotEmpty == true ? settings.rnc!.trim() : 'N/D'}',
      )
      ..writeln(
        'cloudCompanyId: ${settings.cloudCompanyId?.trim().isNotEmpty == true ? settings.cloudCompanyId!.trim() : 'N/D'}',
      )
      ..writeln(
        'Backend companyId: ${_resolvedCompanySummary['companyId'] ?? _dgiiAuthDiagnostic?.companyResolved?['id'] ?? 'N/D'}',
      )
      ..writeln(
        'Backend empresa/RNC: ${_resolvedCompanySummary['companyName'] ?? _dgiiAuthDiagnostic?.companyResolved?['name'] ?? 'N/D'} / ${_resolvedCompanySummary['rnc'] ?? _dgiiAuthDiagnostic?.companyResolved?['rnc'] ?? 'N/D'}',
      )
      ..writeln(
        'Config active/outbound: ${_readiness.checklist['configActive'] ?? 'N/D'} / ${_readiness.checklist['outboundEnabled'] ?? 'N/D'}',
      )
      ..writeln(
        'Readiness: ${_readiness.status} missing=${_readiness.missing.join(',')}',
      )
      ..writeln(
        'Firmante: nombre=${_signer.signerFullName.isEmpty ? 'N/D' : _signer.signerFullName} doc=${_signer.signerDocumentNumber.isEmpty ? 'N/D' : _signer.signerDocumentNumber} autorizadoDGII=${_signer.signerAuthorizedForDgii}',
      )
      ..writeln(
        'Firmante vs certificado: nombre=${_certificateComparison?.signerNameMatchesCertificate ?? 'N/D'} doc=${_certificateComparison?.signerDocumentMatchesCertificate ?? 'N/D'}',
      )
      ..writeln(
        'Certificado: ${_company?.certificateStatus ?? 'N/D'} alias=${_company?.certificateName ?? 'N/D'} vence=${_company?.certificateValidToMs == null ? 'N/D' : DateTime.fromMillisecondsSinceEpoch(_company!.certificateValidToMs!).toIso8601String()}',
      )
      ..writeln(
        'DGII auth: ok=${_dgiiAuthDiagnostic?.ok ?? 'N/D'} seed=${_dgiiAuthDiagnostic?.dgiiAuth['seedOk'] ?? 'N/D'} sign=${_dgiiAuthDiagnostic?.dgiiAuth['signOk'] ?? 'N/D'} validate=${_dgiiAuthDiagnostic?.dgiiAuth['validateOk'] ?? 'N/D'} token=${_dgiiAuthDiagnostic?.dgiiAuth['tokenFound'] ?? 'N/D'}',
      )
      ..writeln(
        'DGII env URLs: seed=${_dgiiAuthDiagnostic?.dgiiAuth['seedUrlConfigured'] ?? 'N/D'} validate=${_dgiiAuthDiagnostic?.dgiiAuth['validateUrlConfigured'] ?? 'N/D'} submit=${_dgiiAuthDiagnostic?.dgiiAuth['submitUrlConfigured'] ?? 'N/D'} result=${_dgiiAuthDiagnostic?.dgiiAuth['resultUrlConfigured'] ?? 'N/D'}',
      )
      ..writeln(
        'DGII safe error: ${_joinCodeMessage(_dgiiAuthDiagnostic?.errorCode, _dgiiAuthDiagnostic?.message)}',
      )
      ..writeln('Secuencias:');
    for (final code in const ['31', '32', '34']) {
      buffer.writeln(
        '  E$code: ${_sequenceDiagnosticSummary(_sequenceFor(code))}',
      );
    }
    buffer
      ..writeln('Última operación: $_lastDiagnosticOperation')
      ..writeln(
        'Último error: ${_joinCodeMessage(_lastDiagnosticErrorCode, _lastDiagnosticErrorMessage)}',
      );
    return buffer.toString();
  }

  ElectronicInvoicingReadiness _effectiveReadiness() {
    return _readiness;
  }
}

class _DiagnosticGroup extends StatelessWidget {
  const _DiagnosticGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: scheme.onSurface, fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value.trim().isEmpty ? 'N/D' : value.trim(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticNotice extends StatelessWidget {
  const _DiagnosticNotice({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
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
  const _SectionCard({this.title, required this.child});

  final String? title;
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
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

class _CertificationBatchTile extends StatelessWidget {
  const _CertificationBatchTile({
    required this.batch,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final DgiiCertificationBatchModel batch;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uploaded = DateFormat('dd/MM/yyyy HH:mm').format(batch.uploadedAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withOpacity(0.35)
            : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? scheme.primary.withOpacity(0.45)
              : scheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          batch.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '$uploaded | total ${batch.totalCases} | ECF ${batch.ecfCases} | RFCE ${batch.rfceCases} | ${batch.status}',
        ),
        trailing: IconButton(
          tooltip: 'Eliminar lote',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _CertificationCaseCard extends StatefulWidget {
  const _CertificationCaseCard({
    required this.item,
    required this.statusLabel,
    required this.statusColor,
    required this.validationLabel,
    required this.amountLabel,
    required this.actions,
  });

  final DgiiCertificationCaseModel item;
  final String statusLabel;
  final Color statusColor;
  final String validationLabel;
  final String amountLabel;
  final List<Widget> actions;

  @override
  State<_CertificationCaseCard> createState() => _CertificationCaseCardState();
}

class _CertificationCaseCardState extends State<_CertificationCaseCard> {
  final ScrollController _actionsScrollController = ScrollController();

  @override
  void dispose() {
    _actionsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final xsdError = widget.item.effectiveRawXmllintOutput;
    final hint = widget.item.parsedXsdElementHint;
    final missingFieldsText = widget.item.missingXmlFields.isEmpty
        ? null
        : 'Campos faltantes: ${widget.item.missingXmlFields.join(', ')}';
    final generationMessage =
        missingFieldsText ?? widget.item.xmlGenerationHumanMessage?.trim();
    final inlineIssue = generationMessage?.isNotEmpty == true
        ? generationMessage
        : hint?.trim().isNotEmpty == true
        ? hint
        : xsdError?.trim().isNotEmpty == true
        ? xsdError!.replaceAll(RegExp(r'\s+'), ' ')
        : null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth < 1240 ? 1240 : constraints.maxWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: 155,
                    child: Text(
                      widget.item.encf?.trim().isNotEmpty == true
                          ? widget.item.encf!
                          : 'Sin eNCF',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _InlineMetaPill(
                    label: 'tipo',
                    value: widget.item.tipoEcf ?? 'N/D',
                  ),
                  const SizedBox(width: 6),
                  _InlineMetaPill(label: 'hoja', value: widget.item.sheetName),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 135,
                    child: _InlineMetaPill(
                      label: 'monto',
                      value: widget.amountLabel,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: widget.statusLabel,
                    color: widget.statusColor,
                  ),
                  const SizedBox(width: 6),
                  _InlineMetaPill(
                    label: 'validacion',
                    value: widget.validationLabel,
                  ),
                  const SizedBox(width: 8),
                  if (inlineIssue?.trim().isNotEmpty == true)
                    Expanded(
                      child: Container(
                        height: 30,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          inlineIssue!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 390,
                    child: Scrollbar(
                      controller: _actionsScrollController,
                      child: SingleChildScrollView(
                        controller: _actionsScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.actions,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PrimarySwitchTile extends StatelessWidget {
  const _PrimarySwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 16,
        vertical: dense ? 8 : 16,
      ),
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
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: dense ? 12.5 : 15,
              ),
            ),
          ),
          Transform.scale(
            scale: dense ? 0.72 : 1,
            child: Switch.adaptive(value: value, onChanged: onChanged),
          ),
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
    required this.statusLabel,
    required this.busy,
    required this.color,
    required this.onPressed,
    required this.helperMessage,
    required this.stateHint,
    required this.limitLabel,
    required this.onDraftChanged,
  });

  final String title;
  final TextEditingController prefixController;
  final TextEditingController startController;
  final TextEditingController numberController;
  final TextEditingController endController;
  final ElectronicSequenceModel sequence;
  final String statusLabel;
  final bool busy;
  final Color color;
  final VoidCallback onPressed;
  final String helperMessage;
  final String stateHint;
  final String limitLabel;
  final VoidCallback onDraftChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    _StatusChip(label: statusLabel, color: color),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InlineMetaPill(label: 'Tipo', value: title),
                    _InlineMetaPill(label: 'Prefijo', value: sequence.prefix),
                    _InlineMetaPill(
                      label: 'Actual',
                      value: sequence.currentNumber.toString(),
                    ),
                    _InlineMetaPill(label: 'Límite', value: limitLabel),
                    _InlineMetaPill(
                      label: 'Guardado',
                      value: sequence.statusLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  stateHint,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: prefixController,
                        onChanged: (_) => onDraftChanged(),
                        decoration: const InputDecoration(labelText: 'Prefijo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: startController,
                        onChanged: (_) => onDraftChanged(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Inicial'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: numberController,
                        onChanged: (_) => onDraftChanged(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Actual'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: endController,
                        onChanged: (_) => onDraftChanged(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Límite'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  helperMessage,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 8),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _StatusChip(label: statusLabel, color: color),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _InlineMetaPill(label: 'Tipo', value: title),
                  _InlineMetaPill(label: 'Prefijo', value: sequence.prefix),
                  _InlineMetaPill(
                    label: 'Actual',
                    value: sequence.currentNumber.toString(),
                  ),
                  _InlineMetaPill(label: 'Límite', value: limitLabel),
                  _InlineMetaPill(
                    label: 'Guardado',
                    value: sequence.statusLabel,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                stateHint,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: prefixController,
                      onChanged: (_) => onDraftChanged(),
                      decoration: const InputDecoration(labelText: 'Prefijo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: startController,
                      onChanged: (_) => onDraftChanged(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Inicial'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: numberController,
                      onChanged: (_) => onDraftChanged(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Actual'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: endController,
                      onChanged: (_) => onDraftChanged(),
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
                        fontSize: 11.5,
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
          _HeaderCell(flex: 3, text: 'Tipo'),
          _HeaderCell(flex: 3, text: 'Cliente'),
          _HeaderCell(flex: 2, text: 'Monto', alignEnd: true),
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
    required this.secondaryType,
    required this.client,
    required this.amount,
    required this.status,
    this.statusDetail,
    this.onViewStatusDetail,
    required this.statusColor,
    required this.accentColor,
    required this.date,
    this.reference,
  });

  final String number;
  final String type;
  final String secondaryType;
  final String client;
  final String amount;
  final String status;
  final String? statusDetail;
  final VoidCallback? onViewStatusDetail;
  final Color statusColor;
  final Color accentColor;
  final String date;
  final String? reference;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4, right: 8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    number,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  secondaryType,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (reference?.trim().isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Ref. ${reference!.trim()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _BodyCell(flex: 3, text: client),
          _BodyCell(
            flex: 2,
            text: amount,
            alignEnd: true,
            color: scheme.onSurface,
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: _StatusChip(label: status, color: statusColor),
                      ),
                      if (onViewStatusDetail != null)
                        IconButton(
                          onPressed: onViewStatusDetail,
                          tooltip: 'Ver detalle completo',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          icon: Icon(
                            Icons.visibility_outlined,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (statusDetail?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        statusDetail!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
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
    this.alignEnd = false,
    this.color,
  });

  final int flex;
  final String text;
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
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
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
