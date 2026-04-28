import 'package:file_picker/file_picker.dart';
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
import '../../facturacion_electronica/data/electronic_invoicing_diagnostics_repository.dart';
import '../../facturacion_electronica/data/electronic_invoicing_config_repository.dart';
import '../../facturacion_electronica/data/electronic_sequence_repository.dart';
import '../../facturacion_electronica/data/electronic_signer_repository.dart';
import '../../facturacion_electronica/data/factura_electronica_repository.dart';
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

  ElectronicCompanyModel? _company;
  EmpresaConfig? _empresaConfig;
  Map<String, String?> _resolvedCompanySummary = const <String, String?>{};
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
  bool _savingSigner = false;
  bool _showCertificatePassword = false;
  bool _testingBackend = false;
  bool _testingDgiiAuth = false;

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
    if (!mounted) return;

    _syncControllers(resolved.company);
    _syncSequenceControllers(resolved.sequences);
    setState(() {
      _storeResolvedConfig(resolved);
      _empresaConfig = empresaConfig;
      _localCompanyId = localCompanyId;
      _recentInvoices = invoices;
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
      cacheExtent: 2400,
      children: [
        _buildHeroSection(context, businessSettings: businessSettings),
        const SizedBox(height: 10),
        _buildDiagnosticsSection(context, businessSettings),
        const SizedBox(height: 10),
        _buildSequencesSection(context),
      ],
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
