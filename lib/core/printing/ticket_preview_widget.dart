import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/app_configuration_service.dart';
import '../../features/settings/data/printer_settings_model.dart';

/// Widget que muestra una vista previa del ticket como se imprimiría
/// Estilo profesional tipo factura ejecutiva
class TicketPreviewWidget extends StatelessWidget {
  final PrinterSettingsModel settings;
  final TicketPreviewData? data;

  const TicketPreviewWidget({super.key, required this.settings, this.data});

  @override
  Widget build(BuildContext context) {
    final previewData = data ?? TicketPreviewData.demo();
    final width = settings.paperWidthMm == 58 ? 200.0 : 280.0;
    final fontSize = settings.fontSizeValue;
    final fontFamily = settings.fontFamilyName;

    final businessName = _resolveBusinessName(settings.headerBusinessName);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 8.0 + settings.leftMargin.toDouble(),
          right: 8.0 + settings.rightMargin.toDouble(),
          top: settings.topMargin.toDouble(),
          bottom: settings.bottomMargin.toDouble(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // === LOGO (si está habilitado) ===
            if (settings.showLogo == 1) ...[
              Container(
                width: settings.logoSize.toDouble(),
                height: settings.logoSize.toDouble(),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Icon(
                  Icons.store,
                  size: settings.logoSize * 0.6,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // === HEADER - NOMBRE DEL NEGOCIO ===
            Text(
              businessName.toUpperCase(),
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize + 3,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),

            // Subtítulo FACTURA
            const SizedBox(height: 2),
            Text(
              'FACTURA',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize + 1,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),

            _buildDivider(settings.charsPerLine, fontFamily),

            // === DATOS DEL NEGOCIO ===
            if (settings.showBusinessData == 1) ...[
              if ((settings.headerRnc ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'RNC: ${settings.headerRnc}',
                  style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                  textAlign: TextAlign.center,
                ),
              ],
              if ((settings.headerAddress ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  settings.headerAddress!,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize - 1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
              if ((settings.headerPhone ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Tel: ${settings.headerPhone}',
                  style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                  textAlign: TextAlign.center,
                ),
              ],
              if ((settings.headerExtra ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  settings.headerExtra!,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize - 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 4),
              _buildDivider(settings.charsPerLine, fontFamily),
            ],

            // === CLIENTE ===
            if (settings.showClient == 1 && previewData.clientName != null) ...[
              const SizedBox(height: 4),
              _buildRow(
                'Cliente:',
                previewData.clientName!,
                fontSize,
                fontFamily,
              ),
              if (previewData.clientPhone != null)
                _buildRow(
                  'Tel:',
                  previewData.clientPhone!,
                  fontSize,
                  fontFamily,
                ),
            ],

            // === FECHA Y CÓDIGO ===
            if (settings.showDatetime == 1) ...[
              const SizedBox(height: 4),
              _buildRow(
                'Fecha:',
                DateFormat('dd/MM/yyyy - HH:mm').format(previewData.dateTime),
                fontSize,
                fontFamily,
              ),
            ],

            if (settings.showCode == 1) ...[
              const SizedBox(height: 2),
              _buildRow(
                'Ticket:',
                '#${previewData.ticketCode}',
                fontSize,
                fontFamily,
                isBold: true,
              ),
            ],

            // === NCF ===
            if (settings.showNcf == 1 &&
                (previewData.ncf ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              _buildRow('NCF:', previewData.ncf!, fontSize, fontFamily),
            ],

            // === CAJERO ===
            if (settings.showCashier == 1 &&
                previewData.cashierName != null) ...[
              const SizedBox(height: 2),
              _buildRow(
                'Cajero:',
                previewData.cashierName!,
                fontSize,
                fontFamily,
              ),
            ],

            const SizedBox(height: 4),
            _buildDivider(settings.charsPerLine, fontFamily),

            // === ENCABEZADO DE ITEMS ===
            const SizedBox(height: 4),
            _buildItemHeader(fontSize, fontFamily),
            _buildDivider(settings.charsPerLine, fontFamily),

            // === ITEMS ===
            const SizedBox(height: 4),
            for (final item in previewData.items) ...[
              _buildItemRow(item, fontSize, fontFamily),
              const SizedBox(height: 2),
            ],

            _buildDivider(settings.charsPerLine, fontFamily),

            // === TOTALES ===
            if (settings.showSubtotalItbisTotal == 1) ...[
              const SizedBox(height: 4),
              _buildRow(
                'SUBTOTAL:',
                _formatCurrency(previewData.subtotal),
                fontSize,
                fontFamily,
              ),

              if (settings.showDiscounts == 1 && previewData.discount > 0) ...[
                const SizedBox(height: 2),
                _buildRow(
                  'DESCUENTO:',
                  '-${_formatCurrency(previewData.discount)}',
                  fontSize,
                  fontFamily,
                  valueColor: Colors.red.shade700,
                ),
              ],

              if (settings.showItbis == 1 && previewData.itbis > 0) ...[
                const SizedBox(height: 2),
                _buildRow(
                  'ITBIS ${(settings.itbisRate * 100).toStringAsFixed(0)}%:',
                  _formatCurrency(previewData.itbis),
                  fontSize,
                  fontFamily,
                ),
              ],

              const SizedBox(height: 4),
              _buildDivider(settings.charsPerLine, fontFamily),
              const SizedBox(height: 4),

              // TOTAL DESTACADO
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _buildRow(
                  'TOTAL A PAGAR:',
                  _formatCurrency(previewData.total),
                  fontSize + 2,
                  fontFamily,
                  isBold: true,
                ),
              ),
            ],

            _buildDivider(settings.charsPerLine, fontFamily),

            // === FORMA DE PAGO ===
            if (settings.showPaymentMethod == 1) ...[
              const SizedBox(height: 4),
              Text(
                'MÉTODO DE PAGO',
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              _buildDivider(settings.charsPerLine, fontFamily),
              const SizedBox(height: 2),
              for (final payment in previewData.payments)
                _buildRow(
                  '${_paymentLabel(payment.method)}:',
                  _formatCurrency(payment.amount),
                  fontSize,
                  fontFamily,
                ),
              if (previewData.change > 0) ...[
                const SizedBox(height: 2),
                _buildRow(
                  'Cambio:',
                  _formatCurrency(previewData.change),
                  fontSize,
                  fontFamily,
                  valueColor: Colors.green.shade700,
                ),
              ],
              _buildDivider(settings.charsPerLine, fontFamily),
            ],

            // === FOOTER ===
            const SizedBox(height: 8),
            Text(
              settings.footerMessage,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _resolvePoweredByLine(),
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize - 2,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),

            // Espacio para corte
            if (settings.autoCut == 1) const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Construye el encabezado de la tabla de items
  Widget _buildItemHeader(double fontSize, String fontFamily) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            'PRODUCTO',
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: fontSize - 1,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            'CANT',
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: fontSize - 1,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            'TOTAL',
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: fontSize - 1,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// Construye una fila de item con formato de tabla
  Widget _buildItemRow(
    TicketItemData item,
    double fontSize,
    String fontFamily,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nombre del producto
        Text(
          item.name,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // Cantidad x Precio = Total
        Row(
          children: [
            Expanded(
              child: Text(
                '  ${item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)} x ${_formatCurrency(item.price)}',
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize - 1,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            Text(
              _formatCurrency(item.total),
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
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

  Widget _buildDivider(int chars, String fontFamily) {
    return Text(
      '-' * (chars ~/ 2),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: 10,
        color: Colors.grey.shade500,
        letterSpacing: 1,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildRow(
    String label,
    String value,
    double fontSize,
    String fontFamily, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  String _formatCurrency(double value) {
    return 'RD\$ ${value.toStringAsFixed(2)}';
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      default:
        return method;
    }
  }
}

/// Datos para la vista previa del ticket
class TicketPreviewData {
  final String ticketCode;
  final DateTime dateTime;
  final String? clientName;
  final String? clientPhone;
  final String? clientRnc;
  final String? cashierName;
  final String? ncf;
  final List<TicketItemData> items;
  final double subtotal;
  final double discount;
  final double itbis;
  final double total;
  final List<PaymentData> payments;
  final double change;

  TicketPreviewData({
    required this.ticketCode,
    required this.dateTime,
    this.clientName,
    this.clientPhone,
    this.clientRnc,
    this.cashierName,
    this.ncf,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.itbis,
    required this.total,
    required this.payments,
    required this.change,
  });

  /// Datos de demostración
  factory TicketPreviewData.demo() {
    return TicketPreviewData(
      ticketCode: 'DEMO-001',
      dateTime: DateTime.now(),
      clientName: 'Cliente Demo',
      clientPhone: '(829) 531-9442',
      cashierName: 'Cajero 1',
      ncf: 'B0100000001',
      items: [
        TicketItemData(
          name: 'Producto de Prueba 1',
          qty: 2,
          price: 350.00,
          total: 700.00,
        ),
        TicketItemData(
          name: 'Producto de Prueba 2',
          qty: 1,
          price: 500.00,
          total: 500.00,
        ),
      ],
      subtotal: 1200.00,
      discount: 0.00,
      itbis: 216.00,
      total: 1416.00,
      payments: [PaymentData(method: 'cash', amount: 1500.00)],
      change: 84.00,
    );
  }
}

class TicketItemData {
  final String name;
  final double qty;
  final double price;
  final double total;

  TicketItemData({
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
  });
}

class PaymentData {
  final String method;
  final double amount;

  PaymentData({required this.method, required this.amount});
}
