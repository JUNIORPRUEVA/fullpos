import '../../utils/currency_display.dart';

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

  static String truncateWithEllipsis(String text, int width) {
    if (width <= 0) return '';
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= width) return cleaned;
    if (width <= 3) return cleaned.substring(0, width);
    return '${cleaned.substring(0, width - 3)}...';
  }

  static String formatLine(String left, String right, int width) {
    if (width <= 0) return '';

    final safeLeft = left.trim();
    final safeRight = right.trim();

    if (safeRight.isEmpty) {
      return fitText(safeLeft, width);
    }

    if (safeLeft.isEmpty) {
      return padLeft(safeRight, width);
    }

    final availableLeft = width - safeRight.length - 1;
    if (availableLeft <= 0) {
      return padLeft(safeRight, width);
    }

    final leftText = padRight(
      truncateWithEllipsis(safeLeft, availableLeft),
      availableLeft,
    );
    return fitText('$leftText $safeRight', width);
  }

  static String alignColumns({
    required List<String> values,
    required List<int> widths,
    List<TextAlignMode>? aligns,
  }) {
    if (values.isEmpty || widths.isEmpty) return '';

    final itemCount = values.length < widths.length
        ? values.length
        : widths.length;
    final modes =
        aligns ?? List<TextAlignMode>.filled(itemCount, TextAlignMode.left);
    final buffer = StringBuffer();

    for (var index = 0; index < itemCount; index++) {
      final width = widths[index];
      final value = values[index];
      final mode = index < modes.length ? modes[index] : TextAlignMode.left;

      final fitted = switch (mode) {
        TextAlignMode.right => padLeft(value, width),
        TextAlignMode.center => _center(value, width),
        TextAlignMode.ellipsis => padRight(
          truncateWithEllipsis(value, width),
          width,
        ),
        TextAlignMode.left => padRight(value, width),
      };

      buffer.write(fitted);
    }

    return buffer.toString();
  }

  static String formatProductRow({
    required String qty,
    required String name,
    required String total,
    required int width,
  }) {
    final qtyWidth = width >= 48 ? 5 : 4;
    final totalWidth = width <= 32 ? 8 : (width >= 48 ? 11 : 10);
    final gap = 1;
    final nameWidth = (width - qtyWidth - totalWidth - (gap * 2)).clamp(
      8,
      width,
    );

    return alignColumns(
      values: [qty, '', name, '', total],
      widths: [qtyWidth, gap, nameWidth, gap, totalWidth],
      aligns: const [
        TextAlignMode.right,
        TextAlignMode.left,
        TextAlignMode.ellipsis,
        TextAlignMode.left,
        TextAlignMode.right,
      ],
    );
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
    if (v.isNaN || v.isInfinite) return '0';
    return CurrencyDisplay.formatPlain(v, decimalDigits: 2);
  }

  static String formatMoney(num value) => money(value);

  static String _center(String text, int width) {
    if (width <= 0) return '';
    if (text.length >= width) return text.substring(0, width);
    final left = ((width - text.length) / 2).floor();
    final right = width - text.length - left;
    return ' ' * left + text + ' ' * right;
  }
}

enum TextAlignMode { left, right, center, ellipsis }
