import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/sales/data/refund_calculator.dart';

void main() {
  group('RefundCalculator', () {
    test('keeps full value when there is no global discount', () {
      final factor = RefundCalculator.globalDiscountFactor(
        saleSubtotal: 1000,
        lineNetSubtotal: 1000,
      );

      expect(factor, 1);
      expect(
        RefundCalculator.refundableUnitPrice(
          quantity: 2,
          unitPrice: 500,
          lineDiscount: 0,
          globalDiscountFactor: factor,
        ),
        500,
      );
    });

    test('prorates a global discount into each refundable unit', () {
      final factor = RefundCalculator.globalDiscountFactor(
        saleSubtotal: 900,
        lineNetSubtotal: 1000,
      );

      expect(factor, 0.9);
      expect(
        RefundCalculator.refundableUnitPrice(
          quantity: 2,
          unitPrice: 500,
          lineDiscount: 0,
          globalDiscountFactor: factor,
        ),
        450,
      );
    });

    test(
      'combines line and global discounts without refunding extra money',
      () {
        final factor = RefundCalculator.globalDiscountFactor(
          saleSubtotal: 720,
          lineNetSubtotal: 800,
        );

        final unitPrice = RefundCalculator.refundableUnitPrice(
          quantity: 2,
          unitPrice: 500,
          lineDiscount: 200,
          globalDiscountFactor: factor,
        );

        expect(unitPrice, 360);
      },
    );

    test('calculates a partial refund with ITBIS', () {
      final totals = RefundCalculator.totals(
        items: const [
          (quantity: 1.0, unitPrice: 500.0),
          (quantity: 2.0, unitPrice: 125.0),
        ],
        itbisEnabled: true,
        itbisRate: 0.18,
      );

      expect(totals.subtotal, 750);
      expect(totals.tax, 135);
      expect(totals.total, 885);
    });

    test('does not add ITBIS when the original sale had it disabled', () {
      final totals = RefundCalculator.totals(
        items: const [(quantity: 1.0, unitPrice: 499.99)],
        itbisEnabled: false,
        itbisRate: 0.18,
      );

      expect(totals.subtotal, 499.99);
      expect(totals.tax, 0);
      expect(totals.total, 499.99);
    });

    test('rounds monetary totals to cents', () {
      final totals = RefundCalculator.totals(
        items: const [(quantity: 3.0, unitPrice: 33.3333)],
        itbisEnabled: true,
        itbisRate: 0.18,
      );

      expect(totals.subtotal, 100);
      expect(totals.tax, 18);
      expect(totals.total, 118);
    });

    test('clamps inconsistent discount factors to a safe range', () {
      expect(
        RefundCalculator.globalDiscountFactor(
          saleSubtotal: 1200,
          lineNetSubtotal: 1000,
        ),
        1,
      );
      expect(
        RefundCalculator.globalDiscountFactor(
          saleSubtotal: -10,
          lineNetSubtotal: 1000,
        ),
        0,
      );
      expect(
        RefundCalculator.globalDiscountFactor(
          saleSubtotal: 100,
          lineNetSubtotal: 0,
        ),
        0,
      );
    });
  });
}
