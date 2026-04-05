import 'package:intl/intl.dart';

class CurrencyDisplay {
  static final NumberFormat _plainFormatter = NumberFormat('#,##0', 'en_US');

  static NumberFormat currency({String symbol = 'RD\$'}) {
    return NumberFormat.currency(
      locale: 'en_US',
      symbol: '$symbol ',
      decimalDigits: 0,
    );
  }

  static String format(num value, {String symbol = 'RD\$'}) {
    return currency(symbol: symbol).format(_sanitize(value));
  }

  static String formatPlain(num value) {
    return _plainFormatter.format(_sanitize(value));
  }

  static double _sanitize(num value) {
    final normalized = value.toDouble();
    if (normalized.isNaN || normalized.isInfinite) {
      return 0;
    }
    return normalized;
  }
}
