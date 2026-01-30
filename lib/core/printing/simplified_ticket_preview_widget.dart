import 'package:flutter/material.dart';
import 'models/models.dart';
import '../../features/settings/data/printer_settings_model.dart';

/// Widget de vista previa SIMPLIFICADO que usa TicketRenderer
///
/// FUENTE ÚNICA DE VERDAD: Usa exactamente las mismas líneas que la impresión
class SimplifiedTicketPreviewWidget extends StatelessWidget {
  final PrinterSettingsModel settings;
  final CompanyInfo? company;
  final TicketData? data;

  const SimplifiedTicketPreviewWidget({
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

    // FUENTE ÚNICA: Usar TicketRenderer para generar las líneas
    final renderer = TicketRenderer(config: layout, company: companyInfo);
    final lines = renderer.buildLines(previewData);

    // Calcular ancho real del ticket en la vista previa.
    // Importante: incluir padding/márgenes; de lo contrario las líneas se parten
    // (se ven "sobresalidas", encabezados en 2 líneas y totales desalineados).
    final fontSize = layout.adjustedFontSize;

    // Para tickets por líneas (con espacios), la previsualización debe ser monospace.
    // Si el usuario elige una fuente proporcional, el centrado/columnas nunca quedarán exactos.
    const monospaceFallback = <String>['Courier New', 'Courier', 'monospace'];
    final requestedFamily = layout.fontFamilyName;
    final fontFamily =
        (requestedFamily == 'Courier' || requestedFamily == 'Courier New')
        ? requestedFamily
        : 'Courier New';

    final charWidth = _measureCharWidth(
      context,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontFamilyFallback: monospaceFallback,
    );

    final paddingLeft = 8.0 + layout.leftMarginMm.toDouble();
    final paddingRight = 8.0 + layout.rightMarginMm.toDouble();

    // +2 para borde y redondeos (margen de seguridad visual)
    final width =
        (layout.maxCharsPerLine * charWidth) + paddingLeft + paddingRight + 2.0;

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
          left: paddingLeft,
          right: paddingRight,
          top: layout.topMarginPx.toDouble(),
          bottom: layout.bottomMarginPx.toDouble(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mostrar cada línea exactamente como saldrá en la impresión
            for (final line in lines)
              Text(
                line,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontFamilyFallback: monospaceFallback,
                  fontSize: fontSize,
                  fontWeight: layout.boldHeader
                      ? FontWeight.w700
                      : FontWeight.normal,
                  height: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _measureCharWidth(
    BuildContext context, {
    required String fontFamily,
    required double fontSize,
    required List<String> fontFamilyFallback,
  }) {
    // Medir un carácter típico de monospace. "0" suele ser estable.
    final painter = TextPainter(
      text: TextSpan(
        text: '0',
        style: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontSize: fontSize,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}
