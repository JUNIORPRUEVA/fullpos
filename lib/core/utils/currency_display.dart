import 'package:intl/intl.dart';

class CurrencyDisplay {
  static final NumberFormat _plainFormatter = NumberFormat('#,##0', 'en_US');

  static final Map<int, NumberFormat> _plainDecimalFormatters = {};

  static NumberFormat currency({
    String symbol = 'RD\$',
    int decimalDigits = 0,
  }) {
    return NumberFormat.currency(
      locale: 'en_US',
      symbol: '$symbol ',
      decimalDigits: decimalDigits,
    );
  }

  static String format(
    num value, {
    String symbol = 'RD\$',
    int decimalDigits = 0,
  }) {
    return currency(
      symbol: symbol,
      decimalDigits: decimalDigits,
    ).format(_sanitize(value));
  }

  static String formatPlain(num value, {int decimalDigits = 0}) {
    final sanitized = _sanitize(value);
    if (decimalDigits <= 0) {
      return _plainFormatter.format(sanitized);
    }

    final formatter = _plainDecimalFormatters.putIfAbsent(
      decimalDigits,
      () => NumberFormat('#,##0.${'0' * decimalDigits}', 'en_US'),
    );
    return formatter.format(sanitized);
  }

  static double _sanitize(num value) {
    final normalized = value.toDouble();
    if (normalized.isNaN || normalized.isInfinite) {
      return 0;
    }
    return normalized;
  }
}
