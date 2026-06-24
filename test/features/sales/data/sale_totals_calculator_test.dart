import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/sales/data/sale_totals_calculator.dart';

void main() {
  group('SaleTotalsCalculator', () {
    test('calculates ITBIS from the discounted taxable base', () {
      final totals = SaleTotalsCalculator.fromDiscountedSubtotal(
        subtotal: 900,
        discountTotal: 100,
        itbisEnabled: true,
        itbisRate: 0.18,
      );

      expect(totals.grossSubtotal, 1000);
      expect(totals.discountTotal, 100);
      expect(totals.taxableSubtotal, 900);
      expect(totals.itbisAmount, 162);
      expect(totals.total, 1062);
    });

    test(
      'supports percentage discounts after they are resolved to an amount',
      () {
        final subtotalBeforeGlobalDiscount = 2000.0;
        final resolvedDiscount = subtotalBeforeGlobalDiscount * 0.10;

        final totals = SaleTotalsCalculator.fromDiscountedSubtotal(
          subtotal: subtotalBeforeGlobalDiscount - resolvedDiscount,
          discountTotal: resolvedDiscount,
          itbisEnabled: true,
          itbisRate: 0.18,
        );

        expect(totals.grossSubtotal, 2000);
        expect(totals.discountTotal, 200);
        expect(totals.taxableSubtotal, 1800);
        expect(totals.itbisAmount, 324);
        expect(totals.total, 2124);
      },
    );

    test('keeps non-fiscal or tax-disabled totals without ITBIS', () {
      final totals = SaleTotalsCalculator.fromDiscountedSubtotal(
        subtotal: 450,
        discountTotal: 50,
        itbisEnabled: false,
        itbisRate: 0.18,
      );

      expect(totals.grossSubtotal, 500);
      expect(totals.taxableSubtotal, 450);
      expect(totals.itbisAmount, 0);
      expect(totals.total, 450);
    });

    test('converts fixed grand-total discount to taxable discount', () {
      final taxableDiscount =
          SaleTotalsCalculator.taxableDiscountFromGrandTotalDiscount(
            amount: 612,
            itbisEnabled: true,
            itbisRate: 0.18,
          );
      final totals = SaleTotalsCalculator.fromDiscountedSubtotal(
        subtotal: 3400 - taxableDiscount,
        discountTotal: taxableDiscount,
        itbisEnabled: true,
        itbisRate: 0.18,
      );

      expect(taxableDiscount, 518.64);
      expect(totals.itbisAmount, 518.64);
      expect(totals.total, 3400);
    });

    test('keeps fixed fiscal discount equal to the amount entered', () {
      final total = SaleTotalsCalculator.grandTotalAfterFixedDiscount(
        taxableSubtotalBeforeDiscount: 5390,
        discountAmount: 360,
        itbisEnabled: true,
        itbisRate: 0.18,
      );

      expect(total, 6000.20);
    });

    test('clamps over-discounted taxable base to zero', () {
      final totals = SaleTotalsCalculator.fromDiscountedSubtotal(
        subtotal: -25,
        discountTotal: 150,
        itbisEnabled: true,
        itbisRate: 0.18,
      );

      expect(totals.grossSubtotal, 150);
      expect(totals.taxableSubtotal, 0);
      expect(totals.itbisAmount, 0);
      expect(totals.total, 0);
    });
  });
}
