import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/utils/accounting_amount_formatter.dart';

void main() {
  group('AccountingAmountFormatter', () {
    test('formats integer values with thousand separators and no decimals', () {
      expect(AccountingAmountFormatter.format(25250), '25,250');
      expect(AccountingAmountFormatter.format(0), '0');
    });

    test('parses formatted values and ignores decimal fragments', () {
      expect(AccountingAmountFormatter.parse('25,250'), 25250);
      expect(AccountingAmountFormatter.parse('1,234.56'), 1234);
      expect(AccountingAmountFormatter.parse(r'$ 9,999'), 9999);
    });

    test('formats user input as accounting text', () {
      final formatter = AccountingAmountFormatter(allowEmpty: false);
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: '25250');

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, '25,250');
      expect(result.selection.baseOffset, result.text.length);
    });
  });
}
