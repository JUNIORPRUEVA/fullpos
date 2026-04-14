import 'cash_accounting_service.dart';

/// Modelo de Resumen de Caja
class CashSummaryModel {
  final double openingAmount;
  final double totalSales;
  final double totalExpenses;
  final double totalWithdrawals;
  final double cashInManual;
  final double cashOutManual;
  final double creditAbonos;
  final double layawayAbonos;
  final double salesCashTotal;
  final double salesCardTotal;
  final double salesTransferTotal;
  final double salesCreditTotal;
  final double refundsCash;
  final double expectedCash;
  final int totalTickets;
  final int totalRefunds;

  CashSummaryModel({
    required this.openingAmount,
    required this.totalSales,
    required this.totalExpenses,
    required this.totalWithdrawals,
    required this.cashInManual,
    required this.cashOutManual,
    required this.creditAbonos,
    required this.layawayAbonos,
    required this.salesCashTotal,
    required this.salesCardTotal,
    required this.salesTransferTotal,
    required this.salesCreditTotal,
    required this.refundsCash,
    required this.expectedCash,
    required this.totalTickets,
    required this.totalRefunds,
  });

  /// Total de ventas (todos los métodos)
  double get grossSalesTotal =>
      salesCashTotal + salesCardTotal + salesTransferTotal + salesCreditTotal;

  double get profit => CashAccountingService.calculateProfit(
    totalSales: totalSales,
    totalExpenses: totalExpenses,
  );

  /// Calcular diferencia con el conteo real
  double calculateDifference(double closingAmount) {
    return CashAccountingService.buildClosingSummary(
      openingAmount: openingAmount,
      totalSales: totalSales,
      totalExpenses: totalExpenses,
      totalWithdrawals: totalWithdrawals,
      countedCash: closingAmount,
    ).difference;
  }

  CashClosingSummary toClosingSummary({required double countedCash}) {
    return CashAccountingService.buildClosingSummary(
      openingAmount: openingAmount,
      totalSales: totalSales,
      totalExpenses: totalExpenses,
      totalWithdrawals: totalWithdrawals,
      countedCash: countedCash,
    );
  }

  /// Factory para crear resumen vacío
  factory CashSummaryModel.empty({double openingAmount = 0.0}) {
    return CashSummaryModel(
      openingAmount: openingAmount,
      totalSales: 0.0,
      totalExpenses: 0.0,
      totalWithdrawals: 0.0,
      cashInManual: 0.0,
      cashOutManual: 0.0,
      creditAbonos: 0.0,
      layawayAbonos: 0.0,
      salesCashTotal: 0.0,
      salesCardTotal: 0.0,
      salesTransferTotal: 0.0,
      salesCreditTotal: 0.0,
      refundsCash: 0.0,
      expectedCash: openingAmount,
      totalTickets: 0,
      totalRefunds: 0,
    );
  }

  CashSummaryModel copyWith({
    double? openingAmount,
    double? totalSales,
    double? totalExpenses,
    double? totalWithdrawals,
    double? cashInManual,
    double? cashOutManual,
    double? creditAbonos,
    double? layawayAbonos,
    double? salesCashTotal,
    double? salesCardTotal,
    double? salesTransferTotal,
    double? salesCreditTotal,
    double? refundsCash,
    double? expectedCash,
    int? totalTickets,
    int? totalRefunds,
  }) {
    return CashSummaryModel(
      openingAmount: openingAmount ?? this.openingAmount,
      totalSales: totalSales ?? this.totalSales,
      totalExpenses: totalExpenses ?? this.totalExpenses,
      totalWithdrawals: totalWithdrawals ?? this.totalWithdrawals,
      cashInManual: cashInManual ?? this.cashInManual,
      cashOutManual: cashOutManual ?? this.cashOutManual,
      creditAbonos: creditAbonos ?? this.creditAbonos,
      layawayAbonos: layawayAbonos ?? this.layawayAbonos,
      salesCashTotal: salesCashTotal ?? this.salesCashTotal,
      salesCardTotal: salesCardTotal ?? this.salesCardTotal,
      salesTransferTotal: salesTransferTotal ?? this.salesTransferTotal,
      salesCreditTotal: salesCreditTotal ?? this.salesCreditTotal,
      refundsCash: refundsCash ?? this.refundsCash,
      expectedCash: expectedCash ?? this.expectedCash,
      totalTickets: totalTickets ?? this.totalTickets,
      totalRefunds: totalRefunds ?? this.totalRefunds,
    );
  }
}
