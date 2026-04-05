import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class AccountingAmountFormatter extends TextInputFormatter {
  AccountingAmountFormatter({this.allowEmpty = true});

  final bool allowEmpty;

  static final NumberFormat _format = NumberFormat('#,##0', 'en_US');

  static String format(num value) {
    final safeValue = value.toDouble();
    if (safeValue.isNaN || safeValue.isInfinite) {
      return '0';
    }
    return _format.format(safeValue.round());
  }

  static String formatWithSymbol(num value, {required String symbol}) {
    return '$symbol ${format(value)}';
  }

  static double parse(String text) {
    final digits = _extractWholeDigits(text);
    if (digits.isEmpty) {
      return 0;
    }
    return double.parse(digits);
  }

  static String _extractWholeDigits(String text) {
    final sanitized = text.replaceAll(RegExp(r'[^0-9,\.]'), '');
    if (sanitized.isEmpty) {
      return '';
    }

    final lastComma = sanitized.lastIndexOf(',');
    final lastDot = sanitized.lastIndexOf('.');
    final separatorIndex = lastComma > lastDot ? lastComma : lastDot;

    if (separatorIndex >= 0) {
      final trailingLength = sanitized.length - separatorIndex - 1;
      if (trailingLength > 0 && trailingLength <= 2) {
        final integerPart = sanitized.substring(0, separatorIndex);
        return integerPart.replaceAll(RegExp(r'[^0-9]'), '');
      }
    }

    return sanitized.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _extractWholeDigits(newValue.text);
    if (digits.isEmpty) {
      if (allowEmpty) {
        return const TextEditingValue(text: '');
      }
      return const TextEditingValue(
        text: '0',
        selection: TextSelection.collapsed(offset: 1),
      );
    }

    final normalized = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final formatted = format(int.parse(normalized.isEmpty ? '0' : normalized));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }
}