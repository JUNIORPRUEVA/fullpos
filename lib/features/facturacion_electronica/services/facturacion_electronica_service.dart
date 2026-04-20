import 'dart:convert';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
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
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _RemoteElectronicInvoiceException(
        message:
            decoded['message']?.toString().trim().isNotEmpty == true
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
    final response = await api.get(
      '/api/electronic-invoicing/outbound/result/by-rnc/$trackId',
      headers: headers,
      queryParameters: <String, String>{...locators, 'branchId': '0'},
      retry: false,
    );
    final decoded = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _RemoteElectronicInvoiceException(
        message:
            decoded['message']?.toString().trim().isNotEmpty == true
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

  static FacturaElectronicaModel _remoteInvoiceToModel({
    required legacy_sales.SaleModel sale,
    required String documentTypeCode,
    required ElectronicCompanyModel company,
    required Map<String, dynamic> invoice,
  }) {
    final createdAtMs =
        _parseMillis(invoice['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
    final updatedAtMs =
        _parseMillis(invoice['updatedAt']) ?? DateTime.now().millisecondsSinceEpoch;

    return FacturaElectronicaModel(
      saleId: sale.id!,
      localCode: sale.localCode,
      ecf: invoice['ecf']?.toString(),
      tipoDocumento:
          invoice['documentTypeCode']?.toString().trim().isNotEmpty == true
          ? invoice['documentTypeCode'].toString().trim()
          : documentTypeCode,
      tipoDescriptivo:
          invoice['documentTypeCode']?.toString().trim() == '34'
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
          _parseMillis(invoice['acceptedAt']) ?? _parseMillis(invoice['rejectedAt']),
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
      throw const _RemoteElectronicInvoiceException(
        message: 'No se pudo identificar la empresa para la facturación electrónica',
        errorCode: 'ELECTRONIC_OUTBOUND_COMPANY_REQUIRED',
      );
    }

    final api = ApiClient(
      baseUrl: CloudSyncService.instance.debugResolveCloudBaseUrl(settings),
    );
    final headers = _buildHeaders(settings.cloudApiKey);

    var invoice = await _postRemoteStep(
      api: api,
      path: '/api/electronic-invoicing/outbound/generate/by-rnc',
      headers: headers,
      body: {
        ...locators,
        'saleId': sale.id,
        'documentTypeCode': documentTypeCode,
        'branchId': 0,
      },
    );

    invoice = await _postRemoteStep(
      api: api,
      path: '/api/electronic-invoicing/outbound/sign/by-rnc',
      headers: headers,
      body: {
        ...locators,
        'invoiceId': invoice['id'],
        'force': false,
      },
    );

    invoice = await _postRemoteStep(
      api: api,
      path: '/api/electronic-invoicing/outbound/submit/by-rnc',
      headers: headers,
      body: {
        ...locators,
        'invoiceId': invoice['id'],
        'force': false,
      },
    );

    if (_shouldQueryTrack(invoice)) {
      invoice = await _queryRemoteTrack(
        api: api,
        headers: headers,
        locators: locators,
        trackId: invoice['dgiiTrackId'].toString(),
      );
    }

    return _remoteInvoiceToModel(
      sale: sale,
      documentTypeCode: documentTypeCode,
      company: company,
      invoice: invoice,
    );
  }

  static FacturaElectronicaModel _buildRemoteFailureModel({
    required legacy_sales.SaleModel sale,
    required String documentTypeCode,
    required ElectronicCompanyModel company,
    required String message,
    required String? errorCode,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedCode = (errorCode ?? '').trim().toUpperCase();
    final isConfigurationIssue = normalizedCode.contains('COMPANY_REQUIRED') ||
        normalizedCode.contains('CERTIFICATE') ||
        normalizedCode.contains('SEQUENCE') ||
        normalizedCode.contains('REAL_EI_DISABLED') ||
        normalizedCode.contains('LOCATOR') ||
        normalizedCode.contains('NOT_FOUND');

    return FacturaElectronicaModel(
      saleId: sale.id!,
      localCode: sale.localCode,
      tipoDocumento: documentTypeCode,
      tipoDescriptivo: 'Factura',
      estadoDgii: isConfigurationIssue
          ? FacturaElectronicaModel.statusConfigPending
          : FacturaElectronicaModel.statusRejected,
      estadoInterno: isConfigurationIssue ? 'CONFIG_PENDING' : 'ERROR',
      mensajeDgii: message,
      ambiente: company.environment,
      montoTotal: sale.total,
      clienteNombre: sale.customerNameSnapshot,
      clienteRnc: sale.customerRncSnapshot,
      createdAtMs: now,
      updatedAtMs: now,
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
    if (sale.kind != 'invoice') {
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
      final now = DateTime.now().millisecondsSinceEpoch;
      return FacturaElectronicaRepository.upsert(
        FacturaElectronicaModel(
          saleId: sale.id!,
          localCode: sale.localCode,
          tipoDocumento: 'venta_local',
          tipoDescriptivo: 'Factura',
          estadoDgii: FacturaElectronicaModel.statusLocal,
          estadoInterno: 'LOCAL_ONLY',
          mensajeDgii: 'Venta registrada sin emisión electrónica.',
          ambiente: company.environment,
          montoTotal: sale.total,
          clienteNombre: sale.customerNameSnapshot,
          clienteRnc: sale.customerRncSnapshot,
          createdAtMs: now,
          updatedAtMs: now,
        ),
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
    } on _RemoteElectronicInvoiceException catch (error) {
      return FacturaElectronicaRepository.upsert(
        _buildRemoteFailureModel(
          sale: sale,
          documentTypeCode: documentTypeCode,
          company: company,
          message: error.message,
          errorCode: error.errorCode,
        ),
      );
    } catch (error) {
      return FacturaElectronicaRepository.upsert(
        _buildRemoteFailureModel(
          sale: sale,
          documentTypeCode: documentTypeCode,
          company: company,
          message: error.toString(),
          errorCode: 'ELECTRONIC_OUTBOUND_RUNTIME_ERROR',
        ),
      );
    }
  }
}

class _RemoteElectronicInvoiceException implements Exception {
  const _RemoteElectronicInvoiceException({
    required this.message,
    this.errorCode,
  });

  final String message;
  final String? errorCode;
}
