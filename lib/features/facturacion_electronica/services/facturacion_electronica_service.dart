import 'dart:convert';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../sales/data/sale_item_model.dart';
import '../../sales/data/sales_model.dart' as legacy_sales;
import '../data/electronic_company_repository.dart';
import '../data/electronic_company_locator_helper.dart';
import '../data/factura_electronica_repository.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/models/electronic_company_model.dart';
import '../data/models/factura_electronica_model.dart';

class FacturacionElectronicaService {
  FacturacionElectronicaService._();

  static String _resolveDocumentTypeCode(legacy_sales.SaleModel sale) {
    final rawType = (sale.electronicDocumentType ?? '').trim();
    if (rawType == '31' || rawType == '32') {
      return rawType;
    }

    final fiscalId = (sale.customerRncSnapshot ?? '').trim();
    return fiscalId.isNotEmpty ? '31' : '32';
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int? _parseMillis(Object? value) {
    final raw = value?.toString() ?? '';
    if (raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch;
  }

  static Map<String, String> _buildHeaders(String? cloudKey) {
    final headers = <String, String>{};
    final trimmed = cloudKey?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      headers['x-cloud-key'] = trimmed;
    }
    return headers;
  }

  static Map<String, String> _buildLocators({
    required int? sessionCompanyId,
    required String? companyCloudId,
    required String? companyRnc,
  }) {
    return buildElectronicCompanyLocators(
      sessionCompanyId: sessionCompanyId,
      companyCloudId: companyCloudId,
      companyRnc: companyRnc,
    );
  }

  static Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static bool _isSaleNotFoundError(Object error) {
    return error is _RemoteElectronicInvoiceException &&
        (error.errorCode ?? '').trim().toUpperCase() == 'SALE_NOT_FOUND';
  }

  static Future<void> _syncSalesBeforeRemoteGenerate({
    required legacy_sales.SaleModel sale,
    required String reason,
  }) async {
    final syncOk = await CloudSyncService.instance.syncSalesIfEnabledDetailed(
      traceSaleLocalCode: sale.localCode,
      requireTraceLocalCode: true,
      reason: 'electronic_invoice_${reason}_sale_${sale.id}',
    );
    await AppLogger.instance.logInfo(
      'FE sales presync result reason=$reason saleId=${sale.id} saleLocalCode=${sale.localCode} success=$syncOk',
      module: 'electronic_invoicing',
    );
    if (!syncOk) {
      throw _RemoteElectronicInvoiceException(
        message:
            'La venta no quedó disponible en cloud antes de generar el documento electrónico',
        errorCode: 'SALE_SYNC_REQUIRED',
      );
    }
  }

  static Future<Map<String, dynamic>> _generateRemoteInvoice({
    required ApiClient api,
    required Map<String, String> headers,
    required Map<String, String> locators,
    required legacy_sales.SaleModel sale,
    required String documentTypeCode,
  }) async {
    final sessionCompanyId = await SessionManager.companyId();
    final generatePayload = <String, dynamic>{
      ...locators,
      'saleId': sale.id,
      if (sale.localCode.trim().isNotEmpty)
        'saleLocalCode': sale.localCode.trim(),
      'documentTypeCode': documentTypeCode,
      'branchId': 0,
    };

    Future<Map<String, dynamic>> runGenerate() {
      return _postRemoteStep(
        api: api,
        path: '/api/electronic-invoicing/outbound/generate/by-rnc',
        headers: headers,
        body: generatePayload,
      );
    }

    await AppLogger.instance.logInfo(
      'FE generate request saleId=${sale.id} saleLocalCode=${sale.localCode} companyId=${sessionCompanyId ?? 'null'} companyCloudId=${locators['companyCloudId'] ?? 'null'} companyRnc=${locators['companyRnc'] ?? 'null'} payload=${jsonEncode(generatePayload)}',
      module: 'electronic_invoicing',
    );

    await _syncSalesBeforeRemoteGenerate(
      sale: sale,
      reason: 'presubmit_sync',
    );

    try {
      return await runGenerate();
    } on _RemoteElectronicInvoiceException catch (error) {
      if (!_isSaleNotFoundError(error)) {
        rethrow;
      }

      await AppLogger.instance.logWarn(
        'FE generate retry triggered saleId=${sale.id} saleLocalCode=${sale.localCode} errorCode=${error.errorCode}',
        module: 'electronic_invoicing',
      );
      await _syncSalesBeforeRemoteGenerate(
        sale: sale,
        reason: 'retry_after_sale_not_found',
      );
      return runGenerate();
    }
  }

  static String _mapRemoteStatus(Map<String, dynamic> invoice) {
    final dgiiStatus = (invoice['dgiiStatus']?.toString() ?? '')
        .trim()
        .toUpperCase();
    switch (dgiiStatus) {
      case 'ACCEPTED':
      case 'ACCEPTED_CONDITIONAL':
        return FacturaElectronicaModel.statusAccepted;
      case 'REJECTED':
      case 'ERROR':
        return FacturaElectronicaModel.statusRejected;
      case 'RECEIVED':
      case 'IN_PROCESS':
        return FacturaElectronicaModel.statusPending;
    }

    final internalStatus = (invoice['internalStatus']?.toString() ?? '')
        .trim()
        .toUpperCase();
    switch (internalStatus) {
      case 'ACCEPTED':
      case 'ACCEPTED_CONDITIONAL':
        return FacturaElectronicaModel.statusAccepted;
      case 'REJECTED':
      case 'ERROR':
        return FacturaElectronicaModel.statusRejected;
      case 'GENERATED':
      case 'SIGNED':
      case 'SUBMISSION_PENDING':
      case 'SUBMITTED':
        return FacturaElectronicaModel.statusPending;
      default:
        return FacturaElectronicaModel.statusLocal;
    }
  }

  static bool _isFinalRemoteStatus(Map<String, dynamic> invoice) {
    final dgiiStatus = (invoice['dgiiStatus']?.toString() ?? '')
        .trim()
        .toUpperCase();
    if (dgiiStatus == 'ACCEPTED' ||
        dgiiStatus == 'ACCEPTED_CONDITIONAL' ||
        dgiiStatus == 'REJECTED' ||
        dgiiStatus == 'ERROR') {
      return true;
    }

    final internalStatus = (invoice['internalStatus']?.toString() ?? '')
        .trim()
        .toUpperCase();
    return internalStatus == 'ACCEPTED' ||
        internalStatus == 'ACCEPTED_CONDITIONAL' ||
        internalStatus == 'REJECTED' ||
        internalStatus == 'ERROR';
  }

  static String _safeRemoteStatusSummary(Map<String, dynamic> invoice) {
    final dgiiStatus = (invoice['dgiiStatus']?.toString() ?? '').trim();
    final internalStatus = (invoice['internalStatus']?.toString() ?? '').trim();
    final trackId = (invoice['dgiiTrackId']?.toString() ?? '').trim();
    final ecf = (invoice['ecf']?.toString() ?? '').trim();
    return 'ecf=$ecf trackId=$trackId dgiiStatus=$dgiiStatus internalStatus=$internalStatus';
  }

  static bool _shouldQueryTrack(Map<String, dynamic> invoice) {
    final trackId = (invoice['dgiiTrackId']?.toString() ?? '').trim();
    if (trackId.isEmpty) return false;
    final dgiiStatus = (invoice['dgiiStatus']?.toString() ?? '')
        .trim()
        .toUpperCase();
    return dgiiStatus == 'RECEIVED' || dgiiStatus == 'IN_PROCESS';
  }

  static Future<Map<String, dynamic>> _postRemoteStep({
    required ApiClient api,
    required String path,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final response = await api.postJson(
      path,
      headers: headers,
      body: body,
      retry: false,
    );
    await AppLogger.instance.logInfo(
      'FE remote response path=$path status=${response.statusCode} request=${jsonEncode(body)} response=${response.body}',
      module: 'electronic_invoicing',
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _RemoteElectronicInvoiceException(
        message: decoded['message']?.toString().trim().isNotEmpty == true
            ? decoded['message'].toString().trim()
            : 'No se pudo procesar el documento electrónico',
        errorCode: decoded['errorCode']?.toString(),
      );
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> _queryRemoteTrack({
    required ApiClient api,
    required Map<String, String> headers,
    required Map<String, String> locators,
    required String trackId,
  }) async {
    final path =
        '/api/electronic-invoicing/outbound/result/by-rnc/${trackId.trim()}';
    final response = await api.get(
      path,
      headers: headers,
      queryParameters: <String, String>{...locators, 'branchId': '0'},
      retry: false,
    );
    await AppLogger.instance.logInfo(
      'FE dgii result query path=$path status=${response.statusCode} trackId=${trackId.trim()} response=${response.body}',
      module: 'electronic_invoicing',
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _RemoteElectronicInvoiceException(
        message: decoded['message']?.toString().trim().isNotEmpty == true
            ? decoded['message'].toString().trim()
            : 'No se pudo consultar el resultado DGII',
        errorCode: decoded['errorCode']?.toString(),
      );
    }
    final invoice = decoded['invoice'];
    if (invoice is Map<String, dynamic>) {
      return invoice;
    }
    if (invoice is Map) {
      return Map<String, dynamic>.from(invoice);
    }
    return decoded;
  }

  static void _scheduleTrackPolling({
    required ApiClient api,
    required Map<String, String> headers,
    required Map<String, String> locators,
    required legacy_sales.SaleModel sale,
    required String documentTypeCode,
    required ElectronicCompanyModel company,
    required String trackId,
    required Map<String, dynamic> lastInvoice,
  }) {
    final trimmedTrackId = trackId.trim();
    if (trimmedTrackId.isEmpty) return;
    if (_isFinalRemoteStatus(lastInvoice)) return;
    if (!_shouldQueryTrack(lastInvoice)) return;

    Future<void>(() async {
      final delays = <Duration>[
        const Duration(seconds: 8),
        const Duration(seconds: 20),
        const Duration(seconds: 45),
      ];

      var current = lastInvoice;
      for (var attempt = 0; attempt < delays.length; attempt++) {
        await Future.delayed(delays[attempt]);

        try {
          await AppLogger.instance.logInfo(
            'FE dgii poll attempt=${attempt + 1}/${delays.length} trackId=$trimmedTrackId before=${_safeRemoteStatusSummary(current)}',
            module: 'electronic_invoicing',
          );
          current = await _queryRemoteTrack(
            api: api,
            headers: headers,
            locators: locators,
            trackId: trimmedTrackId,
          );
          await AppLogger.instance.logInfo(
            'FE dgii poll result attempt=${attempt + 1}/${delays.length} trackId=$trimmedTrackId after=${_safeRemoteStatusSummary(current)}',
            module: 'electronic_invoicing',
          );

          final model = _remoteInvoiceToModel(
            sale: sale,
            documentTypeCode: documentTypeCode,
            company: company,
            invoice: current,
          );
          final persisted = await FacturaElectronicaRepository.upsert(model);
          await AppLogger.instance.logInfo(
            'FE dgii poll persisted saleId=${sale.id} saleLocalCode=${sale.localCode} trackId=$trimmedTrackId estadoDgii=${persisted.estadoDgii} estadoInterno=${persisted.estadoInterno}',
            module: 'electronic_invoicing',
          );

          if (_isFinalRemoteStatus(current)) {
            return;
          }
          if (!_shouldQueryTrack(current)) {
            return;
          }
        } catch (error) {
          await AppLogger.instance.logWarn(
            'FE dgii poll failed attempt=${attempt + 1}/${delays.length} trackId=$trimmedTrackId error=$error',
            module: 'electronic_invoicing',
          );
          // Continue to next attempt.
        }
      }
    });
  }

  static FacturaElectronicaModel _remoteInvoiceToModel({
    required legacy_sales.SaleModel sale,
    required String documentTypeCode,
    required ElectronicCompanyModel company,
    required Map<String, dynamic> invoice,
  }) {
    final createdAtMs =
        _parseMillis(invoice['createdAt']) ??
        DateTime.now().millisecondsSinceEpoch;
    final updatedAtMs =
        _parseMillis(invoice['updatedAt']) ??
        DateTime.now().millisecondsSinceEpoch;

    return FacturaElectronicaModel(
      saleId: sale.id!,
      localCode: sale.localCode,
      ecf: invoice['ecf']?.toString(),
      tipoDocumento:
          invoice['documentTypeCode']?.toString().trim().isNotEmpty == true
          ? invoice['documentTypeCode'].toString().trim()
          : documentTypeCode,
      tipoDescriptivo: invoice['documentTypeCode']?.toString().trim() == '34'
          ? 'Nota de crédito'
          : 'Factura',
      xmlPayload: invoice['xmlUnsigned']?.toString(),
      xmlFirmado: invoice['xmlSigned']?.toString(),
      dgiiTrackId: invoice['dgiiTrackId']?.toString(),
      estadoDgii: _mapRemoteStatus(invoice),
      codigoDgii: invoice['rejectionCode']?.toString(),
      mensajeDgii: invoice['rejectionMessage']?.toString(),
      ambiente: company.environment,
      montoTotal: _asDouble(invoice['totalAmount']),
      clienteNombre:
          sale.customerNameSnapshot ?? invoice['buyerName']?.toString(),
      clienteRnc: sale.customerRncSnapshot ?? invoice['buyerRnc']?.toString(),
      referenciaDocumento: invoice['referenceDocument']?.toString(),
      estadoInterno: invoice['internalStatus']?.toString(),
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs,
      sentAtMs: _parseMillis(invoice['submittedAt']),
      acknowledgedAtMs:
          _parseMillis(invoice['acceptedAt']) ??
          _parseMillis(invoice['rejectedAt']),
    );
  }

  static Future<FacturaElectronicaModel> _procesarFacturaRemota({
    required legacy_sales.SaleModel sale,
    required String documentTypeCode,
    required ElectronicCompanyModel company,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final locators = _buildLocators(
      sessionCompanyId: await SessionManager.companyId(),
      companyCloudId: settings.cloudCompanyId,
      companyRnc: settings.rnc,
    );
    if (locators.isEmpty) {
      throw _RemoteElectronicInvoiceException(
        message:
            'No se pudo identificar la empresa para la facturación electrónica',
        errorCode: 'ELECTRONIC_OUTBOUND_COMPANY_REQUIRED',
      );
    }

    final api = ApiClient(
      baseUrl: CloudSyncService.instance.debugResolveCloudBaseUrl(settings),
    );
    final headers = _buildHeaders(settings.cloudApiKey);

    var invoice = await _generateRemoteInvoice(
      api: api,
      headers: headers,
      locators: locators,
      sale: sale,
      documentTypeCode: documentTypeCode,
    );

    invoice = await _postRemoteStep(
      api: api,
      path: '/api/electronic-invoicing/outbound/sign/by-rnc',
      headers: headers,
      body: {...locators, 'invoiceId': invoice['id'], 'force': false},
    );

    invoice = await _postRemoteStep(
      api: api,
      path: '/api/electronic-invoicing/outbound/submit/by-rnc',
      headers: headers,
      body: {...locators, 'invoiceId': invoice['id'], 'force': false},
    );

    final submittedTrackId = (invoice['dgiiTrackId']?.toString() ?? '').trim();
    await AppLogger.instance.logInfo(
      'FE submit completed saleId=${sale.id} saleLocalCode=${sale.localCode} ${_safeRemoteStatusSummary(invoice)}',
      module: 'electronic_invoicing',
    );

    // Hacemos un primer query inmediato. Si DGII sigue pendiente, se agenda
    // polling en background para evitar bloquear la operación de venta.
    if (_shouldQueryTrack(invoice)) {
      if (submittedTrackId.isNotEmpty) {
        await AppLogger.instance.logInfo(
          'FE trackId received trackId=$submittedTrackId saleId=${sale.id} saleLocalCode=${sale.localCode}',
          module: 'electronic_invoicing',
        );
      }

      try {
        invoice = await _queryRemoteTrack(
          api: api,
          headers: headers,
          locators: locators,
          trackId: submittedTrackId,
        );
        await AppLogger.instance.logInfo(
          'FE dgii result immediate ${_safeRemoteStatusSummary(invoice)}',
          module: 'electronic_invoicing',
        );
      } catch (error) {
        await AppLogger.instance.logWarn(
          'FE dgii result immediate failed trackId=$submittedTrackId error=$error',
          module: 'electronic_invoicing',
        );
      }

      _scheduleTrackPolling(
        api: api,
        headers: headers,
        locators: locators,
        sale: sale,
        documentTypeCode: documentTypeCode,
        company: company,
        trackId: submittedTrackId,
        lastInvoice: invoice,
      );
    }

    return _remoteInvoiceToModel(
      sale: sale,
      documentTypeCode: documentTypeCode,
      company: company,
      invoice: invoice,
    );
  }

  static Future<void> _persistSaleElectronicLink({
    required int saleId,
    required String ecf,
    required String documentTypeCode,
  }) async {
    final db = await AppDb.database;
    await db.update(
      DbTables.sales,
      {
        'electronic_invoice_enabled': 1,
        'electronic_invoice_code': ecf,
        'electronic_document_type': documentTypeCode,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  static Future<FacturaElectronicaModel?> procesarVenta(int saleId) async {
    final db = await AppDb.database;
    final saleRows = await db.query(
      DbTables.sales,
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (saleRows.isEmpty) return null;

    final sale = legacy_sales.SaleModel.fromMap(saleRows.first);
    if (sale.kind != 'invoice' || sale.electronicInvoiceEnabled != 1) {
      return null;
    }

    final itemRows = await db.query(
      DbTables.saleItems,
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );
    final items = itemRows.map(SaleItemModel.fromMap).toList(growable: false);
    return procesarFactura(sale: sale, items: items);
  }

  static Future<FacturaElectronicaModel> procesarFactura({
    required legacy_sales.SaleModel sale,
    required List<SaleItemModel> items,
  }) async {
    final company = await ElectronicCompanyRepository.getOrCreate();
    final documentTypeCode = _resolveDocumentTypeCode(sale);

    if (sale.electronicInvoiceEnabled != 1) {
      throw _RemoteElectronicInvoiceException(
        message: 'La venta no está marcada para facturación electrónica real',
        errorCode: 'REAL_EI_REQUIRED',
      );
    }

    try {
      final remote = await _procesarFacturaRemota(
        sale: sale,
        documentTypeCode: documentTypeCode,
        company: company,
      );
      final resolvedEcf = (remote.ecf ?? '').trim();
      if (resolvedEcf.isNotEmpty) {
        await _persistSaleElectronicLink(
          saleId: sale.id!,
          ecf: resolvedEcf,
          documentTypeCode: remote.tipoDocumento,
        );
      }
      return FacturaElectronicaRepository.upsert(remote);
    } on _RemoteElectronicInvoiceException {
      rethrow;
    } catch (error) {
      throw _RemoteElectronicInvoiceException(
        message: error.toString(),
        errorCode: 'ELECTRONIC_OUTBOUND_RUNTIME_ERROR',
      );
    }
  }
}

class _RemoteElectronicInvoiceException extends AppException {
  _RemoteElectronicInvoiceException({
    required this.message,
    this.errorCode,
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
         type: _mapErrorType(errorCode),
         code: errorCode,
         messageUser: message,
         messageDev: _buildDevMessage(message, errorCode),
         originalError: originalError,
         stackTrace: stackTrace,
       );

  final String message;
  final String? errorCode;

  static AppErrorType _mapErrorType(String? errorCode) {
    final normalized = (errorCode ?? '').trim().toUpperCase();
    if (normalized.isEmpty) {
      return AppErrorType.unknown;
    }
    if (normalized.endsWith('_NOT_FOUND') || normalized == 'TRACK_NOT_FOUND') {
      return AppErrorType.notFound;
    }
    if (normalized.contains('DISABLED') ||
        normalized.contains('CONFLICT') ||
        normalized.contains('ALREADY_EXISTS') ||
        normalized.contains('STATUS_NOT_SUBMITTABLE')) {
      return AppErrorType.conflict;
    }
    if (normalized.contains('REQUIRED') ||
        normalized.contains('INVALID') ||
        normalized.contains('MISSING') ||
        normalized.contains('CERTIFICATE') ||
        normalized.contains('SEQUENCE') ||
        normalized.contains('COMPANY')) {
      return AppErrorType.validation;
    }
    if (normalized.contains('RUNTIME') || normalized.contains('DGII')) {
      return AppErrorType.server;
    }
    return AppErrorType.unknown;
  }

  static String _buildDevMessage(String message, String? errorCode) {
    final normalized = (errorCode ?? '').trim();
    if (normalized.isEmpty) {
      return 'RemoteElectronicInvoiceException: $message';
    }
    return 'RemoteElectronicInvoiceException($normalized): $message';
  }

  @override
  String toString() => errorCode == null || errorCode!.trim().isEmpty
      ? message
      : '$errorCode: $message';
}
