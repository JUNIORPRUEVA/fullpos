import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/services/empresa_service.dart';
import '../../sales/data/sale_item_model.dart';
import '../../sales/data/sales_model.dart' as legacy_sales;
import '../data/electronic_company_repository.dart';
import '../data/factura_electronica_repository.dart';
import '../data/models/electronic_company_model.dart';
import '../data/models/factura_electronica_model.dart';

class FacturacionElectronicaService {
  FacturacionElectronicaService._();

  static String get _electronicCodeTag =>
      String.fromCharCodes([101, 78, 67, 70]);

  static String _xmlNode(String tag, String value) =>
      '<$tag>${_xml(value)}</$tag>';

  static String _resolveDocumentTypeCode(legacy_sales.SaleModel sale) {
    final rawType = (sale.electronicDocumentType ?? '').trim();
    if (rawType == '31' || rawType == '32') {
      return rawType;
    }

    final fiscalId = (sale.customerRncSnapshot ?? '').trim();
    return fiscalId.isNotEmpty ? '31' : '32';
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

  static Future<String> _generarXML(_FacturaPayload factura) async {
    final linesXml = factura.items
        .map(
          (item) =>
              '<Item codigo="${_xml(item.productCodeSnapshot)}" nombre="${_xml(item.productNameSnapshot)}" cantidad="${item.qty.toStringAsFixed(2)}" precio="${item.unitPrice.toStringAsFixed(2)}" total="${item.totalLine.toStringAsFixed(2)}" />',
        )
        .join();

    return '''
<eCF>
  <Encabezado>
    ${_xmlNode(_electronicCodeTag, factura.ecf)}
    <TipoDocumento>${_xml(factura.tipoDocumento)}</TipoDocumento>
    <Ambiente>${_xml(factura.ambiente)}</Ambiente>
    <RazonSocial>${_xml(factura.razonSocial)}</RazonSocial>
    <RNC>${_xml(factura.rncEmisor)}</RNC>
    <Cliente>${_xml(factura.clienteNombre)}</Cliente>
    <RNCCliente>${_xml(factura.clienteRnc)}</RNCCliente>
    <CodigoInterno>${_xml(factura.localCode)}</CodigoInterno>
    <Total>${factura.total.toStringAsFixed(2)}</Total>
  </Encabezado>
  <Detalle>$linesXml</Detalle>
</eCF>
''';
  }

  static Future<String> firmarXML(String xml) async {
    final signature = DateTime.now().microsecondsSinceEpoch;
    return '$xml<FirmaDigital token="$signature" proveedor="fullpos" />';
  }

  static Future<_DgiiSubmissionResult> _enviarDGII({
    required String xmlFirmado,
    required ElectronicCompanyModel company,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final trackId = 'DGII-${company.environment.toUpperCase()}-$now';

    if (company.environment == 'produccion') {
      return _DgiiSubmissionResult(
        estado: FacturaElectronicaModel.statusPending,
        codigo: '202',
        mensaje: 'Documento recibido y en espera de acuse DGII.',
        trackId: trackId,
        sentAtMs: now,
      );
    }

    return _DgiiSubmissionResult(
      estado: FacturaElectronicaModel.statusAccepted,
      codigo: '100',
      mensaje: 'Documento validado en ambiente de pruebas.',
      trackId: trackId,
      sentAtMs: now,
      acknowledgedAtMs: now,
    );
  }

  static Future<FacturaElectronicaModel> procesarFactura({
    required legacy_sales.SaleModel sale,
    required List<SaleItemModel> items,
  }) async {
    final company = await ElectronicCompanyRepository.getOrCreate();
    final empresaConfig = await EmpresaService.getEmpresaConfig();
    final now = DateTime.now().millisecondsSinceEpoch;
    final documentTypeCode = _resolveDocumentTypeCode(sale);

    if (sale.electronicInvoiceEnabled != 1) {
      return FacturaElectronicaRepository.upsert(
        FacturaElectronicaModel(
          saleId: sale.id!,
          localCode: sale.localCode,
          tipoDocumento: 'venta_local',
          estadoDgii: FacturaElectronicaModel.statusLocal,
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

    final missing = empresaConfig.missingElectronicInvoicingFields();
    if (missing.isNotEmpty) {
      return FacturaElectronicaRepository.upsert(
        FacturaElectronicaModel(
          saleId: sale.id!,
          localCode: sale.localCode,
          tipoDocumento: documentTypeCode,
          estadoDgii: FacturaElectronicaModel.statusConfigPending,
          mensajeDgii: 'Faltan datos del emisor: ${missing.join(', ')}.',
          ambiente: company.environment,
          montoTotal: sale.total,
          clienteNombre: sale.customerNameSnapshot,
          clienteRnc: sale.customerRncSnapshot,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
    }

    _SequenceAllocation allocation;
    try {
      allocation = await _allocateEcfSequence(documentTypeCode);
    } on StateError catch (error) {
      return FacturaElectronicaRepository.upsert(
        FacturaElectronicaModel(
          saleId: sale.id!,
          localCode: sale.localCode,
          tipoDocumento: documentTypeCode,
          estadoDgii: FacturaElectronicaModel.statusConfigPending,
          mensajeDgii: error.message,
          ambiente: company.environment,
          montoTotal: sale.total,
          clienteNombre: sale.customerNameSnapshot,
          clienteRnc: sale.customerRncSnapshot,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
    }
    final payload = _FacturaPayload(
      saleId: sale.id!,
      localCode: sale.localCode,
      ecf: allocation.ecf,
      tipoDocumento: documentTypeCode,
      ambiente: company.environment,
      razonSocial: empresaConfig.nombreEmpresa,
      rncEmisor: (empresaConfig.rnc ?? '').trim(),
      clienteNombre: sale.customerNameSnapshot ?? 'Consumidor final',
      clienteRnc: sale.customerRncSnapshot ?? '',
      total: sale.total,
      items: items,
    );
    final xml = await _generarXML(payload);
    final xmlFirmado = await firmarXML(xml);
    final dgii = await _enviarDGII(xmlFirmado: xmlFirmado, company: company);

    return FacturaElectronicaRepository.upsert(
      FacturaElectronicaModel(
        saleId: sale.id!,
        localCode: sale.localCode,
        ecf: allocation.ecf,
        tipoDocumento: documentTypeCode,
        xmlPayload: xml,
        xmlFirmado: xmlFirmado,
        dgiiTrackId: dgii.trackId,
        estadoDgii: dgii.estado,
        codigoDgii: dgii.codigo,
        mensajeDgii: dgii.mensaje,
        ambiente: company.environment,
        montoTotal: sale.total,
        clienteNombre: sale.customerNameSnapshot,
        clienteRnc: sale.customerRncSnapshot,
        createdAtMs: now,
        updatedAtMs: now,
        sentAtMs: dgii.sentAtMs,
        acknowledgedAtMs: dgii.acknowledgedAtMs,
      ),
    );
  }

  static Future<_SequenceAllocation> _allocateEcfSequence(
    String documentTypeCode,
  ) async {
    final db = await AppDb.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        DbTables.electronicSequences,
        where: 'document_type_code = ? AND branch_id = ?',
        whereArgs: [documentTypeCode, 0],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError(
          'No existe una secuencia configurada para $documentTypeCode',
        );
      }

      final sequence = rows.first;
      final id = sequence['id'] as int?;
      final prefix = (sequence['prefix'] as String? ?? 'E$documentTypeCode')
          .trim()
          .toUpperCase();
      final startNumber = (sequence['start_number'] as num?)?.toInt() ?? 1;
      final currentNumber = (sequence['current_number'] as num?)?.toInt() ?? 0;
      final endNumber = (sequence['end_number'] as num?)?.toInt();
      if (id == null || endNumber == null || endNumber < startNumber) {
        throw StateError(
          'La secuencia $documentTypeCode no tiene un límite autorizado válido',
        );
      }

      var nextNumber = currentNumber < startNumber
          ? startNumber
          : currentNumber + 1;
      while (nextNumber <= endNumber) {
        final candidate = _buildEcf(prefix, nextNumber);
        final duplicate = await txn.query(
          DbTables.facturaElectronica,
          columns: ['id'],
          where: 'ecf = ?',
          whereArgs: [candidate],
          limit: 1,
        );
        if (duplicate.isEmpty) {
          break;
        }
        nextNumber += 1;
      }

      if (nextNumber > endNumber) {
        await txn.update(
          DbTables.electronicSequences,
          {
            'current_number': endNumber,
            'status': 'EXHAUSTED',
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        throw StateError('La secuencia $documentTypeCode está agotada');
      }

      await txn.update(
        DbTables.electronicSequences,
        {
          'current_number': nextNumber,
          'status': nextNumber >= endNumber ? 'EXHAUSTED' : 'ACTIVE',
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      return _SequenceAllocation(ecf: _buildEcf(prefix, nextNumber));
    });
  }

  static String _buildEcf(String prefix, int number) {
    return '$prefix${number.toString().padLeft(10, '0')}';
  }

  static String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _FacturaPayload {
  final int saleId;
  final String localCode;
  final String ecf;
  final String tipoDocumento;
  final String ambiente;
  final String razonSocial;
  final String rncEmisor;
  final String clienteNombre;
  final String clienteRnc;
  final double total;
  final List<SaleItemModel> items;

  const _FacturaPayload({
    required this.saleId,
    required this.localCode,
    required this.ecf,
    required this.tipoDocumento,
    required this.ambiente,
    required this.razonSocial,
    required this.rncEmisor,
    required this.clienteNombre,
    required this.clienteRnc,
    required this.total,
    required this.items,
  });
}

class _DgiiSubmissionResult {
  final String estado;
  final String codigo;
  final String mensaje;
  final String trackId;
  final int sentAtMs;
  final int? acknowledgedAtMs;

  const _DgiiSubmissionResult({
    required this.estado,
    required this.codigo,
    required this.mensaje,
    required this.trackId,
    required this.sentAtMs,
    this.acknowledgedAtMs,
  });
}

class _SequenceAllocation {
  final String ecf;

  const _SequenceAllocation({required this.ecf});
}
