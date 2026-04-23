import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/factura_electronica_model.dart';

FacturaElectronicaModel _model({
  required String estadoDgii,
  String? mensajeDgii,
  String? estadoInterno,
}) {
  return FacturaElectronicaModel(
    saleId: 1,
    localCode: 'V-TEST-1',
    tipoDocumento: '32',
    estadoDgii: estadoDgii,
    mensajeDgii: mensajeDgii,
    estadoInterno: estadoInterno,
    montoTotal: 100,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  test('statusLabel shows specific config reason for missing certificate', () {
    final model = _model(
      estadoDgii: FacturaElectronicaModel.statusConfigPending,
      mensajeDgii: 'La compañía no tiene un certificado electrónico activo',
      estadoInterno: 'CONFIG_PENDING',
    );

    expect(model.statusLabel, 'Sin cert.');
  });

  test('statusLabel shows backend FE when master key is missing', () {
    final model = _model(
      estadoDgii: FacturaElectronicaModel.statusConfigPending,
      mensajeDgii:
          'La facturación electrónica requiere FE_MASTER_ENCRYPTION_KEY configurada',
      estadoInterno: 'CONFIG_PENDING',
    );

    expect(model.statusLabel, 'Backend FE');
  });

  test('statusLabel shows sale issue for legacy not-found placeholders', () {
    final model = _model(
      estadoDgii: FacturaElectronicaModel.statusConfigPending,
      mensajeDgii: 'Venta no encontrada',
      estadoInterno: 'CONFIG_PENDING',
    );

    expect(model.statusLabel, 'Venta');
  });

  test('statusLabel shows submission pending state consistently', () {
    final model = _model(
      estadoDgii: FacturaElectronicaModel.statusLocal,
      estadoInterno: 'SUBMISSION_PENDING',
    );

    expect(model.statusLabel, 'Enviando');
  });
}
