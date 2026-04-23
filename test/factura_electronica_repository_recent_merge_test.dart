import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/facturacion_electronica/data/factura_electronica_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/factura_electronica_model.dart';
import 'package:fullpos/features/sales/data/sales_model.dart' as sales;

FacturaElectronicaModel _document({
  required int saleId,
  required String localCode,
  required String tipoDocumento,
  String? ecf,
  String? dgiiTrackId,
  String estadoDgii = FacturaElectronicaModel.statusLocal,
  String? estadoInterno,
  int createdAtMs = 0,
  int? updatedAtMs,
}) {
  return FacturaElectronicaModel(
    saleId: saleId,
    localCode: localCode,
    ecf: ecf,
    tipoDocumento: tipoDocumento,
    dgiiTrackId: dgiiTrackId,
    estadoDgii: estadoDgii,
    estadoInterno: estadoInterno,
    montoTotal: 0,
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs ?? createdAtMs,
  );
}

void main() {
  sales.SaleModel sale({
    required int id,
    required String localCode,
    required int createdAtMs,
    int electronicInvoiceEnabled = 0,
    String? electronicDocumentType,
    String? electronicInvoiceCode,
    String kind = sales.SaleKind.invoice,
    String? customerNameSnapshot,
    String? customerRncSnapshot,
    double total = 100,
  }) {
    return sales.SaleModel(
      id: id,
      localCode: localCode,
      kind: kind,
      status: 'completed',
      subtotal: total,
      total: total,
      customerNameSnapshot: customerNameSnapshot,
      customerRncSnapshot: customerRncSnapshot,
      electronicInvoiceEnabled: electronicInvoiceEnabled,
      electronicDocumentType: electronicDocumentType,
      electronicInvoiceCode: electronicInvoiceCode,
      createdAtMs: createdAtMs,
      updatedAtMs: createdAtMs,
    );
  }

  test(
    'pickRecentElectronicCandidates skips local-only sales and keeps older FE rows inside the limit',
    () {
      final picked = pickRecentElectronicCandidates(
        orderedDocuments: [
          _document(
            saleId: 90,
            localCode: 'V-90',
            tipoDocumento: 'venta_local',
            estadoInterno: 'LOCAL_ONLY',
            createdAtMs: 90,
          ),
          _document(
            saleId: 89,
            localCode: 'V-89',
            tipoDocumento: 'venta_local',
            estadoInterno: 'LOCAL_ONLY',
            createdAtMs: 89,
          ),
          _document(
            saleId: 88,
            localCode: 'FAC-88',
            tipoDocumento: '32',
            ecf: 'E320000000088',
            createdAtMs: 88,
          ),
          _document(
            saleId: 87,
            localCode: 'FAC-87',
            tipoDocumento: '31',
            ecf: 'E310000000087',
            createdAtMs: 87,
          ),
        ],
        limit: 2,
      );

      expect(picked, hasLength(2));
      expect(picked[0].saleId, 88);
      expect(picked[1].saleId, 87);
    },
  );

  test(
    'pickRecentElectronicCandidates keeps only documents inside the recent window',
    () {
      final picked = pickRecentElectronicCandidates(
        orderedDocuments: [
          _document(
            saleId: 100,
            localCode: 'FAC-100',
            tipoDocumento: '32',
            ecf: 'E320000000100',
            createdAtMs: 1000,
          ),
          _document(
            saleId: 99,
            localCode: 'FAC-99',
            tipoDocumento: '31',
            ecf: 'E310000000099',
            createdAtMs: 900,
          ),
          _document(
            saleId: 98,
            localCode: 'FAC-98',
            tipoDocumento: '31',
            ecf: 'E310000000098',
            createdAtMs: 100,
          ),
        ],
        limit: 10,
        recentAfterMs: 800,
      );

      expect(picked, hasLength(2));
      expect(picked[0].saleId, 100);
      expect(picked[1].saleId, 99);
    },
  );

  test(
    'mergeRecentSalesDocuments shows local and fiscal sales immediately',
    () {
      final merged = mergeRecentSalesDocuments(
        recentSales: [
          sale(
            id: 20,
            localCode: 'V-20',
            createdAtMs: 200,
            electronicInvoiceEnabled: 0,
            customerNameSnapshot: 'Consumidor final',
          ),
          sale(
            id: 19,
            localCode: 'V-19',
            createdAtMs: 190,
            electronicInvoiceEnabled: 1,
            electronicDocumentType: '31',
            customerNameSnapshot: 'Apyra',
            customerRncSnapshot: '131313131',
          ),
        ],
        remoteElectronic: [
          _document(
            saleId: 19,
            localCode: 'V-19',
            tipoDocumento: '31',
            ecf: 'E310000000019',
            estadoDgii: FacturaElectronicaModel.statusAccepted,
            createdAtMs: 190,
          ),
        ],
        localElectronic: const [],
        limit: 10,
      );

      expect(merged, hasLength(2));
      expect(merged[0].saleId, 20);
      expect(merged[0].tipoDocumento, 'venta_local');
      expect(merged[0].estadoInterno, 'LOCAL_ONLY');
      expect(merged[1].saleId, 19);
      expect(merged[1].ecf, 'E310000000019');
      expect(merged[1].estadoDgii, FacturaElectronicaModel.statusAccepted);
    },
  );

  test(
    'mergeRecentElectronicDocuments falls back to valid local cache when backend is empty',
    () {
      final merged = mergeRecentElectronicDocuments(
        remote: const [],
        local: [
          _document(
            saleId: 10,
            localCode: 'FAC-10',
            tipoDocumento: 'venta',
            ecf: 'E320000000010',
            createdAtMs: 10,
          ),
          _document(
            saleId: 20,
            localCode: 'FAC-20',
            tipoDocumento: '31',
            ecf: 'E310000000020',
            dgiiTrackId: 'TRK-20',
            estadoDgii: FacturaElectronicaModel.statusPending,
            estadoInterno: 'SUBMITTED',
            createdAtMs: 20,
          ),
          _document(
            saleId: 30,
            localCode: 'FAC-30',
            tipoDocumento: '31',
            ecf: 'E310000000030',
            estadoDgii: FacturaElectronicaModel.statusAccepted,
            createdAtMs: 30,
          ),
          _document(
            saleId: 40,
            localCode: 'FAC-40',
            tipoDocumento: 'venta_local',
            estadoInterno: 'LOCAL_ONLY',
            createdAtMs: 40,
          ),
        ],
        limit: 10,
      );

      expect(merged, hasLength(3));
      expect(merged[0].saleId, 30);
      expect(merged[0].estadoDgii, FacturaElectronicaModel.statusAccepted);
      expect(merged[1].saleId, 20);
      expect(merged[1].estadoDgii, FacturaElectronicaModel.statusPending);
      expect(merged[2].saleId, 10);
      expect(merged[2].estadoInterno, 'CACHE_ONLY');
    },
  );

  test(
    'mergeRecentElectronicDocuments excludes config placeholders without persisted identity when backend is empty',
    () {
      final merged = mergeRecentElectronicDocuments(
        remote: const [],
        local: [
          _document(
            saleId: 40,
            localCode: 'V-IDEM-40',
            tipoDocumento: '31',
            estadoDgii: FacturaElectronicaModel.statusConfigPending,
            estadoInterno: 'CONFIG_PENDING',
            createdAtMs: 40,
          ),
          _document(
            saleId: 41,
            localCode: 'FAC-41',
            tipoDocumento: '31',
            ecf: 'E310000000041',
            estadoDgii: FacturaElectronicaModel.statusAccepted,
            createdAtMs: 41,
          ),
        ],
        limit: 10,
      );

      expect(merged, hasLength(1));
      expect(merged.single.saleId, 41);
      expect(merged.single.ecf, 'E310000000041');
    },
  );

  test(
    'mergeRecentElectronicDocuments keeps backend truth and preserves E34 for the same sale',
    () {
      final merged = mergeRecentElectronicDocuments(
        remote: [
          _document(
            saleId: 30,
            localCode: 'FAC-30',
            tipoDocumento: '31',
            ecf: 'E310000000030',
            estadoDgii: FacturaElectronicaModel.statusAccepted,
            createdAtMs: 100,
            updatedAtMs: 100,
          ),
          _document(
            saleId: 30,
            localCode: 'NC-30',
            tipoDocumento: '34',
            ecf: 'E340000000030',
            estadoDgii: FacturaElectronicaModel.statusPending,
            createdAtMs: 200,
            updatedAtMs: 200,
          ),
        ],
        local: [
          _document(
            saleId: 30,
            localCode: 'FAC-30',
            tipoDocumento: '31',
            estadoInterno: 'CACHE_ONLY',
            createdAtMs: 50,
            updatedAtMs: 50,
          ),
        ],
        limit: 10,
      );

      expect(merged, hasLength(2));
      expect(merged.first.tipoDocumento, '34');
      expect(merged.last.ecf, 'E310000000030');
      expect(merged.last.estadoDgii, FacturaElectronicaModel.statusAccepted);
    },
  );
}
