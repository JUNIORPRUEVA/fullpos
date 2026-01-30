import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/models.dart';
import '../../features/settings/data/printer_settings_model.dart';

/// Widget de vista previa del ticket UNIFICADO
/// Usa la misma lógica que el TicketBuilder para garantizar consistencia
/// Formato profesional estilo factura
class UnifiedTicketPreviewWidget extends StatelessWidget {
  final PrinterSettingsModel settings;
  final CompanyInfo? company;
  final TicketData? data;

  const UnifiedTicketPreviewWidget({
    super.key,
    required this.settings,
    this.company,
    this.data,
  });

  @override
  Widget build(BuildContext context) {
    final previewData = data ?? TicketData.demo();
    final companyInfo = company ?? CompanyInfo.defaults();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);

    final width = settings.paperWidthMm == 58 ? 200.0 : 280.0;

    // Usar los nuevos niveles de espaciado
    final fontSize = layout.adjustedFontSize;
    final fontFamily = layout.fontFamilyName;
    final lineSpacing = 2.0 * layout.lineSpacingFactor;
    final sectionSpacing = 4.0 * layout.sectionSpacingFactor;

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
          left: 8.0 + layout.leftMarginMm.toDouble(),
          right: 8.0 + layout.rightMarginMm.toDouble(),
          top: layout.topMarginPx.toDouble(),
          bottom: layout.bottomMarginPx.toDouble(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ================================================ HEADER
            if (layout.showCompanyInfo) ...[
              _buildDoubleDivider(layout.maxCharsPerLine, fontFamily, fontSize),
              SizedBox(height: lineSpacing),

              // === LOGO ===
              if (layout.showLogo) ...[
                Container(
                  width: layout.logoSizePx.toDouble(),
                  height: layout.logoSizePx.toDouble(),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: companyInfo.logoBytes != null
                      ? Image.memory(
                          companyInfo.logoBytes!,
                          fit: BoxFit.contain,
                        )
                      : Icon(
                          Icons.store,
                          size: layout.logoSizePx * 0.6,
                          color: Colors.grey.shade500,
                        ),
                ),
                SizedBox(height: lineSpacing),
              ],

              // Nombre del negocio
              Text(
                companyInfo.name.toUpperCase(),
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize + 2,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),

              // RNC y Teléfono en la misma línea
              if ((companyInfo.rnc?.isNotEmpty ?? false) ||
                  (companyInfo.primaryPhone?.isNotEmpty ?? false)) ...[
                SizedBox(height: lineSpacing),
                Text(
                  _buildRncPhoneLine(companyInfo),
                  style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                  textAlign: TextAlign.center,
                ),
              ],

              // Dirección
              if (companyInfo.address?.isNotEmpty ?? false) ...[
                SizedBox(height: lineSpacing),
                Text(
                  companyInfo.address!,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize - 1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],

              SizedBox(height: lineSpacing),
              _buildDoubleDivider(layout.maxCharsPerLine, fontFamily, fontSize),
            ],

            SizedBox(height: sectionSpacing),

            // ================================================ FACTURA + FECHA / TICKET
            _buildRow(
              _getDocumentType(previewData.type),
              'FECHA: ${DateFormat('dd/MM/yyyy').format(previewData.dateTime)}',
              fontSize,
              fontFamily,
              leftBold: true,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'TICKET: #${previewData.ticketNumber.padLeft(6, '0')}',
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if (previewData.isCopy) ...[
              SizedBox(height: lineSpacing),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '*** COPIA ***',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize - 1,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],

            // NCF
            if (layout.showNcf &&
                previewData.ncf != null &&
                previewData.ncf!.isNotEmpty) ...[
              SizedBox(height: lineSpacing),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'NCF: ${previewData.ncf}',
                  style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                ),
              ),
            ],

            // Cajero
            if (layout.showCashier && previewData.cashierName != null) ...[
              SizedBox(height: lineSpacing),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Cajero: ${previewData.cashierName}',
                  style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                ),
              ),
            ],

            _buildSingleDivider(layout.maxCharsPerLine, fontFamily, fontSize),
            SizedBox(height: sectionSpacing),

            // ================================================ DATOS DEL CLIENTE
            if (layout.showClientInfo && previewData.client != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DATOS DEL CLIENTE:',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: lineSpacing),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nombre: ${previewData.client!.name}',
                  style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                ),
              ),
              if (previewData.client!.rnc?.isNotEmpty ?? false) ...[
                SizedBox(height: lineSpacing),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'RNC/Cédula: ${previewData.client!.rnc}',
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ],
              if (previewData.client!.phone?.isNotEmpty ?? false) ...[
                SizedBox(height: lineSpacing),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Teléfono: ${previewData.client!.phone}',
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ],
              _buildSingleDivider(layout.maxCharsPerLine, fontFamily, fontSize),
              SizedBox(height: sectionSpacing),
            ],

            // ================================================ ENCABEZADO DE ITEMS
            Text(
              'DESCRIPCIÓN          CANT.    PRECIO     TOTAL',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize - 1,
                fontWeight: FontWeight.bold,
              ),
            ),
            _buildSingleDivider(layout.maxCharsPerLine, fontFamily, fontSize),

            // ================================================ ITEMS
            SizedBox(height: lineSpacing),
            for (final item in previewData.items) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.name,
                  style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                ),
              ),
              _buildRow(
                '  ${_formatQty(item.quantity)} x ${_formatNumber(item.unitPrice)}',
                _formatNumber(item.total),
                fontSize - 1,
                fontFamily,
              ),
              SizedBox(height: lineSpacing),
            ],

            _buildSingleDivider(layout.maxCharsPerLine, fontFamily, fontSize),
            SizedBox(height: sectionSpacing),

            // ================================================ TOTALES
            if (layout.showTotalsBreakdown) ...[
              _buildRow(
                '',
                'SUB-TOTAL:      RD\$ ${_formatNumber(previewData.subtotal)}',
                fontSize,
                fontFamily,
                rightAlign: true,
              ),

              if (previewData.discount > 0) ...[
                SizedBox(height: lineSpacing),
                _buildRow(
                  '',
                  'DESCUENTO:      RD\$ ${_formatNumber(previewData.discount)}',
                  fontSize,
                  fontFamily,
                  rightAlign: true,
                  valueColor: Colors.red.shade700,
                ),
              ],

              if (layout.showItbis && previewData.itbis > 0) ...[
                SizedBox(height: lineSpacing),
                _buildRow(
                  '',
                  'ITBIS (${(previewData.itbisRate * 100).toStringAsFixed(0)}%):    RD\$ ${_formatNumber(previewData.itbis)}',
                  fontSize,
                  fontFamily,
                  rightAlign: true,
                ),
              ],

              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '-' * 28,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize - 1,
                  ),
                ),
              ),
            ],

            // TOTAL destacado
            _buildRow(
              '',
              'TOTAL:          RD\$ ${_formatNumber(previewData.total)}',
              fontSize + 1,
              fontFamily,
              rightAlign: true,
              isBold: true,
            ),
            SizedBox(height: sectionSpacing),

            // ================================================ FORMA DE PAGO
            if (layout.showPaymentInfo &&
                previewData.paymentMethod.isNotEmpty) ...[
              _buildSingleDivider(layout.maxCharsPerLine, fontFamily, fontSize),
              SizedBox(height: lineSpacing),
              Text(
                'Pago: ${previewData.paymentMethod}',
                style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
                textAlign: TextAlign.center,
              ),
              if (previewData.paidAmount > 0) ...[
                SizedBox(height: lineSpacing),
                _buildRow(
                  'Recibido:',
                  'RD\$ ${_formatNumber(previewData.paidAmount)}',
                  fontSize,
                  fontFamily,
                ),
              ],
              if (previewData.changeAmount > 0) ...[
                SizedBox(height: lineSpacing),
                _buildRow(
                  'Cambio:',
                  'RD\$ ${_formatNumber(previewData.changeAmount)}',
                  fontSize,
                  fontFamily,
                  valueColor: Colors.green.shade700,
                ),
              ],
              SizedBox(height: sectionSpacing),
            ],

            // ================================================ FOOTER
            _buildDoubleDivider(layout.maxCharsPerLine, fontFamily, fontSize),
            SizedBox(height: lineSpacing),

            if (layout.showFooterMessage &&
                layout.footerMessage.isNotEmpty) ...[
              Text(
                layout.footerMessage,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Text(
                '¡GRACIAS POR LA COMPRA!',
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            Text(
              'No se aceptan devoluciones sin',
              style: TextStyle(fontFamily: fontFamily, fontSize: fontSize - 1),
              textAlign: TextAlign.center,
            ),
            Text(
              'presentar este ticket.',
              style: TextStyle(fontFamily: fontFamily, fontSize: fontSize - 1),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: lineSpacing),
            _buildDoubleDivider(layout.maxCharsPerLine, fontFamily, fontSize),

            // Espacio para corte
            if (layout.autoCut) const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _buildRncPhoneLine(CompanyInfo company) {
    final rnc = company.rnc ?? '';
    final phone = company.primaryPhone ?? '';
    final rncPart = rnc.isNotEmpty ? 'RNC: $rnc' : '';
    final phonePart = phone.isNotEmpty ? 'Tel: $phone' : '';
    final separator = (rncPart.isNotEmpty && phonePart.isNotEmpty) ? ' | ' : '';
    return '$rncPart$separator$phonePart';
  }

  String _getDocumentType(TicketType type) {
    switch (type) {
      case TicketType.sale:
        return 'FACTURA';
      case TicketType.quote:
        return 'COTIZACIÓN';
      case TicketType.refund:
        return 'DEVOLUCIÓN';
      case TicketType.credit:
        return 'NOTA DE CRÉDITO';
      case TicketType.copy:
        return 'COPIA';
    }
  }

  String _formatNumber(double value) {
    final formatter = NumberFormat('#,##0.00', 'es_DO');
    return formatter.format(value);
  }

  String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(2);
  }

  Widget _buildDoubleDivider(int chars, String fontFamily, double fontSize) {
    return Text(
      '=' * chars,
      style: TextStyle(fontFamily: fontFamily, fontSize: fontSize - 2),
    );
  }

  Widget _buildSingleDivider(int chars, String fontFamily, double fontSize) {
    return Text(
      '-' * chars,
      style: TextStyle(fontFamily: fontFamily, fontSize: fontSize - 2),
    );
  }

  Widget _buildRow(
    String label,
    String value,
    double fontSize,
    String fontFamily, {
    bool isBold = false,
    bool leftBold = false,
    bool rightAlign = false,
    Color? valueColor,
  }) {
    if (rightAlign) {
      return Align(
        alignment: Alignment.centerRight,
        child: Text(
          value,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: valueColor,
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: (isBold || leftBold)
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Widget con FutureBuilder que carga automáticamente CompanyInfo
class AsyncTicketPreviewWidget extends StatelessWidget {
  final PrinterSettingsModel settings;
  final TicketData? data;

  const AsyncTicketPreviewWidget({
    super.key,
    required this.settings,
    this.data,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CompanyInfo>(
      future: CompanyInfoRepository.getCurrentCompanyInfo(),
      builder: (context, snapshot) {
        final company = snapshot.data ?? CompanyInfo.defaults();
        return UnifiedTicketPreviewWidget(
          settings: settings,
          company: company,
          data: data,
        );
      },
    );
  }
}
