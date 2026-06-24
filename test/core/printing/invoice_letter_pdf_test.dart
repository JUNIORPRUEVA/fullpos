import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/printing/invoice_letter_pdf.dart';
import 'package:fullpos/features/sales/data/sales_model.dart';
import 'package:fullpos/features/settings/data/business_settings_model.dart';

void main() {
  test('generates redesigned invoice PDF bytes', () async {
    final now = DateTime(2026, 1, 15, 10, 30).millisecondsSinceEpoch;
    final sale = SaleModel(
      id: null,
      localCode: 'FAC-1024',
      kind: 'invoice',
      customerNameSnapshot: 'Cliente de Prueba',
      customerRncSnapshot: '00112345678',
      itbisEnabled: 1,
      itbisRate: 0.18,
      discountTotal: 100,
      subtotal: 900,
      itbisAmount: 162,
      total: 1062,
      paymentMethod: 'cash',
      createdAtMs: now,
      updatedAtMs: now,
    );

    final bytes = await InvoiceLetterPdf.generate(
      sale: sale,
      items: [
        SaleItemModel(
          saleId: 0,
          productCodeSnapshot: 'SKU-1',
          productNameSnapshot:
              'Producto con nombre largo para validar ajuste en tabla',
          qty: 2,
          unitPrice: 500,
          discountLine: 100,
          totalLine: 900,
          createdAtMs: now,
        ),
      ],
      business: BusinessSettings(
        businessName: 'FULLTECH, SRL',
        rnc: '131000000',
        phone: '809-000-0000',
        email: 'ventas@example.com',
        address: 'Av. Principal 123',
        city: 'Santo Domingo',
        receiptHeader: 'Factura generada para prueba.',
      ),
      brandColorArgb: 0xFF1A56DB,
      cashierName: 'Caja 1',
      warrantyPolicy: '',
      footerMessage: '',
    );

    expect(bytes, isNotEmpty);
    expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
  });
}
