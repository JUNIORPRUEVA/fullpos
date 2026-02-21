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
    // Importante: NO forzar negrita en el cuerpo en tamaños normales;
    // pero cuando el tamaño queda muy pequeño (común en 58mm), el normal puede
    // salir “lavado” en algunas impresoras/drivers, así que oscurecemos levemente.
    final pw.Font normalFont = pw.Font.courier();
    final pw.Font boldFont = pw.Font.courierBold();

    // Ancho real imprimible (ver `TicketLayoutConfig.printableWidthMm`).
    final double pageWidth = layout.printableWidthMm * PdfPageFormat.mm;

    // Alto del rollo: usar un valor grande FINITO.
    // En algunos drivers/spoolers (Windows) `double.infinity` puede imprimir en blanco.
    final double pageHeight = 2000 * PdfPageFormat.mm;

    // Márgenes (mm). En térmicas, márgenes grandes destruyen el ancho útil.
    // Por estabilidad (alineación/columnas), limitamos el rango.
    final double marginLeftPts =
        (layout.leftMarginMm.clamp(0, 4)) * PdfPageFormat.mm;
    final double marginRightPts =
        (layout.rightMarginMm.clamp(0, 4)) * PdfPageFormat.mm;
    final double contentWidthPts = (pageWidth - marginLeftPts - marginRightPts)
        .clamp(10.0, pageWidth);

    // Fuente monoespaciada: aproximación Courier => ancho de carácter ~0.60 * fontSize.
    // Usamos un factor conservador para evitar desalineación por wraps.
    const double courierCharWidthFactor = 0.60;
    final double fittedFontSize =
        contentWidthPts / (layout.maxCharsPerLine * courierCharWidthFactor);

    // Tamaño de fuente:
    // - `layout.adjustedFontSize` refleja el ajuste del usuario (niveles 1-10)
    // - `fittedFontSize` es el máximo que cabe sin romper columnas
    // Importante: nunca exceder el fitted; si no, el driver hace wrap y se desalinean columnas.
    const double safety = 0.98;
    // Permitir letra más grande por defecto (siempre limitado por fittedFontSize).
    final double maxReadableFont = 16.0;
    final double desiredFontSize = layout.adjustedFontSize;
    final double fontSize = math
        .min(
          math.min(desiredFontSize, fittedFontSize * safety),
          maxReadableFont,
        )
        .clamp(5.5, maxReadableFont);

    // En muchas impresoras 80mm, el Courier normal puede salir “gris” comparado con el
    // encabezado (que va en bold). Para mantener TODO igual pero más negro, usamos
    // una base más oscura en 80mm. En 58mm, solo forzamos bold cuando el tamaño es
    // muy pequeño para mejorar contraste sin volverlo pesado.
    final bool preferDarkerBody = layout.paperWidthMm == 80;
    final pw.Font bodyFont = preferDarkerBody
      ? boldFont
      : (fontSize < 7.0 ? boldFont : normalFont);

    final content = <pw.Widget>[];

    final bool hasLogo =
        includeLogo && layout.showLogo && company.logoBytes != null;

    if (hasLogo) {
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
      // Evitar “aire” extra debajo del logo.
      content.add(pw.SizedBox(height: 0.2));
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

    bool isSeparatorLine(String text) {
      final t = text.trim();
      if (t.isEmpty) return false;
      // Considerar separadores típicos: ---- o ====.
      final first = t.codeUnitAt(0);
      for (final c in t.codeUnits) {
        if (c != first) return false;
      }
      return t.length >= 6 && (t[0] == '-' || t[0] == '=');
    }

    // Detectar bloque de encabezado: desde el inicio hasta el primer separador.
    // Esto nos permite imprimir el header (empresa/dirección/RNC) más grande y elegante,
    // sin romper columnas del cuerpo.
    int firstSeparatorIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (isSeparatorLine(lines[i])) {
        firstSeparatorIndex = i;
        break;
      }
    }

    pw.TextStyle styleFromTag(String tag) {
      final t = tag.toUpperCase();
      final bool bold = t.startsWith('B') || t.startsWith('H');
      double size = fontSize;
      if (t.startsWith('H1')) size = fontSize * 1.35;
      if (t.startsWith('H2')) size = fontSize * 1.18;

      // Evitar tamaños demasiado grandes en algunos drivers.
      size = size.clamp(fontSize, 16.0);

      return pw.TextStyle(
        font: bold ? boldFont : bodyFont,
        fontSize: size,
        lineSpacing: 1.0 * layout.lineSpacingFactor,
      );
    }

    pw.TextStyle styleForLine(String tag, String text, int index) {
      // Si ya hay tag explícito, respetarlo.
      if (tag.isNotEmpty) return styleFromTag(tag);

      final isInHeaderBlock =
          firstSeparatorIndex != -1 && index < firstSeparatorIndex;
      if (!isInHeaderBlock) return styleFromTag(tag);

      // Encabezado más grande: primera línea (nombre) más grande; resto ligeramente menor.
      final trimmed = text.trim();
      if (trimmed.isEmpty) return styleFromTag(tag);

      final multiplier = index == 0 ? 1.35 : 1.15;
      // Intentar agrandar el header, pero sin exceder el tamaño que cabe.
      // (El body usa padding/columnas; el header va sin padding y centrado.)
      final maxToFit =
          contentWidthPts /
          (math.max(1, trimmed.length) * courierCharWidthFactor) *
          safety;
      final size = math
          .min(math.min(fontSize * multiplier, maxToFit), 18.0)
          .clamp(fontSize, 18.0);
      return pw.TextStyle(
        font: boldFont,
        fontSize: size,
        lineSpacing: 1.0 * layout.lineSpacingFactor,
      );
    }

    pw.Widget buildLineWidget(int index) {
      final raw = lines[index];
      final parsed = parseTag(raw);
      final tag = parsed.tag;
      final text = parsed.text;

      // Si la línea es “grande”, no conviene respetar pads/espacios a la derecha.
      final isHeader = tag.toUpperCase().startsWith('H');
      final display = isHeader ? text.trimRight() : text;

      final isHeaderBlock =
          tag.isEmpty &&
          firstSeparatorIndex != -1 &&
          index < firstSeparatorIndex;

      final headerText = display.trim();
      final widget = pw.Text(
        (isHeaderBlock ? headerText : display).isEmpty
            ? ' '
            : (isHeaderBlock ? headerText : display),
        style: styleForLine(tag, display, index),
        textAlign: isHeaderBlock ? pw.TextAlign.center : pw.TextAlign.left,
      );

      if (tag.isEmpty) {
        if (isHeaderBlock) {
          return pw.Align(alignment: pw.Alignment.center, child: widget);
        }
        return widget;
      }

      return pw.Align(alignment: alignmentFromTag(tag), child: widget);
    }

    content.add(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [for (var i = 0; i < lines.length; i++) buildLineWidget(i)],
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidth,
          pageHeight,
          marginLeft: marginLeftPts,
          marginRight: marginRightPts,
          marginTop:
              (layout.topMarginPx.toDouble().clamp(0.0, 120.0) -
                      (hasLogo ? 6.0 : 0.0))
                  .clamp(0.0, 120.0),
          marginBottom: layout.bottomMarginPx.toDouble().clamp(0.0, 120.0),
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
