import 'dart:convert';

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}

class DgiiCertificationBatchModel {
  const DgiiCertificationBatchModel({
    required this.id,
    required this.companyId,
    required this.fileName,
    required this.status,
    required this.totalCases,
    required this.ecfCases,
    required this.rfceCases,
    required this.uploadedAt,
    this.rnc,
  });

  final int id;
  final int companyId;
  final String? rnc;
  final String fileName;
  final String status;
  final int totalCases;
  final int ecfCases;
  final int rfceCases;
  final DateTime uploadedAt;

  factory DgiiCertificationBatchModel.fromMap(Map<String, dynamic> map) {
    return DgiiCertificationBatchModel(
      id: (map['id'] as num?)?.toInt() ?? 0,
      companyId: (map['companyId'] as num?)?.toInt() ?? 0,
      rnc: map['rnc']?.toString(),
      fileName: map['fileName']?.toString() ?? '',
      status: map['status']?.toString() ?? 'IMPORTED',
      totalCases: (map['totalCases'] as num?)?.toInt() ?? 0,
      ecfCases: (map['ecfCases'] as num?)?.toInt() ?? 0,
      rfceCases: (map['rfceCases'] as num?)?.toInt() ?? 0,
      uploadedAt:
          DateTime.tryParse(map['uploadedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class DgiiCertificationCaseModel {
  const DgiiCertificationCaseModel({
    required this.id,
    required this.batchId,
    required this.companyId,
    required this.sheetName,
    required this.rowNumber,
    required this.status,
    required this.rawRowJson,
    this.encf,
    this.tipoEcf,
    this.rncEmisor,
    this.rncComprador,
    this.fechaEmision,
    this.montoTotal,
    this.xmlGenerated,
    this.xmlSigned,
    this.trackId,
    this.dgiiStatusCode,
    this.dgiiStatusMessage,
    this.rejectionCode,
    this.rejectionMessage,
    this.dgiiRawResponseJson,
    this.xmlValidationStatus,
    this.xmlValidationJson,
    this.xsdFileUsed,
    this.rawXmllintOutput,
    this.validationErrors = const <String>[],
    this.validationWarnings = const <String>[],
    this.errorMessage,
  });

  final int id;
  final int batchId;
  final int companyId;
  final String sheetName;
  final int rowNumber;
  final String? encf;
  final String? tipoEcf;
  final String? rncEmisor;
  final String? rncComprador;
  final DateTime? fechaEmision;
  final double? montoTotal;
  final String? xmlGenerated;
  final String? xmlSigned;
  final String? trackId;
  final String? dgiiStatusCode;
  final String? dgiiStatusMessage;
  final String? rejectionCode;
  final String? rejectionMessage;
  final Map<String, dynamic>? dgiiRawResponseJson;
  final String? xmlValidationStatus;
  final Map<String, dynamic>? xmlValidationJson;
  final String? xsdFileUsed;
  final String? rawXmllintOutput;
  final List<String> validationErrors;
  final List<String> validationWarnings;
  final Map<String, dynamic> rawRowJson;
  final String status;
  final String? errorMessage;

  factory DgiiCertificationCaseModel.fromMap(Map<String, dynamic> map) {
    final raw = map['rawRowJson'];
    List<String> readStringList(String key) {
      final value = map[key];
      return value is List
          ? value.map((item) => item.toString()).toList(growable: false)
          : const <String>[];
    }

    return DgiiCertificationCaseModel(
      id: (map['id'] as num?)?.toInt() ?? 0,
      batchId: (map['batchId'] as num?)?.toInt() ?? 0,
      companyId: (map['companyId'] as num?)?.toInt() ?? 0,
      sheetName: map['sheetName']?.toString() ?? '',
      rowNumber: (map['rowNumber'] as num?)?.toInt() ?? 0,
      encf: map['encf']?.toString(),
      tipoEcf: map['tipoEcf']?.toString(),
      rncEmisor: map['rncEmisor']?.toString(),
      rncComprador: map['rncComprador']?.toString(),
      fechaEmision: DateTime.tryParse(map['fechaEmision']?.toString() ?? ''),
      montoTotal: (map['montoTotal'] as num?)?.toDouble(),
      xmlGenerated: map['xmlGenerated']?.toString(),
      xmlSigned: map['xmlSigned']?.toString(),
      trackId: _nullableText(map['trackId']),
      dgiiStatusCode: map['dgiiStatusCode']?.toString(),
      dgiiStatusMessage: map['dgiiStatusMessage']?.toString(),
      rejectionCode: map['rejectionCode']?.toString(),
      rejectionMessage: map['rejectionMessage']?.toString(),
      dgiiRawResponseJson: map['dgiiRawResponseJson'] is Map
          ? (map['dgiiRawResponseJson'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : null,
      xmlValidationStatus: map['xmlValidationStatus']?.toString(),
      xmlValidationJson: map['xmlValidationJson'] is Map
          ? (map['xmlValidationJson'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : null,
      xsdFileUsed: map['xsdFileUsed']?.toString(),
      rawXmllintOutput: map['rawXmllintOutput']?.toString(),
      validationErrors: readStringList('validationErrors'),
      validationWarnings: readStringList('validationWarnings'),
      rawRowJson: raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{},
      status: map['status']?.toString() ?? 'IMPORTED',
      errorMessage: map['errorMessage']?.toString(),
    );
  }

  String formattedRawJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(rawRowJson);
  }

  String formattedDgiiRawResponseJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(dgiiRawResponseJson ?? const <String, dynamic>{});
  }

  Map<String, dynamic> get xmlGenerationDiagnostics {
    final json = xmlValidationJson;
    if (json == null) return const <String, dynamic>{};
    final type = json['type']?.toString();
    return type == 'XML_GENERATION_REQUIRED_FIELDS'
        ? json
        : const <String, dynamic>{};
  }

  List<String> get missingXmlFields {
    final value = xmlGenerationDiagnostics['missingFields'];
    return value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
  }

  Map<String, dynamic> get extractedXmlFields {
    final value = xmlGenerationDiagnostics['extractedFields'];
    return value is Map
        ? value.map((key, item) => MapEntry(key.toString(), item))
        : const <String, dynamic>{};
  }

  List<String> get rawRowKeys {
    final value = xmlGenerationDiagnostics['rawRowKeys'];
    return value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : rawRowJson.keys.toList(growable: false);
  }

  String? get xmlGenerationHumanMessage {
    final message = xmlGenerationDiagnostics['humanReadableMessage']
        ?.toString();
    if (message?.trim().isNotEmpty == true) return message;
    return errorMessage;
  }

  List<String> get xmlValidationErrors {
    final direct = validationErrors;
    if (direct.isNotEmpty) return direct;
    final value = xmlValidationJson?['errors'];
    return value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
  }

  List<String> get xmlValidationWarnings {
    final direct = validationWarnings;
    if (direct.isNotEmpty) return direct;
    final value = xmlValidationJson?['warnings'];
    return value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
  }

  String? get effectiveXsdFileUsed {
    final direct = xsdFileUsed?.trim();
    if (direct?.isNotEmpty == true) return direct;
    return xmlValidationJson?['xsdFileUsed']?.toString();
  }

  String? get effectiveRawXmllintOutput {
    final direct = rawXmllintOutput?.trim();
    if (direct?.isNotEmpty == true) return direct;
    final raw = xmlValidationJson?['rawXmllintOutput']?.toString();
    if (raw?.trim().isNotEmpty == true) return raw;
    final xsdError = xmlValidationJson?['xsdError']?.toString();
    if (xsdError?.trim().isNotEmpty == true) return xsdError;
    final errors = xmlValidationErrors;
    return errors.isEmpty ? errorMessage : errors.join('\n');
  }

  String? get parsedXsdElementHint {
    final output = effectiveRawXmllintOutput;
    if (output == null || output.trim().isEmpty) return null;
    final expected = RegExp(r'Expected is \(([^)]+)\)').firstMatch(output);
    final unexpected = RegExp(r"Element '([^']+)'").firstMatch(output);
    final parts = <String>[];
    if (unexpected != null) {
      parts.add('Elemento reportado: ${unexpected.group(1)}');
    }
    if (expected != null) parts.add('Esperado: ${expected.group(1)}');
    return parts.isEmpty ? null : parts.join('\n');
  }
}

class DgiiCertificationAuditMismatch {
  const DgiiCertificationAuditMismatch({
    required this.field,
    this.excelExpected,
    this.xmlGenerated,
    this.calculatedFromItems,
    this.difference,
    this.severity = 'ERROR',
  });

  final String field;
  final String? excelExpected;
  final String? xmlGenerated;
  final String? calculatedFromItems;
  final String? difference;
  final String severity;

  factory DgiiCertificationAuditMismatch.fromMap(Map<String, dynamic> map) {
    return DgiiCertificationAuditMismatch(
      field: map['field']?.toString() ?? '',
      excelExpected: _nullableText(map['excelExpected']),
      xmlGenerated: _nullableText(map['xmlGenerated']),
      calculatedFromItems: _nullableText(map['calculatedFromItems']),
      difference: _nullableText(map['difference']),
      severity: map['severity']?.toString() ?? 'ERROR',
    );
  }
}

class DgiiCertificationAuditResult {
  const DgiiCertificationAuditResult({
    required this.caseId,
    required this.encf,
    required this.tipoEcf,
    required this.filename,
    required this.filenameValid,
    required this.xsdValid,
    required this.requiredFieldsPresent,
    required this.noPlaceholders,
    required this.totalsMatchExcel,
    required this.totalsMatchItems,
    required this.aptoParaEnviar,
    required this.status,
    required this.summary,
    required this.warnings,
    required this.errors,
    required this.mismatches,
    required this.excelValues,
    required this.xmlValues,
    required this.calculatedValues,
    required this.raw,
    this.ai = const <String, dynamic>{},
  });

  final int caseId;
  final String? encf;
  final String? tipoEcf;
  final String? filename;
  final bool filenameValid;
  final bool xsdValid;
  final bool requiredFieldsPresent;
  final bool noPlaceholders;
  final bool totalsMatchExcel;
  final bool totalsMatchItems;
  final bool aptoParaEnviar;
  final String status;
  final String summary;
  final List<String> warnings;
  final List<String> errors;
  final List<DgiiCertificationAuditMismatch> mismatches;
  final Map<String, dynamic> excelValues;
  final Map<String, dynamic> xmlValues;
  final Map<String, dynamic> calculatedValues;
  final Map<String, dynamic> raw;
  final Map<String, dynamic> ai;

  factory DgiiCertificationAuditResult.fromMap(Map<String, dynamic> map) {
    List<String> readList(String key) {
      final value = map[key];
      return value is List
          ? value.map((item) => item.toString()).toList(growable: false)
          : const <String>[];
    }

    Map<String, dynamic> readObject(String key) {
      final value = map[key];
      return value is Map
          ? value.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{};
    }

    final mismatchesValue = map['mismatches'];
    return DgiiCertificationAuditResult(
      caseId: (map['caseId'] as num?)?.toInt() ?? 0,
      encf: _nullableText(map['eNCF'] ?? map['encf']),
      tipoEcf: _nullableText(map['tipoEcf']),
      filename: _nullableText(map['filename']),
      filenameValid: map['filenameValid'] == true,
      xsdValid: map['xsdValid'] == true,
      requiredFieldsPresent: map['requiredFieldsPresent'] == true,
      noPlaceholders: map['noPlaceholders'] == true,
      totalsMatchExcel: map['totalsMatchExcel'] == true,
      totalsMatchItems: map['totalsMatchItems'] == true,
      aptoParaEnviar: map['aptoParaEnviar'] == true,
      status: map['status']?.toString() ?? 'NO APTO PARA ENVIAR',
      summary: map['summary']?.toString() ?? '',
      warnings: readList('warnings'),
      errors: readList('errors'),
      mismatches: mismatchesValue is List
          ? mismatchesValue
                .whereType<Map>()
                .map(
                  (item) => DgiiCertificationAuditMismatch.fromMap(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <DgiiCertificationAuditMismatch>[],
      excelValues: readObject('excelValues'),
      xmlValues: readObject('xmlValues'),
      calculatedValues: readObject('calculatedValues'),
      raw: readObject('raw'),
      ai: readObject('ai'),
    );
  }
}

class DgiiCertificationXmlValidationResult {
  const DgiiCertificationXmlValidationResult({
    required this.wellFormed,
    required this.xsdValidated,
    required this.valid,
    required this.canSign,
    required this.errors,
    required this.warnings,
  });

  final bool wellFormed;
  final bool xsdValidated;
  final bool valid;
  final bool canSign;
  final List<String> errors;
  final List<String> warnings;

  factory DgiiCertificationXmlValidationResult.fromMap(
    Map<String, dynamic> map,
  ) {
    List<String> readList(String key) {
      final value = map[key];
      return value is List
          ? value.map((item) => item.toString()).toList(growable: false)
          : const <String>[];
    }

    return DgiiCertificationXmlValidationResult(
      wellFormed: map['wellFormed'] == true,
      xsdValidated: map['xsdValidated'] == true,
      valid: map['valid'] == true,
      canSign: map['canSign'] == true,
      errors: readList('errors'),
      warnings: readList('warnings'),
    );
  }
}

class DgiiCertificationDiagnosticsModel {
  const DgiiCertificationDiagnosticsModel({
    required this.prismaClientHasNewFields,
    required this.xsdDirectoryExists,
    required this.xsdFilesFound,
    required this.xsdValidationEngineAvailable,
    required this.rfceGenerationAvailable,
    required this.canSubmitToDgii,
    this.signingEngineAvailable = false,
    this.certificateConfigured = false,
    this.signedCasesCount = 0,
    this.totalCasesCount = 0,
    this.lastSigningError,
    this.canSignCertification = false,
    this.submitBlockers = const <String>[],
    this.requiredEndpointConfigKeys = const <String>[],
    this.requiredAuthConfigKeys = const <String>[],
    this.dgiiEndpointConfigExists = false,
    this.dgiiAuthConfigExists = false,
    this.dgiiAuthTokenValid = false,
    this.dgiiAuthLastErrorCode,
    this.dgiiAuthLastErrorMessage,
    this.dgiiAuthLastErrorAt,
    this.dgiiAuthTokenExpiresAt,
    this.activeCertificateExists = false,
    this.databaseHasNewFields,
    this.pendingMigrationWarning,
  });

  final bool prismaClientHasNewFields;
  final bool? databaseHasNewFields;
  final String? pendingMigrationWarning;
  final bool xsdDirectoryExists;
  final int xsdFilesFound;
  final bool xsdValidationEngineAvailable;
  final bool rfceGenerationAvailable;
  final bool canSubmitToDgii;
  final bool signingEngineAvailable;
  final bool certificateConfigured;
  final int signedCasesCount;
  final int totalCasesCount;
  final String? lastSigningError;
  final bool canSignCertification;
  final List<String> submitBlockers;
  final List<String> requiredEndpointConfigKeys;
  final List<String> requiredAuthConfigKeys;
  final bool dgiiEndpointConfigExists;
  final bool dgiiAuthConfigExists;
  final bool dgiiAuthTokenValid;
  final String? dgiiAuthLastErrorCode;
  final String? dgiiAuthLastErrorMessage;
  final String? dgiiAuthLastErrorAt;
  final String? dgiiAuthTokenExpiresAt;
  final bool activeCertificateExists;

  bool get hasMigrationWarning =>
      pendingMigrationWarning?.trim().isNotEmpty == true ||
      databaseHasNewFields == false;

  factory DgiiCertificationDiagnosticsModel.fromMap(Map<String, dynamic> map) {
    List<String> readList(String key) {
      final value = map[key];
      return value is List
          ? value.map((item) => item.toString()).toList(growable: false)
          : const <String>[];
    }

    final lastSigningErrorValue = map['lastSigningError'];
    final lastSigningError = lastSigningErrorValue is Map
        ? lastSigningErrorValue['message']?.toString()
        : lastSigningErrorValue?.toString();

    return DgiiCertificationDiagnosticsModel(
      prismaClientHasNewFields: map['prismaClientHasNewFields'] == true,
      databaseHasNewFields: map['databaseHasNewFields'] is bool
          ? map['databaseHasNewFields'] as bool
          : null,
      pendingMigrationWarning: map['pendingMigrationWarning']?.toString(),
      xsdDirectoryExists: map['xsdDirectoryExists'] == true,
      xsdFilesFound: (map['xsdFilesFound'] as num?)?.toInt() ?? 0,
      xsdValidationEngineAvailable: map['xsdValidationEngineAvailable'] == true,
      rfceGenerationAvailable: map['rfceGenerationAvailable'] == true,
      canSubmitToDgii: map['canSubmitToDgii'] == true,
      signingEngineAvailable: map['signingEngineAvailable'] == true,
      certificateConfigured: map['certificateConfigured'] == true,
      signedCasesCount: (map['signedCasesCount'] as num?)?.toInt() ?? 0,
      totalCasesCount: (map['totalCasesCount'] as num?)?.toInt() ?? 0,
      lastSigningError: lastSigningError,
      canSignCertification: map['canSignCertification'] == true,
      submitBlockers: readList('submitBlockers'),
      requiredEndpointConfigKeys: readList('requiredEndpointConfigKeys'),
      requiredAuthConfigKeys: readList('requiredAuthConfigKeys'),
      dgiiEndpointConfigExists: map['dgiiEndpointConfigExists'] == true,
      dgiiAuthConfigExists: map['dgiiAuthConfigExists'] == true,
      dgiiAuthTokenValid: map['dgiiAuthTokenValid'] == true,
      dgiiAuthLastErrorCode: map['dgiiAuthLastErrorCode']?.toString(),
      dgiiAuthLastErrorMessage: map['dgiiAuthLastErrorMessage']?.toString(),
      dgiiAuthLastErrorAt: map['dgiiAuthLastErrorAt']?.toString(),
      dgiiAuthTokenExpiresAt: map['dgiiAuthTokenExpiresAt']?.toString(),
      activeCertificateExists: map['activeCertificateExists'] == true,
    );
  }
}

class DgiiManualSignedSeedResult {
  const DgiiManualSignedSeedResult({
    required this.tokenAccepted,
    required this.environment,
    this.issuedAt,
    this.expiresAt,
    this.validatedAt,
    this.signedXmlRoot,
    this.signedXmlHasSignature = false,
    this.message,
    this.validateUrl,
    this.payloadMode,
    this.fieldName,
  });

  final bool tokenAccepted;
  final String environment;
  final String? issuedAt;
  final String? expiresAt;
  final String? validatedAt;
  final String? signedXmlRoot;
  final bool signedXmlHasSignature;
  final String? message;
  final String? validateUrl;
  final String? payloadMode;
  final String? fieldName;

  factory DgiiManualSignedSeedResult.fromMap(Map<String, dynamic> map) {
    return DgiiManualSignedSeedResult(
      tokenAccepted: map['tokenAccepted'] == true,
      environment: map['environment']?.toString() ?? '',
      issuedAt: map['issuedAt']?.toString(),
      expiresAt: map['expiresAt']?.toString(),
      validatedAt: map['validatedAt']?.toString(),
      signedXmlRoot: map['signedXmlRoot']?.toString(),
      signedXmlHasSignature: map['signedXmlHasSignature'] == true,
      message: map['message']?.toString(),
      validateUrl: map['validateUrl']?.toString(),
      payloadMode: map['payloadMode']?.toString(),
      fieldName: map['fieldName']?.toString(),
    );
  }
}

class DgiiCertificationCasePreflightModel {
  const DgiiCertificationCasePreflightModel({
    required this.caseId,
    required this.canSend,
    required this.blockers,
    required this.warnings,
    this.endpointType,
    this.endpointUrlMasked,
    this.certificateStatus,
    this.xmlValidationStatus,
    this.signatureStatus,
  });

  final int caseId;
  final bool canSend;
  final List<String> blockers;
  final List<String> warnings;
  final String? endpointType;
  final String? endpointUrlMasked;
  final String? certificateStatus;
  final String? xmlValidationStatus;
  final String? signatureStatus;

  bool get dbOk => !blockers.contains('DB_MIGRATION_NOT_APPLIED');
  bool get xsdOk =>
      !blockers.contains('XSD_FILES_MISSING') &&
      !blockers.contains('XSD_ENGINE_MISSING') &&
      !blockers.contains('XSD_VALIDATION_FAILED');
  bool get signatureOk =>
      signatureStatus == 'VALID' && !blockers.contains('SIGNED_XML_MISSING');
  bool get endpointOk =>
      !blockers.contains('DGII_ENDPOINT_CONFIG_MISSING') &&
      !blockers.contains('ECF_ENDPOINT_MISSING') &&
      !blockers.contains('RFCE_ENDPOINT_MISSING');
  bool get authOk => !blockers.contains('DGII_AUTH_CONFIG_MISSING');
  bool get certificateOk =>
      certificateStatus == 'VALID' &&
      !blockers.contains('ACTIVE_CERTIFICATE_MISSING_OR_INVALID') &&
      !blockers.contains('CERTIFICATE_RNC_MISMATCH') &&
      !blockers.contains('CERTIFICATE_KEY_MISMATCH');

  factory DgiiCertificationCasePreflightModel.fromMap(
    Map<String, dynamic> map,
  ) {
    List<String> readList(String key) {
      final value = map[key];
      return value is List
          ? value.map((item) => item.toString()).toList(growable: false)
          : const <String>[];
    }

    return DgiiCertificationCasePreflightModel(
      caseId: (map['caseId'] as num?)?.toInt() ?? 0,
      canSend: map['canSend'] == true,
      blockers: readList('blockers'),
      warnings: readList('warnings'),
      endpointType: map['endpointType']?.toString(),
      endpointUrlMasked: map['endpointUrlMasked']?.toString(),
      certificateStatus: map['certificateStatus']?.toString(),
      xmlValidationStatus: map['xmlValidationStatus']?.toString(),
      signatureStatus: map['signatureStatus']?.toString(),
    );
  }
}

class DgiiCertificationBatchPreflightModel {
  const DgiiCertificationBatchPreflightModel({
    required this.total,
    required this.readyToSend,
    required this.blocked,
    required this.warnings,
    required this.cases,
  });

  final int total;
  final int readyToSend;
  final int blocked;
  final List<String> warnings;
  final List<DgiiCertificationCasePreflightModel> cases;

  factory DgiiCertificationBatchPreflightModel.fromMap(
    Map<String, dynamic> map,
  ) {
    final cases = map['cases'];
    final warnings = map['warnings'];
    return DgiiCertificationBatchPreflightModel(
      total: (map['total'] as num?)?.toInt() ?? 0,
      readyToSend: (map['readyToSend'] as num?)?.toInt() ?? 0,
      blocked: (map['blocked'] as num?)?.toInt() ?? 0,
      warnings: warnings is List
          ? warnings.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      cases: cases is List
          ? cases
                .whereType<Map>()
                .map(
                  (item) => DgiiCertificationCasePreflightModel.fromMap(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <DgiiCertificationCasePreflightModel>[],
    );
  }
}

class DgiiCertificationBatchActionResult {
  const DgiiCertificationBatchActionResult({
    required this.total,
    this.generated = 0,
    this.signed = 0,
    this.sent = 0,
    this.queried = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.conditional = 0,
    this.processing = 0,
    this.skipped = 0,
    required this.failed,
    required this.errors,
  });

  final int total;
  final int generated;
  final int signed;
  final int sent;
  final int queried;
  final int accepted;
  final int rejected;
  final int conditional;
  final int processing;
  final int skipped;
  final int failed;
  final List<String> errors;

  factory DgiiCertificationBatchActionResult.fromMap(Map<String, dynamic> map) {
    final errors = map['errors'];
    return DgiiCertificationBatchActionResult(
      total: (map['total'] as num?)?.toInt() ?? 0,
      generated: (map['generated'] as num?)?.toInt() ?? 0,
      signed: (map['signed'] as num?)?.toInt() ?? 0,
      sent: (map['sent'] as num?)?.toInt() ?? 0,
      queried: (map['queried'] as num?)?.toInt() ?? 0,
      accepted: (map['accepted'] as num?)?.toInt() ?? 0,
      rejected: (map['rejected'] as num?)?.toInt() ?? 0,
      conditional: (map['conditional'] as num?)?.toInt() ?? 0,
      processing: (map['processing'] as num?)?.toInt() ?? 0,
      skipped: (map['skipped'] as num?)?.toInt() ?? 0,
      failed: (map['failed'] as num?)?.toInt() ?? 0,
      errors: errors is List
          ? errors
                .map((item) {
                  if (item is Map) {
                    final caseId = item['caseId']?.toString() ?? '';
                    final missing = item['missingFields'];
                    final missingText = missing is List && missing.isNotEmpty
                        ? ' Campos faltantes: ${missing.map((field) => field.toString()).join(', ')}'
                        : '';
                    final message =
                        (item['humanReadableMessage'] ?? item['message'] ?? '')
                            .toString();
                    final label = caseId.isEmpty
                        ? message
                        : 'Caso $caseId: $message';
                    return '$label$missingText'.trim();
                  }
                  return item.toString();
                })
                .toList(growable: false)
          : const <String>[],
    );
  }
}

typedef DgiiCertificationBatchXmlResult = DgiiCertificationBatchActionResult;

class DgiiCertificationBatchSummary {
  const DgiiCertificationBatchSummary({
    required this.totalCases,
    required this.imported,
    required this.xmlGenerated,
    required this.signed,
    required this.sent,
    required this.accepted,
    required this.rejected,
    required this.acceptedConditional,
    required this.processing,
    required this.error,
    required this.ecfCases,
    required this.rfceCases,
    required this.progressPercentage,
    required this.blockingIssues,
  });

  final int totalCases;
  final int imported;
  final int xmlGenerated;
  final int signed;
  final int sent;
  final int accepted;
  final int rejected;
  final int acceptedConditional;
  final int processing;
  final int error;
  final int ecfCases;
  final int rfceCases;
  final int progressPercentage;
  final List<String> blockingIssues;

  factory DgiiCertificationBatchSummary.fromMap(Map<String, dynamic> map) {
    final issues = map['blockingIssues'];
    return DgiiCertificationBatchSummary(
      totalCases: (map['totalCases'] as num?)?.toInt() ?? 0,
      imported: (map['imported'] as num?)?.toInt() ?? 0,
      xmlGenerated: (map['xmlGenerated'] as num?)?.toInt() ?? 0,
      signed: (map['signed'] as num?)?.toInt() ?? 0,
      sent: (map['sent'] as num?)?.toInt() ?? 0,
      accepted: (map['accepted'] as num?)?.toInt() ?? 0,
      rejected: (map['rejected'] as num?)?.toInt() ?? 0,
      acceptedConditional: (map['acceptedConditional'] as num?)?.toInt() ?? 0,
      processing: (map['processing'] as num?)?.toInt() ?? 0,
      error: (map['error'] as num?)?.toInt() ?? 0,
      ecfCases: (map['ecfCases'] as num?)?.toInt() ?? 0,
      rfceCases: (map['rfceCases'] as num?)?.toInt() ?? 0,
      progressPercentage: (map['progressPercentage'] as num?)?.toInt() ?? 0,
      blockingIssues: issues is List
          ? issues.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

class DgiiCertificationImportResult {
  const DgiiCertificationImportResult({
    required this.batch,
    required this.imported,
    required this.warnings,
  });

  final DgiiCertificationBatchModel batch;
  final int imported;
  final List<String> warnings;

  factory DgiiCertificationImportResult.fromMap(Map<String, dynamic> map) {
    final warnings = map['warnings'];
    return DgiiCertificationImportResult(
      batch: DgiiCertificationBatchModel.fromMap(
        (map['batch'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      imported: (map['imported'] as num?)?.toInt() ?? 0,
      warnings: warnings is List
          ? warnings
                .map((item) {
                  if (item is Map) {
                    final sheet = item['sheetName']?.toString() ?? '';
                    final row = item['rowNumber']?.toString() ?? '';
                    final message = item['message']?.toString() ?? '';
                    return [
                      sheet,
                      if (row.isNotEmpty) 'fila $row',
                      message,
                    ].where((part) => part.trim().isNotEmpty).join(' - ');
                  }
                  return item.toString();
                })
                .toList(growable: false)
          : const <String>[],
    );
  }
}
