import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'company_info.dart';
import 'ticket_layout_config.dart';
import 'ticket_data.dart';
import 'ticket_renderer.dart';

/// Builder centralizado de tickets
/// Genera tanto texto plano para vista previa como PDF para impresión
/// Formato profesional estilo factura (80mm)
class TicketBuilder {
  final TicketLayoutConfig layout;
  final CompanyInfo company;

  TicketBuilder({required this.layout, required this.company});

  // ============================================================
  // HELPERS DE SEGURIDAD PARA ALINEACIÓN Y ANCHO
  // ============================================================

  /// Genera una línea de regla para debugging del ancho real
  /// Muestra: 0123456789012345678901234567890123456789
  /// Útil para verificar que el maxCharsPerLine es correcto
  String buildDebugRuler() {
    final w = layout.maxCharsPerLine;
    final buffer = StringBuffer();
    for (int i = 0; i < w; i++) {
      buffer.write((i % 10).toString());
    }
    return buffer.toString();
  }

  /// Trunca o rellena texto a la derecha sin exceder ancho
  String padRightSafe(String text, int width) {
    if (text.length > width) return text.substring(0, width);
    return text.padRight(width);
  }

  /// Trunca o rellena texto a la izquierda sin exceder ancho
  String padLeftSafe(String text, int width) {
    if (text.length > width) return text.substring(0, width);
    return text.padLeft(width);
  }

  /// Centra texto sin exceder ancho
  String centerSafe(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final left = ((width - text.length) / 2).floor();
    final right = width - text.length - left;
    return ' ' * left + text + ' ' * right;
  }

  /// Repite un carácter hasta llenar el ancho
  String repeatedChar(String ch, int width) {
    return List.filled(width, ch).join('');
  }

  /// Alinea texto genéricamente respetando maxCharsPerLine
  /// align: 'left' | 'center' | 'right'
  String alignText(String text, int width, String align) {
    if (text.length > width) {
      text = text.substring(0, width);
    }
    switch (align) {
      case 'right':
        return text.padLeft(width);
      case 'center':
        final left = ((width - text.length) / 2).floor();
        final right = width - text.length - left;
        return ' ' * left + text + ' ' * right;
      case 'left':
      default:
        return text.padRight(width);
    }
  }

  /// Crea una línea separadora del ancho especificado
  String sepLine(int width, [String char = '-']) {
    return repeatedChar(char, width);
  }

  /// Alinea un total (label: value) respetando alineación configurada
  String totalsLine(String label, String value, int width, String align) {
    final text = '$label: $value';
    return alignText(text, width, align);
  }

  /// Alinea texto a la derecha con etiqueta a la izquierda (método legacy)
  String totalLine(String label, String value, int width) {
    final text = '$label: $value';
    if (text.length >= width) return text.substring(0, width);
    final pad = width - text.length;
    return ' ' * pad + text;
  }

  /// Genera ticket CON REGLA DE DEBUG para verificar el ancho real
  /// Útil para verificar que maxCharsPerLine es correcto
  /// Muestra una línea de números (0123456789...) al inicio
  String buildPlainTextWithDebugRuler(TicketData data) {
    final buffer = StringBuffer();

    // Agregar regla de debug al inicio
    buffer.writeln('DEBUG RULER - Verify width fits:');
    buffer.writeln(buildDebugRuler());
    buffer.writeln();

    // Ahora agregar el ticket normal
    buffer.write(buildPlainText(data));

    return buffer.toString();
  }

  // ============================================================
  // FORMATO PROFESIONAL DE TICKET (TEXTO PLANO)
  // ============================================================

  /// Genera el ticket en texto plano con formato profesional
  /// Estructura:
  /// ================================================
  ///        FULLTECH, SRL
  ///   RNC: 133080206 | Tel: +1(829)531-8442
  ///         Centro Balber 9
  /// ----
  ///
  /// FACTURA                 FECHA: 29/12/2025
  ///                         TICKET: #DEMO-001
  /// ----
  ///
  /// Cajero: Junior
  ///
  /// DATOS DEL CLIENTE:
  /// Nombre: Cliente Demo
  /// Teléfono: (809) 555-1234
  /// ----
  ///
  /// CANT  PRODUCTO                 PRECIO
  /// ----
  /// 2     Producto de Prueba       500.00
  /// 1     Otro producto            200.00
  /// ----
  ///
  ///              SUB-TOTAL: RDS 1,000.00
  ///              ITBIS (18%): RDS   180.00
  ///              -----
  ///              TOTAL: RDS 1,180.00
  ///
  /// Gracias por su compra
  /// No se aceptan devoluciones sin
  /// presentar este ticket.
  ///
  String buildPlainText(TicketData data) {
    // FUENTE ÚNICA DE VERDAD: Usar TicketRenderer
    final renderer = TicketRenderer(config: layout, company: company);
    final lines = renderer.buildLines(data);

    // Convertir líneas a string
    return lines.join('\n');
  }

  // ============================================================
  // GENERACIÓN DE PDF PROFESIONAL (para impresión térmica)
  // ============================================================

  /// Genera el ticket como documento PDF para impresión térmica
  /// Usa TicketRenderer.buildLines() como FUENTE ÚNICA de verdad para el layout
  pw.Document buildPdf(TicketData data) {
    final renderer = TicketRenderer(config: layout, company: company);
    final lines = renderer.buildLines(data);
    return buildPdfFromLines(lines, includeLogo: true);
  }

  /// Genera un PDF desde una lista de líneas ya alineadas (monoespaciado).
  /// Útil para tickets especiales de prueba (ej. regla de ancho).
  pw.Document buildPdfFromLines(
    List<String> lines, {
    required bool includeLogo,
  }) {
    final doc = pw.Document();

    // Fuentes monoespaciadas para preservar columnas.
    final pw.Font normalFont = pw.Font.courier();
    final pw.Font boldFont = pw.Font.courierBold();
    final bool forceBoldBody = layout.fontSizeLevel >= 6;

    // Ancho real imprimible (ver `TicketLayoutConfig.printableWidthMm`).
    final double pageWidth = layout.printableWidthMm * PdfPageFormat.mm;

    // Alto del rollo: usar un valor grande FINITO.
    // En algunos drivers/spoolers (Windows) `double.infinity` puede imprimir en blanco.
    final double pageHeight = 2000 * PdfPageFormat.mm;

    // Márgenes (mm). En térmicas, márgenes grandes destruyen el ancho útil.
    // Además, algunos sliders guardan valores en “px”; por seguridad, clamp a un rango pequeño.
    final double marginLeftPts =
        (layout.leftMarginMm.clamp(0, 4)) * PdfPageFormat.mm;
    final double marginRightPts =
        (layout.rightMarginMm.clamp(0, 4)) * PdfPageFormat.mm;
    final double contentWidthPts = (pageWidth - marginLeftPts - marginRightPts)
        .clamp(10.0, pageWidth);

    // Fuente monoespaciada: aproximación Courier => ancho de carácter ~0.60 * fontSize.
    // Elegimos fontSize para que entren EXACTAMENTE `maxCharsPerLine` sin escalar.
    const double courierCharWidthFactor = 0.60;
    final double fittedFontSize =
        contentWidthPts / (layout.maxCharsPerLine * courierCharWidthFactor);

    // Mantener tamaño legible sin romper el ancho.
    // Importante: NO exceder `fittedFontSize` para evitar wraps que rompan columnas.
    final double maxReadableFont = 12.0;
    final double minReadableFont = 8.0;
    final double fontSize = math.min(
      fittedFontSize < minReadableFont ? minReadableFont : fittedFontSize,
      maxReadableFont,
    );

    final content = <pw.Widget>[];

    if (includeLogo && layout.showLogo && company.logoBytes != null) {
      final image = pw.MemoryImage(company.logoBytes!);
      content.add(
        pw.Center(
          child: pw.Image(
            image,
            width: layout.logoSizePx.toDouble(),
            height: layout.logoSizePx.toDouble(),
            fit: pw.BoxFit.contain,
          ),
        ),
      );
      content.add(pw.SizedBox(height: 2.0));
    }

    // Render por líneas para poder resaltar encabezados/totales.
    // Soporta tags al inicio de la línea:
    // - <H1C>, <H2C> (grande, centrado)
    // - <H1R>, <H2R> (grande, derecha)
    // - <BC>, <BR>, <BL> (negrita)
    // - sin tag: texto normal
    pw.Alignment alignmentFromTag(String tag) {
      final t = tag.toUpperCase();
      if (t.contains('R')) return pw.Alignment.centerRight;
      if (t.contains('C')) return pw.Alignment.center;
      return pw.Alignment.centerLeft;
    }

    ({String tag, String text}) parseTag(String raw) {
      final s = raw;
      if (s.startsWith('<')) {
        final end = s.indexOf('>');
        if (end > 1) {
          final tag = s.substring(1, end);
          final text = s.substring(end + 1);
          return (tag: tag, text: text);
        }
      }
      return (tag: '', text: s);
    }

    pw.TextStyle styleFromTag(String tag) {
      final t = tag.toUpperCase();
      final bool bold = t.startsWith('B') || t.startsWith('H') || forceBoldBody;
      double size = fontSize;
      if (t.startsWith('H1')) size = fontSize * 1.35;
      if (t.startsWith('H2')) size = fontSize * 1.18;

      // Evitar tamaños demasiado grandes en algunos drivers.
      size = size.clamp(fontSize, 16.0);

      return pw.TextStyle(
        font: bold ? boldFont : normalFont,
        fontSize: size,
        lineSpacing: 1.0 * layout.lineSpacingFactor,
      );
    }

    content.add(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          for (final raw in lines)
            () {
              final parsed = parseTag(raw);
              final tag = parsed.tag;
              final text = parsed.text;

              // Si la línea es “grande”, no conviene respetar pads/espacios a la derecha.
              final isHeader = tag.toUpperCase().startsWith('H');
              final display = isHeader ? text.trimRight() : text;

              final widget = pw.Text(
                display.isEmpty ? ' ' : display,
                style: styleFromTag(tag),
                textAlign: pw.TextAlign.left,
              );

              if (tag.isEmpty) return widget;

              return pw.Align(alignment: alignmentFromTag(tag), child: widget);
            }(),
        ],
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidth,
          pageHeight,
          marginLeft: marginLeftPts,
          marginRight: marginRightPts,
          marginTop: layout.topMarginPx.toDouble(),
          marginBottom: layout.bottomMarginPx.toDouble(),
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: content,
        ),
      ),
    );

    return doc;
  }

  // ============================================================
  // HELPERS: Ahora la mayoría están en TicketRenderer
  // Estos helpers se mantienen solo si se usan en otros métodos
  // ============================================================
}
