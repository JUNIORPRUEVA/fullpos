import 'package:intl/intl.dart';

/// Utilidades para tickets monoespaciados (fixed-width).
///
/// Todas las funciones garantizan NO exceder el ancho indicado.
class ReceiptText {
  /// Ancho típico para 80mm en muchas impresoras/librerías.
  /// Nota: el ancho real final lo controla `TicketLayoutConfig.maxCharsPerLine`.
  static const int ticketWidth80mm = 48;

  static String line({String char = '-', required int width}) {
    if (width <= 0) return '';
    final ch = char.isEmpty ? '-' : char[0];
    return List.filled(width, ch).join();
  }

  static String fitText(String text, int width) {
    if (width <= 0) return '';
    if (text.length == width) return text;
    if (text.length < width) return text.padRight(width);
    return text.substring(0, width);
  }

  static String padRight(String text, int width) {
    if (width <= 0) return '';
    if (text.length <= width) return text.padRight(width);
    return text.substring(0, width);
  }

  /// Pad a la izquierda (para números). Si excede el ancho, conserva el final.
  static String padLeft(String text, int width) {
    if (width <= 0) return '';
    if (text.length <= width) return text.padLeft(width);
    return text.substring(text.length - width);
  }

  /// Wrap por palabras; si una palabra excede el ancho, se parte duro.
  static List<String> wrapText(String text, int width) {
    if (width <= 0) return const [''];

    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return const [''];

    final words = cleaned.split(' ');
    final out = <String>[];
    var current = '';

    for (final word in words) {
      if (word.length > width) {
        if (current.isNotEmpty) {
          out.add(current);
          current = '';
        }
        for (var i = 0; i < word.length; i += width) {
          final end = (i + width) > word.length ? word.length : (i + width);
          out.add(word.substring(i, end));
        }
        continue;
      }

      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        out.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) out.add(current);
    return out;
  }

  /// Formato tipo POS: 1,250.00 (coma miles, punto decimal)
  static String money(num value) {
    final v = value.toDouble();
    if (v.isNaN || v.isInfinite) return '0.00';
    // Requerimiento de ticket: 2 decimales, sin símbolos y sin separador de miles.
    // Esto mantiene alineación estable en columnas fijas (ej: 59.32).
    return NumberFormat('0.00', 'en_US').format(v);
  }
}
