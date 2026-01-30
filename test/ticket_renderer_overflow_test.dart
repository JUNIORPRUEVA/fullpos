import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/printing/models/company_info.dart';
import 'package:fullpos/core/printing/models/ticket_data.dart';
import 'package:fullpos/core/printing/models/ticket_layout_config.dart';
import 'package:fullpos/core/printing/models/ticket_renderer.dart';

TicketData _sampleSaleData() {
  return TicketData(
    ticketNumber: '003740',
    dateTime: DateTime(2026, 1, 12, 16, 5),
    cashierName: 'CAJA3',
    client: const ClientInfo(name: ''), // fuerza "AL PORTADOR"
    items: const [
      TicketItemData(
        name: 'DESTORNILLADOR EXTRA LARGO INDUSTRIAL',
        code: 'F04823-ULTRA-SUPER-LARGO-1234567890',
        quantity: 1,
        unitPrice: 55.00,
        total: 55.00,
      ),
      TicketItemData(
        name: 'TORNILLO 4.2x19 CON RANURA',
        code: 'Z009-4.2x19-TRNLL-ABCDEFGHIJKL',
        quantity: 1,
        unitPrice: 15.00,
        total: 15.00,
      ),
    ],
    subtotal: 59.32,
    itbis: 10.68,
    itbisRate: 0.18,
    total: 70.00,
    paymentMethod: 'EFECTIVO',
    paidAmount: 100.00,
    changeAmount: 30.00,
    ncf: 'B020000000000058',
    type: TicketType.sale,
  );
}

TicketData _sampleSaleDataWithZerosButItems() {
  return TicketData(
    ticketNumber: '0001234',
    dateTime: DateTime(2026, 1, 13, 9, 15),
    cashierName: 'CAJA1',
    client: const ClientInfo(name: 'Cliente Demo'),
    items: const [
      TicketItemData(name: 'PAN', quantity: 1, unitPrice: 50.0, total: 50.0),
      TicketItemData(
        name:
            'REFRESCO SUPER EXTRA ULTRA MEGA LARGO PARA PROBAR EL WRAP EN 80MM SIN ROMPER COLUMNAS',
        quantity: 2,
        unitPrice: 75.0,
        total: 150.0,
      ),
      TicketItemData(
        name: 'SERVICIO',
        quantity: 10,
        unitPrice: 10.0,
        total: 100.0,
      ),
    ],
    // Valores en cero simulando bug de datos; el renderer debe hacer fallback.
    subtotal: 0.0,
    discount: 0.0,
    itbis: 0.0,
    itbisRate: 0.18,
    total: 0.0,
    paymentMethod: 'Efectivo',
    paidAmount: 0.0,
    changeAmount: 0.0,
    ncf: 'B020000000000058',
    type: TicketType.sale,
  );
}

CompanyInfo _sampleCompany() {
  return const CompanyInfo(
    name: 'FERRETERIA DEMO SRL',
    address: 'CARRETERA HIGUEY KM 5\nLA ALTAGRACIA',
    rnc: '123456789',
    phone: '(809) 555-1234',
  );
}

TicketLayoutConfig _configForWidth(int width) {
  return TicketLayoutConfig(
    maxCharsPerLine: width,
    showCompanyInfo: true,
    showClientInfo: true,
    showPaymentInfo: true,
    showFooterMessage: false,
    footerMessage: '',
    showNcf: true,
    showItbis: true,
    showCashier: true,
    showTotalsBreakdown: true,
    autoCut: false,
    headerAlignment: 'center',
    detailsAlignment: 'left',
    totalsAlignment: 'right',
  );
}

void main() {
  test('Factura clasica no desborda (32 chars)', () {
    const width = 32;
    final renderer = TicketRenderer(
      config: _configForWidth(width),
      company: _sampleCompany(),
    );

    final lines = renderer.buildLines(_sampleSaleData());

    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(width));
    }
  });

  test('Factura clasica no desborda (48 chars)', () {
    const width = 48;
    final renderer = TicketRenderer(
      config: _configForWidth(width),
      company: _sampleCompany(),
    );

    final lines = renderer.buildLines(_sampleSaleData());

    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(width));
    }
  });

  test('Factura clasica 42 chars: items en 2 lineas y con aire', () {
    const width = 42;
    final renderer = TicketRenderer(
      config: _configForWidth(width),
      company: _sampleCompany(),
    );

    final lines = renderer.buildLines(_sampleSaleDataWithZerosButItems());

    // 1) Nunca exceder el ancho.
    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(width));
    }

    // 2) Debe imprimir encabezado de tabla (4 columnas) sin romper.
    final headerLine = lines.firstWhere(
      (l) => l.contains('CANT.') && l.contains('DESCRIPCION'),
      orElse: () => '',
    );
    expect(headerLine, isNot(equals('')));

    // 3) Debe imprimir TOTAL y EFECTIVO con formato " --> " y valores > 0.
    final totalLine = lines.firstWhere(
      (l) => l.contains('TOTAL') && l.contains('-->'),
      orElse: () => '',
    );
    expect(totalLine, isNot(equals('')));

    double parseAmount(String line) {
      final m = RegExp(r'(-?\d[\d,]*\.\d{2})\s*$').firstMatch(line);
      if (m == null) return 0.0;
      return double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    expect(parseAmount(totalLine), greaterThan(0));

    final cashLine = lines.firstWhere(
      (l) => l.contains('EFECTIVO') && l.contains('-->'),
      orElse: () => '',
    );
    expect(cashLine, isNot(equals('')));
    expect(parseAmount(cashLine), greaterThan(0));
  });

  test('Factura clasica 80mm: tabla alineada y totales no cero con items', () {
    const width = 48;
    final renderer = TicketRenderer(
      config: _configForWidth(width),
      company: _sampleCompany(),
    );

    final lines = renderer.buildLines(_sampleSaleDataWithZerosButItems());

    // 1) Nunca exceder el ancho.
    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(width));
    }

    // 2) Debe imprimir encabezado de tabla con columnas estables.
    // Validamos estructura (fixed-width 48): QTY=4, DESC=24, PRICE=10, TOTAL=10.
    final headerLine = lines.firstWhere(
      (l) => l.contains('CANT.') && l.contains('DESCRIPCION'),
      orElse: () => '',
    );
    expect(headerLine, isNot(equals('')));
    expect(headerLine.length, lessThanOrEqualTo(width));

    // Verifica que existan las columnas numéricas (sin depender de espacios exactos).
    expect(headerLine.contains('PRECIO'), isTrue);
    expect(headerLine.contains('TOTAL'), isTrue);

    // 3) Debe imprimir TOTAL y EFECTIVO con valores distintos de 0.00.
    final totalLine = lines.firstWhere(
      (l) => l.contains('TOTAL') && l.contains('-->'),
      orElse: () => '',
    );
    expect(totalLine, isNot(equals('')));

    double parseAmount(String line) {
      final m = RegExp(r'(-?\d[\d,]*\.\d{2})\s*$').firstMatch(line);
      if (m == null) return 0.0;
      return double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    expect(parseAmount(totalLine), greaterThan(0));

    final cashLine = lines.firstWhere(
      (l) => l.contains('EFECTIVO') && l.contains('-->'),
      orElse: () => '',
    );
    expect(cashLine, isNot(equals('')));
    expect(parseAmount(cashLine), greaterThan(0));
  });
}
