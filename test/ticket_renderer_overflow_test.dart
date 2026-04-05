import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/printing/models/company_info.dart';
import 'package:fullpos/core/printing/models/ticket_data.dart';
import 'package:fullpos/core/printing/models/ticket_layout_config.dart';
import 'package:fullpos/core/printing/models/ticket_renderer.dart';
import 'package:fullpos/features/settings/data/printer_settings_model.dart';

TicketData _sampleSaleData() {
  return TicketData(
    ticketNumber: '003740',
    dateTime: DateTime(2026, 1, 12, 16, 5),
    cashierName: 'CAJA3',
    client: const ClientInfo(name: ''),
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
    electronicInvoiceCode: 'B020000000000058',
    type: TicketType.sale,
  );
}

List<String> _extractItemRows(List<String> lines) {
  final headerIndex = lines.indexWhere(
    (line) => line.contains('CANT') && line.contains('DESCRIPCION'),
  );
  expect(headerIndex, greaterThanOrEqualTo(0));

  final rows = <String>[];
  for (var index = headerIndex + 2; index < lines.length; index++) {
    final line = lines[index];
    if (RegExp(r'^-+$').hasMatch(line.trim())) {
      break;
    }
    if (line.trim().isNotEmpty) {
      rows.add(line);
    }
  }
  return rows;
}

double _parseTrailingMoney(String line) {
  final match = RegExp(r'(\d[\d,]*(?:\.\d{2})?)\s*$').firstMatch(line);
  if (match == null) return 0.0;
  return double.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0.0;
}

int _moneyEndIndex(String line) {
  final match = RegExp(r'(\d[\d,]*(?:\.\d{2})?)\s*$').firstMatch(line);
  return match?.end ?? -1;
}

bool _hasTrailingCents(String line) {
  return RegExp(r'\d[\d,]*\.\d{2}\s*$').hasMatch(line);
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
    electronicInvoiceCode: 'B020000000000058',
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
    showElectronicInvoiceReference: true,
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
  test(
    'Ticket POS no desborda y mantiene productos en una linea (32 chars)',
    () {
      const width = 32;
      final renderer = TicketRenderer(
        config: _configForWidth(width),
        company: _sampleCompany(),
      );

      final lines = renderer.buildLines(_sampleSaleData());

      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(width));
      }

      final itemRows = _extractItemRows(lines);
      expect(itemRows.length, equals(_sampleSaleData().items.length));
      expect(itemRows.first.contains('...'), isTrue);
      for (final row in itemRows) {
        expect(_parseTrailingMoney(row), greaterThan(0));
        expect(_hasTrailingCents(row), isTrue);
        expect(_moneyEndIndex(row), equals(width));
      }

      final totalLine = lines.firstWhere(
        (line) => line.contains('TOTAL:'),
        orElse: () => '',
      );
      expect(totalLine, isNot(equals('')));
      expect(_hasTrailingCents(totalLine), isTrue);
    },
  );

  test(
    'Ticket POS no desborda y mantiene productos en una linea (48 chars)',
    () {
      const width = 48;
      final renderer = TicketRenderer(
        config: _configForWidth(width),
        company: _sampleCompany(),
      );

      final lines = renderer.buildLines(_sampleSaleData());

      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(width));
      }

      expect(lines.any((line) => line.contains('FACTURA')), isTrue);
      expect(lines.any((line) => line.contains('FECHA: 12/01/2026')), isTrue);
      expect(lines.any((line) => line.contains('CAJERO: CAJA3')), isTrue);

      final itemRows = _extractItemRows(lines);
      expect(itemRows.length, equals(_sampleSaleData().items.length));
      for (final row in itemRows) {
        expect(_parseTrailingMoney(row), greaterThan(0));
        expect(_hasTrailingCents(row), isTrue);
        expect(_moneyEndIndex(row), equals(width));
      }

      final totalLine = lines.firstWhere(
        (line) => line.contains('TOTAL:'),
        orElse: () => '',
      );
      expect(totalLine, isNot(equals('')));
      expect(_hasTrailingCents(totalLine), isTrue);
    },
  );

  test('Ticket POS 42 chars usa tabla compacta y totales simples', () {
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

    // 2) Debe imprimir encabezado de tabla sin romper.
    final headerLine = lines.firstWhere(
      (l) => l.contains('CANT') && l.contains('DESCRIPCION'),
      orElse: () => '',
    );
    expect(headerLine, isNot(equals('')));
    expect(headerLine.contains('TOTAL'), isTrue);

    final itemRows = _extractItemRows(lines);
    expect(
      itemRows.length,
      equals(_sampleSaleDataWithZerosButItems().items.length),
    );
    expect(itemRows[1].contains('...'), isTrue);
    for (final row in itemRows) {
      expect(_hasTrailingCents(row), isTrue);
      expect(_moneyEndIndex(row), equals(width));
    }

    // 3) Debe imprimir TOTAL y EFECTIVO con formato compacto y valores > 0.
    final totalLine = lines.firstWhere(
      (l) => l.contains('TOTAL:'),
      orElse: () => '',
    );
    expect(totalLine, isNot(equals('')));
    expect(_parseTrailingMoney(totalLine), greaterThan(0));
    expect(_hasTrailingCents(totalLine), isTrue);

    final cashLine = lines.firstWhere(
      (l) => l.contains('EFECTIVO:'),
      orElse: () => '',
    );
    expect(cashLine, isNot(equals('')));
    expect(_parseTrailingMoney(cashLine), greaterThan(0));
    expect(_hasTrailingCents(cashLine), isTrue);
    expect(_moneyEndIndex(totalLine), equals(width));
    expect(_moneyEndIndex(cashLine), equals(width));
  });

  test('Ticket POS 80mm mantiene filas unicas y bloque de pago compacto', () {
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
    final headerLine = lines.firstWhere(
      (l) => l.contains('CANT') && l.contains('DESCRIPCION'),
      orElse: () => '',
    );
    expect(headerLine, isNot(equals('')));
    expect(headerLine.length, lessThanOrEqualTo(width));
    expect(headerLine.contains('TOTAL'), isTrue);

    final itemRows = _extractItemRows(lines);
    expect(
      itemRows.length,
      equals(_sampleSaleDataWithZerosButItems().items.length),
    );
    expect(itemRows.every((row) => _parseTrailingMoney(row) > 0), isTrue);
    expect(itemRows.every(_hasTrailingCents), isTrue);
    expect(itemRows.every((row) => _moneyEndIndex(row) == width), isTrue);

    // 3) Debe imprimir TOTAL y EFECTIVO con valores distintos de 0.00.
    final totalLine = lines.firstWhere(
      (l) => l.contains('TOTAL:'),
      orElse: () => '',
    );
    expect(totalLine, isNot(equals('')));
    expect(_parseTrailingMoney(totalLine), greaterThan(0));
    expect(_hasTrailingCents(totalLine), isTrue);

    final cashLine = lines.firstWhere(
      (l) => l.contains('EFECTIVO:'),
      orElse: () => '',
    );
    expect(cashLine, isNot(equals('')));
    expect(_parseTrailingMoney(cashLine), greaterThan(0));
    expect(_hasTrailingCents(cashLine), isTrue);
    expect(_moneyEndIndex(totalLine), equals(width));
    expect(_moneyEndIndex(cashLine), equals(width));
  });

  test('TicketLayoutConfig respeta anchos estandar para 58mm y 80mm', () {
    final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    final layout58 = TicketLayoutConfig.fromPrinterSettings(
      PrinterSettingsModel(
        paperWidthMm: 58,
        charsPerLine: 80,
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );
    final layout80 = TicketLayoutConfig.fromPrinterSettings(
      PrinterSettingsModel(
        paperWidthMm: 80,
        charsPerLine: 34,
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );

    expect(layout58.maxCharsPerLine, equals(32));
    expect(layout80.maxCharsPerLine, equals(42));
  });
}
