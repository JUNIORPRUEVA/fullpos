import 'package:flutter/foundation.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';
import 'package:usb_esc_printer_windows/usb_esc_printer_windows.dart' as usb_esc;

import 'receipt_typography.dart';

class ReceiptPrinterService {
  ReceiptPrinterService._();

  static const int _charsPerLine80mm = 48;
  static const String _preferredCodeTable = 'CP1252';

  static Future<List<int>> buildTicketBytes({
    required ReceiptPrintPayload payload,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    final bytes = <int>[];
    final hasClientBlock = (payload.clientName ?? '').trim().isNotEmpty;
    final hasDateBlock = (payload.dateText ?? '').trim().isNotEmpty;
    final hasTimeBlock = (payload.timeText ?? '').trim().isNotEmpty;
    final dateTimeText = [
      if (hasDateBlock) payload.dateText!.toUpperCase(),
      if (hasTimeBlock) payload.timeText!.toUpperCase(),
    ].join(' ');

    bytes.addAll(generator.reset());
    bytes.addAll(generator.setGlobalCodeTable(_preferredCodeTable));
    bytes.addAll(
      generator.text(
        payload.companyName.toUpperCase(),
        styles: const PosStyles(
          fontType: PosFontType.fontA,
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          codeTable: _preferredCodeTable,
        ),
        maxCharsPerLine: _charsPerLine80mm,
      ),
    );
    bytes.addAll(
      generator.text(
        payload.documentTitle.toUpperCase(),
        styles: const PosStyles(
          fontType: PosFontType.fontA,
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size1,
          width: PosTextSize.size1,
          codeTable: _preferredCodeTable,
        ),
        maxCharsPerLine: _charsPerLine80mm,
      ),
    );
    bytes.addAll(generator.hr());

    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'DOC: ${payload.documentCode.toUpperCase()}',
          width: 6,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.left,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
        PosColumn(
          text: 'CAJA: ${payload.cashierName.toUpperCase()}',
          width: 6,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.right,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
      ]),
    );

    if (hasClientBlock || hasDateBlock || hasTimeBlock) {
      bytes.addAll(
        generator.row([
          PosColumn(
            text: hasClientBlock
                ? 'CLI: ${_truncate(payload.clientName!, 24).toUpperCase()}'
                : '',
            width: 7,
            styles: const PosStyles(
              fontType: PosFontType.fontA,
              align: PosAlign.left,
              bold: true,
              codeTable: _preferredCodeTable,
            ),
          ),
          PosColumn(
            text: (hasDateBlock || hasTimeBlock)
                ? 'FECHA: ${_truncate(dateTimeText, 14).toUpperCase()}'
                : '',
            width: 5,
            styles: const PosStyles(
              fontType: PosFontType.fontA,
              align: PosAlign.right,
              bold: true,
              codeTable: _preferredCodeTable,
            ),
          ),
        ]),
      );
    }

    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'CANT',
          width: 2,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.right,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
        PosColumn(
          text: 'PRODUCTO',
          width: 5,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.left,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
        PosColumn(
          text: 'P/U',
          width: 2,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.right,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
        PosColumn(
          text: 'TOTAL',
          width: 3,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.right,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
      ]),
    );

    for (final item in payload.items) {
      bytes.addAll(
        generator.row([
          PosColumn(
            text: _formatQty(item.quantity),
            width: 2,
            styles: const PosStyles(
              fontType: PosFontType.fontA,
              align: PosAlign.right,
              bold: true,
              codeTable: _preferredCodeTable,
            ),
          ),
          PosColumn(
            text: _truncate(item.productName.toUpperCase(), 18),
            width: 5,
            styles: const PosStyles(
              fontType: PosFontType.fontA,
              align: PosAlign.left,
              codeTable: _preferredCodeTable,
            ),
          ),
          PosColumn(
            text: ReceiptTypography.money(item.unitPrice),
            width: 2,
            styles: const PosStyles(
              fontType: PosFontType.fontA,
              align: PosAlign.right,
              codeTable: _preferredCodeTable,
            ),
          ),
          PosColumn(
            text: ReceiptTypography.money(item.total),
            width: 3,
            styles: const PosStyles(
              fontType: PosFontType.fontA,
              align: PosAlign.right,
              bold: true,
              codeTable: _preferredCodeTable,
            ),
          ),
        ]),
      );
    }

    bytes.addAll(generator.hr());
    bytes.addAll(_amountRow(generator, 'SUBT.', payload.subtotal));
    if (payload.itbis > 0) {
      bytes.addAll(_amountRow(generator, 'ITBIS', payload.itbis));
    }
    bytes.addAll(generator.hr());
    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'TOTAL',
          width: 5,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
            reverse: true,
            codeTable: _preferredCodeTable,
          ),
        ),
        PosColumn(
          text: ReceiptTypography.money(payload.total),
          width: 7,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
            reverse: true,
            codeTable: _preferredCodeTable,
          ),
        ),
      ]),
    );
    bytes.addAll(generator.hr());

    final paidAmount = payload.paidAmount <= 0 ? payload.total : payload.paidAmount;
    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'PAGO',
          width: 4,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.left,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
        PosColumn(
          text: _truncate(payload.paymentMethod.toUpperCase(), 20),
          width: 8,
          styles: const PosStyles(
            fontType: PosFontType.fontA,
            align: PosAlign.right,
            bold: true,
            codeTable: _preferredCodeTable,
          ),
        ),
      ]),
    );
    bytes.addAll(_amountRow(generator, 'RECIBIDO', paidAmount));
    if (payload.changeAmount > 0) {
      bytes.addAll(_amountRow(generator, 'CAMBIO', payload.changeAmount));
    }
    bytes.addAll(
      generator.text(
        (payload.footerMessage ?? 'GRACIAS POR SU COMPRA').toUpperCase(),
        styles: const PosStyles(
          fontType: PosFontType.fontA,
          align: PosAlign.center,
          bold: true,
          codeTable: _preferredCodeTable,
        ),
        maxCharsPerLine: _charsPerLine80mm,
      ),
    );
    if (payload.cutPaper) {
      bytes.addAll(generator.cut());
    }

    return bytes;
  }

  static Future<ReceiptPrinterResult> printNetworkReceipt({
    required String host,
    int port = 9100,
    required ReceiptPrintPayload payload,
  }) async {
    try {
      final manager = PrinterNetworkManager(
        host,
        port: port,
        timeout: const Duration(seconds: 5),
      );
      final connection = await manager.connect();
      if (connection != PosPrintResult.success &&
          connection != PosPrintResult.printerConnected) {
        return ReceiptPrinterResult(
          success: false,
          message: connection.msg,
        );
      }

      final bytes = await buildTicketBytes(payload: payload);
      final result = await manager.printTicket(bytes, isDisconnect: true);
      return ReceiptPrinterResult(
        success: result == PosPrintResult.success,
        message: result.msg,
      );
    } catch (error, stackTrace) {
      debugPrint('ReceiptPrinterService network error: $error\n$stackTrace');
      return ReceiptPrinterResult(
        success: false,
        message: 'NETWORK PRINT ERROR: $error',
      );
    }
  }

  static Future<ReceiptPrinterResult> printUsbReceipt({
    required String printerName,
    required ReceiptPrintPayload payload,
  }) async {
    try {
      final bytes = await buildTicketBytes(payload: payload);
      final response = await usb_esc.sendPrintRequest(bytes, printerName);
      final success = !response.toLowerCase().contains('error');
      return ReceiptPrinterResult(
        success: success,
        message: response,
      );
    } catch (error, stackTrace) {
      debugPrint('ReceiptPrinterService USB error: $error\n$stackTrace');
      return ReceiptPrinterResult(
        success: false,
        message: 'USB PRINT ERROR: $error',
      );
    }
  }

  static Future<ReceiptPrinterResult> printExampleUsbReceipt({
    required String printerName,
  }) {
    return printUsbReceipt(
      printerName: printerName,
      payload: ReceiptPrintPayload.example(),
    );
  }

  static List<int> _amountRow(
    Generator generator,
    String label,
    double amount,
  ) {
    return generator.row([
      PosColumn(
        text: label.toUpperCase(),
        width: 4,
        styles: const PosStyles(
          fontType: PosFontType.fontA,
          align: PosAlign.left,
          bold: true,
          codeTable: _preferredCodeTable,
        ),
      ),
      PosColumn(
        text: ReceiptTypography.money(amount),
        width: 8,
        styles: const PosStyles(
          fontType: PosFontType.fontA,
          align: PosAlign.right,
          bold: true,
          codeTable: _preferredCodeTable,
        ),
      ),
    ]);
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength - 3)}...';
  }

  static String _formatQty(double quantity) {
    final isWhole = quantity.truncateToDouble() == quantity;
    return isWhole ? quantity.toStringAsFixed(0) : quantity.toStringAsFixed(2);
  }
}

class ReceiptPrintPayload {
  final String companyName;
  final String documentTitle;
  final String documentCode;
  final String cashierName;
  final String? clientName;
  final String? dateText;
  final String? timeText;
  final List<ReceiptPrintItem> items;
  final double subtotal;
  final double itbis;
  final double total;
  final double paidAmount;
  final double changeAmount;
  final String paymentMethod;
  final String? footerMessage;
  final bool cutPaper;

  const ReceiptPrintPayload({
    required this.companyName,
    required this.documentTitle,
    required this.documentCode,
    required this.cashierName,
    this.clientName,
    this.dateText,
    this.timeText,
    required this.items,
    required this.subtotal,
    required this.itbis,
    required this.total,
    required this.paidAmount,
    required this.changeAmount,
    required this.paymentMethod,
    this.footerMessage,
    this.cutPaper = true,
  });

  factory ReceiptPrintPayload.example() {
    return const ReceiptPrintPayload(
      companyName: 'FULLPOS DEMO',
      documentTitle: 'FACTURA DE CONSUMO',
      documentCode: 'FAC-2048',
      cashierName: 'CAJA 1',
      clientName: 'CLIENTE GENERAL',
      dateText: '13/04/2026',
      timeText: '06:45 PM',
      items: [
        ReceiptPrintItem(
          quantity: 1,
          productName: 'ARROZ SELECTO 5LB',
          unitPrice: 340,
          total: 340,
        ),
        ReceiptPrintItem(
          quantity: 2,
          productName: 'LECHE ENTERA UHT',
          unitPrice: 85,
          total: 170,
        ),
      ],
      subtotal: 510,
      itbis: 91.80,
      total: 601.80,
      paidAmount: 1000,
      changeAmount: 398.20,
      paymentMethod: 'EFECTIVO',
      footerMessage: 'GRACIAS POR SU COMPRA',
    );
  }
}

class ReceiptPrintItem {
  final double quantity;
  final String productName;
  final double unitPrice;
  final double total;

  const ReceiptPrintItem({
    required this.quantity,
    required this.productName,
    required this.unitPrice,
    required this.total,
  });
}

class ReceiptPrinterResult {
  final bool success;
  final String message;

  const ReceiptPrinterResult({
    required this.success,
    required this.message,
  });
}