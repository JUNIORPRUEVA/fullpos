class RefundCalculator {
  RefundCalculator._();

  static double roundMoney(double value) =>
      (value * 100).roundToDouble() / 100.0;

  static double globalDiscountFactor({
    required double saleSubtotal,
    required double lineNetSubtotal,
  }) {
    if (lineNetSubtotal <= 0) return 0;
    return (saleSubtotal / lineNetSubtotal).clamp(0.0, 1.0).toDouble();
  }

  static double refundableUnitPrice({
    required double quantity,
    required double unitPrice,
    required double lineDiscount,
    required double globalDiscountFactor,
  }) {
    if (quantity <= 0) return 0;
    final lineNet = ((quantity * unitPrice) - lineDiscount).clamp(
      0.0,
      double.infinity,
    );
    return (lineNet / quantity) * globalDiscountFactor;
  }

  static ({double subtotal, double tax, double total}) totals({
    required Iterable<({double quantity, double unitPrice})> items,
    required bool itbisEnabled,
    required double itbisRate,
  }) {
    final subtotal = roundMoney(
      items.fold<double>(
        0,
        (sum, item) => sum + (item.quantity * item.unitPrice),
      ),
    );
    final tax = itbisEnabled
        ? roundMoney(subtotal * itbisRate.clamp(0.0, 1.0))
        : 0.0;
    return (subtotal: subtotal, tax: tax, total: roundMoney(subtotal + tax));
  }
}
