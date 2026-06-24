class SaleTotals {
  final double grossSubtotal;
  final double discountTotal;
  final double taxableSubtotal;
  final double itbisAmount;
  final double total;
  final double itbisRate;
  final bool itbisEnabled;

  const SaleTotals({
    required this.grossSubtotal,
    required this.discountTotal,
    required this.taxableSubtotal,
    required this.itbisAmount,
    required this.total,
    required this.itbisRate,
    required this.itbisEnabled,
  });
}

class SaleTotalsCalculator {
  SaleTotalsCalculator._();

  static double roundMoney(num value) => (value * 100).roundToDouble() / 100;

  static double taxableDiscountFromGrandTotalDiscount({
    required double amount,
    required bool itbisEnabled,
    required double itbisRate,
  }) {
    final normalizedAmount = amount.clamp(0.0, double.infinity);
    final normalizedRate = itbisRate.clamp(0.0, double.infinity);
    if (!itbisEnabled || normalizedRate <= 0) {
      return roundMoney(normalizedAmount);
    }
    return roundMoney(normalizedAmount / (1 + normalizedRate));
  }

  static double grandTotalAfterFixedDiscount({
    required double taxableSubtotalBeforeDiscount,
    required double discountAmount,
    required bool itbisEnabled,
    required double itbisRate,
  }) {
    final subtotal = taxableSubtotalBeforeDiscount.clamp(0.0, double.infinity);
    final discount = discountAmount.clamp(0.0, double.infinity);
    final rate = itbisEnabled ? itbisRate.clamp(0.0, double.infinity) : 0.0;
    return roundMoney(
      (subtotal * (1 + rate)) - discount,
    ).clamp(0.0, double.infinity);
  }

  static SaleTotals fromDiscountedSubtotal({
    required double subtotal,
    required double discountTotal,
    required bool itbisEnabled,
    required double itbisRate,
    double? itbisAmount,
    double? total,
  }) {
    final normalizedDiscount = discountTotal.clamp(0.0, double.infinity);
    final taxableSubtotal = subtotal.clamp(0.0, double.infinity);
    final grossSubtotal = roundMoney(taxableSubtotal + normalizedDiscount);
    final normalizedRate = itbisRate.clamp(0.0, double.infinity);
    final calculatedItbis = itbisEnabled
        ? roundMoney(taxableSubtotal * normalizedRate)
        : 0.0;
    final resolvedItbis = itbisAmount == null
        ? calculatedItbis
        : roundMoney(itbisAmount.clamp(0.0, double.infinity));

    return SaleTotals(
      grossSubtotal: grossSubtotal,
      discountTotal: roundMoney(normalizedDiscount),
      taxableSubtotal: roundMoney(taxableSubtotal),
      itbisAmount: resolvedItbis,
      total: total == null
          ? roundMoney(taxableSubtotal + resolvedItbis)
          : roundMoney(total.clamp(0.0, double.infinity)),
      itbisRate: normalizedRate,
      itbisEnabled: itbisEnabled,
    );
  }
}
