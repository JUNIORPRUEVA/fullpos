import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/cash/data/cash_accounting_service.dart';
import 'package:fullpos/features/cash/data/cash_movement_model.dart';
import 'package:fullpos/features/cash/data/cash_summary_model.dart';

void main() {
  group('CashAccountingService', () {
    test('separates expense and withdrawal movements correctly', () {
      expect(
        CashAccountingService.isExpenseMovement(
          directionType: CashMovementType.outcome,
          movementType: CashMovementAccountingType.expense,
          affectsProfit: true,
        ),
        isTrue,
      );

      expect(
        CashAccountingService.isWithdrawalMovement(
          directionType: CashMovementType.outcome,
          movementType: CashMovementAccountingType.ownerDraw,
          affectsProfit: false,
        ),
        isTrue,
      );

      expect(
        CashAccountingService.isWithdrawalMovement(
          directionType: CashMovementType.income,
          movementType: CashMovementAccountingType.transfer,
          affectsProfit: false,
        ),
        isFalse,
      );
    });

    test('builds closing summary with accounting formula only', () {
      final report = CashAccountingService.buildClosingSummary(
        openingAmount: 100,
        totalSales: 500,
        totalExpenses: 80,
        totalWithdrawals: 50,
        countedCash: 460,
      );

      expect(report.expectedCash, 470);
      expect(report.difference, -10);
      expect(report.toMap(), {
        'openingAmount': 100,
        'totalSales': 500,
        'totalExpenses': 80,
        'totalWithdrawals': 50,
        'expectedCash': 470,
        'countedCash': 460,
        'difference': -10,
      });
    });

    test('calculates expected drawer cash without card or transfer sales', () {
      final expected = CashAccountingService.calculateExpectedDrawerCash(
        openingAmount: 0,
        cashSales: 420,
        cashRefunds: 0,
        cashInManual: 1000,
        cashOutManual: 1000,
      );

      expect(expected, 420);
    });

    test('profit excludes withdrawals', () {
      expect(
        CashAccountingService.calculateProfit(
          totalSales: 500,
          totalExpenses: 80,
        ),
        420,
      );
    });

    test('rejects negative or zero movement amounts', () {
      expect(
        () => CashAccountingService.validateAmount(0),
        throwsA(isA<Exception>()),
      );
      expect(
        () => CashAccountingService.validateAmount(-1),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CashSummaryModel', () {
    test('returns structured closing summary', () {
      final summary = CashSummaryModel(
        openingAmount: 150,
        totalSales: 1000.0,
        totalExpenses: 200.0,
        totalWithdrawals: 100.0,
        cashInManual: 0,
        cashOutManual: 130,
        creditAbonos: 0,
        layawayAbonos: 0,
        salesCashTotal: 650,
        salesCardTotal: 0,
        salesTransferTotal: 0,
        salesCreditTotal: 0,
        refundsCash: 50,
        expectedCash: 620,
        totalTickets: 5,
        totalRefunds: 1,
      );

      final closing = summary.toClosingSummary(countedCash: 615);

      expect(summary.totalSold, 1000);
      expect(summary.netCashSales, 600);
      expect(closing.expectedCash, 620);
      expect(closing.difference, -5);
    });
  });
}
