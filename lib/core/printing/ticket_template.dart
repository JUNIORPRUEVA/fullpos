import 'package:intl/intl.dart';
import '../services/app_configuration_service.dart';
import '../../features/settings/data/printer_settings_model.dart';
import '../../features/sales/data/sales_model.dart';

class TicketTemplate {
  final PrinterSettingsModel settings;
  final SaleModel sale;
  final List<SaleItemModel> items;
  final String? cashierName;

  TicketTemplate({
    required this.settings,
    required this.sale,
    required this.items,
    this.cashierName,
  });

  String generate() {
    final lines = <String>[];
    final width = settings.charsPerLine;
    final separator = '-' * width;

    final businessName = _resolveBusinessName(settings.headerBusinessName);

    // Header del negocio - solo si está habilitado
    if (settings.showBusinessData == 1) {
      lines.add(_center(businessName, width));
      if ((settings.headerRnc ?? '').isNotEmpty) {
        lines.add(_center('RNC: ${settings.headerRnc}', width));
      }
      if ((settings.headerAddress ?? '').isNotEmpty) {
        lines.add(_center(settings.headerAddress!, width));
      }
      if ((settings.headerPhone ?? '').isNotEmpty) {
        lines.add(_center('Tel: ${settings.headerPhone}', width));
      }
      if ((settings.headerExtra ?? '').isNotEmpty) {
        lines.add(_center(settings.headerExtra!, width));
      }
      lines.add(separator);
    }

    // Fecha y hora
    if (settings.showDatetime == 1) {
      final now = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
      final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
      lines.add(_center(dateStr, width));
    }

    // Ticket ID
    if (settings.showCode == 1) {
      lines.add(_center('Ticket #${sale.localCode}', width));
    }

    // NCF
    if ((settings.showNcf == 1 || sale.fiscalEnabled == 1) &&
        (sale.ncfFull ?? '').isNotEmpty) {
      lines.add(_center('NCF: ${sale.ncfFull}', width));
    }

    lines.add(separator);

    // Cliente
    if (settings.showClient == 1 &&
        (sale.customerNameSnapshot ?? '').isNotEmpty) {
      lines.add('Cliente: ${sale.customerNameSnapshot}');
      if ((sale.customerPhoneSnapshot ?? '').isNotEmpty) {
        lines.add('Tel: ${sale.customerPhoneSnapshot}');
      }
      lines.add(separator);
    }

    // Cajero
    if (settings.showCashier == 1 && (cashierName ?? '').isNotEmpty) {
      lines.add('Cajero: $cashierName');
      lines.add(separator);
    }

    // Detalle de items
    lines.add(_padRight('ITEM', width ~/ 2) + _padRight('TOTAL', width ~/ 2));
    lines.add(
      _padRight('QTY', width ~/ 3) +
          _padRight('PRECIO', width ~/ 3) +
          _padRight('', width ~/ 3),
    );
    lines.add(separator);

    for (final item in items) {
      final itemLine =
          '${item.productNameSnapshot}\n'
          '${item.qty} x ${_formatCurrency(item.unitPrice)} = ${_formatCurrency(item.totalLine)}';
      lines.add(itemLine);
    }

    lines.add(separator);

    // Totales - solo mostrar desglose si está habilitado
    if (settings.showSubtotalItbisTotal == 1) {
      lines.add(
        _padRight('Subtotal:', (width * 0.6).toInt()) +
            _padLeft(_formatCurrency(sale.subtotal), (width * 0.4).toInt()),
      );

      if ((sale.discountTotal) > 0) {
        lines.add(
          _padRight('Descuento:', (width * 0.6).toInt()) +
              _padLeft(
                '-${_formatCurrency(sale.discountTotal)}',
                (width * 0.4).toInt(),
              ),
        );
      }

      if (settings.showItbis == 1 && sale.itbisAmount > 0) {
        lines.add(
          _padRight(
                'ITBIS (${(sale.itbisRate * 100).toStringAsFixed(0)}%):',
                (width * 0.6).toInt(),
              ) +
              _padLeft(
                _formatCurrency(sale.itbisAmount),
                (width * 0.4).toInt(),
              ),
        );
      }

      lines.add(separator);
    }

    // TOTAL siempre se muestra
    lines.add(
      _padRight('TOTAL:', (width * 0.6).toInt()) +
          _padLeft(_formatCurrency(sale.total), (width * 0.4).toInt()),
    );

    lines.add(separator);

    // Forma de pago
    if (settings.showPaymentMethod == 1 &&
        (sale.paymentMethod ?? '').isNotEmpty) {
      lines.add(
        _center(
          'Pago: ${_translatePaymentMethod(sale.paymentMethod!)}',
          width,
        ),
      );
    }

    if ((sale.paymentMethod ?? '').toLowerCase() == 'credit') {
      final interestRate = sale.creditInterestRate;
      final interestAmount = sale.total * (interestRate / 100);
      final totalDue = sale.total + interestAmount;
      lines.add(separator);
      lines.add(_center('CREDITO', width));
      lines.add(
        _padRight('Interes:', (width * 0.6).toInt()) +
            _padLeft('${interestRate.toStringAsFixed(2)}%', (width * 0.4).toInt()),
      );
      lines.add(
        _padRight('Total credito:', (width * 0.6).toInt()) +
            _padLeft(_formatCurrency(totalDue), (width * 0.4).toInt()),
      );
      if (sale.creditTermDays != null && sale.creditTermDays! > 0) {
        lines.add(
          _padRight('Plazo (dias):', (width * 0.6).toInt()) +
              _padLeft('${sale.creditTermDays}', (width * 0.4).toInt()),
        );
      }
      if (sale.creditInstallments != null && sale.creditInstallments! > 0) {
        final installmentAmount = totalDue / sale.creditInstallments!;
        lines.add(
          _padRight('Cuotas:', (width * 0.6).toInt()) +
              _padLeft('${sale.creditInstallments}', (width * 0.4).toInt()),
        );
        lines.add(
          _padRight('Valor cuota:', (width * 0.6).toInt()) +
              _padLeft(_formatCurrency(installmentAmount), (width * 0.4).toInt()),
        );
      }
      if (sale.creditDueDateMs != null) {
        final dueDate =
            DateTime.fromMillisecondsSinceEpoch(sale.creditDueDateMs!);
        final dueStr = DateFormat('dd/MM/yyyy').format(dueDate);
        lines.add(
          _padRight('Vence:', (width * 0.6).toInt()) +
              _padLeft(dueStr, (width * 0.4).toInt()),
        );
      }
      if ((sale.creditNote ?? '').isNotEmpty) {
        lines.add('Nota: ${sale.creditNote}');
      }
      lines.add(separator);
    }

    if (sale.paidAmount > 0) {
      lines.add(
        _padRight('Pagado:', (width * 0.6).toInt()) +
            _padLeft(_formatCurrency(sale.paidAmount), (width * 0.4).toInt()),
      );
    }

    if (sale.changeAmount > 0) {
      lines.add(
        _padRight('Cambio:', (width * 0.6).toInt()) +
            _padLeft(_formatCurrency(sale.changeAmount), (width * 0.4).toInt()),
      );
    }

    lines.add(separator);

    // Footer
    lines.add(_center(settings.footerMessage, width));
    lines.add('');
    lines.add(_center(_resolvePoweredByLine(), width));

    if (settings.autoCut == 1) {
      lines.add('\n\n\n\n'); // Para que la impresora corte
    }

    return lines.join('\n');
  }

  String _resolveBusinessName(String headerBusinessName) {
    final header = headerBusinessName.trim();
    final headerUpper = header.toUpperCase();
    final business = appConfigService.getBusinessName().trim();
    final shouldFallback =
        header.isEmpty ||
        headerUpper == 'FULLTECH, SRL' ||
        headerUpper == 'FULLPOS';
    if (shouldFallback && business.isNotEmpty) {
      return business;
    }
    return header.isNotEmpty ? header : business;
  }

  String _resolvePoweredByLine() {
    return 'Powered by FULLTECH, SRL';
  }

  String _translatePaymentMethod(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mixed':
        return 'Mixto';
      case 'credit':
        return 'Credito';
      case 'layaway':
        return 'Apartado';
      default:
        return method;
    }
  }

  /// Genera un ticket de prueba (demo)
  static String generateDemoTicket(PrinterSettingsModel settings) {
    final demoSale = SaleModel(
      localCode: 'DEMO-001',
      kind: 'invoice',
      subtotal: 1000.0,
      total: 1180.0,
      itbisAmount: 180.0,
      itbisRate: 0.18,
      itbisEnabled: 1,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      customerNameSnapshot: 'Cliente Demo',
      customerPhoneSnapshot: '(829) 531-9442',
      paymentMethod: 'cash',
      paidAmount: 1200.0,
      changeAmount: 20.0,
    );

    final demoItems = [
      SaleItemModel(
        saleId: 0,
        productCodeSnapshot: 'PROD-001',
        productNameSnapshot: 'Producto de Prueba',
        qty: 2.0,
        unitPrice: 500.0,
        totalLine: 1000.0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    final template = TicketTemplate(
      settings: settings,
      sale: demoSale,
      items: demoItems,
    );

    return template.generate();
  }

  String _center(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final padding = (width - text.length) ~/ 2;
    return ' ' * padding + text;
  }

  String _padRight(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    return text + ' ' * (width - text.length);
  }

  String _padLeft(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    return ' ' * (width - text.length) + text;
  }

  String _formatCurrency(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }
}
