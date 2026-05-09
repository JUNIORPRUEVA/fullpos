import 'cash_movement_model.dart';
import 'cash_transaction_model.dart';

class CashAccountingTotals {
  final double totalSales;
  final double totalExpenses;
  final double totalWithdrawals;

  const CashAccountingTotals({
    required this.totalSales,
    required this.totalExpenses,
    required this.totalWithdrawals,
  });
}

class CashClosingSummary {
  final double openingAmount;
  final double totalSales;
  final double totalExpenses;
  final double totalWithdrawals;
  final double expectedCash;
  final double countedCash;
  final double difference;

  const CashClosingSummary({
    required this.openingAmount,
    required this.totalSales,
    required this.totalExpenses,
    required this.totalWithdrawals,
    required this.expectedCash,
    required this.countedCash,
    required this.difference,
  });

  Map<String, double> toMap() {
    return {
      'openingAmount': openingAmount,
      'totalSales': totalSales,
      'totalExpenses': totalExpenses,
      'totalWithdrawals': totalWithdrawals,
      'expectedCash': expectedCash,
      'countedCash': countedCash,
      'difference': difference,
    };
  }
}

class CashAccountingService {
  CashAccountingService._();

  static bool isExpenseMovement({
    required String directionType,
    required String movementType,
    required bool affectsProfit,
  }) {
    return directionType == CashMovementType.outcome &&
        movementType == CashMovementAccountingType.expense &&
        affectsProfit;
  }

  static bool isWithdrawalMovement({
    required String directionType,
    required String movementType,
    required bool affectsProfit,
  }) {
    return directionType == CashMovementType.outcome &&
        !isExpenseMovement(
          directionType: directionType,
          movementType: movementType,
          affectsProfit: affectsProfit,
        );
  }

  static String? resolveTransactionTypeForMovement(CashMovementModel movement) {
    if (isExpenseMovement(
      directionType: movement.type,
      movementType: movement.movementType,
      affectsProfit: movement.affectsProfit,
    )) {
      return CashTransactionType.expense;
    }
    if (isWithdrawalMovement(
      directionType: movement.type,
      movementType: movement.movementType,
      affectsProfit: movement.affectsProfit,
    )) {
      return CashTransactionType.withdrawal;
    }
    return null;
  }

  static CashAccountingTotals buildTotals({
    required double totalSales,
    required double totalExpenses,
    required double totalWithdrawals,
  }) {
    return CashAccountingTotals(
      totalSales: _normalizeCurrency(totalSales),
      totalExpenses: _normalizePositive(totalExpenses),
      totalWithdrawals: _normalizePositive(totalWithdrawals),
    );
  }

  static double calculateProfit({
    required double totalSales,
    required double totalExpenses,
  }) {
    return _normalizeCurrency(totalSales - totalExpenses);
  }

  static double calculateExpectedCash({
    required double openingAmount,
    required double totalSales,
    required double totalExpenses,
    required double totalWithdrawals,
  }) {
    return _normalizeCurrency(
      openingAmount + totalSales - totalExpenses - totalWithdrawals,
    );
  }

  static double calculateExpectedDrawerCash({
    required double openingAmount,
    required double cashSales,
    required double cashRefunds,
    required double cashInManual,
    required double cashOutManual,
  }) {
    return _normalizeCurrency(
      openingAmount + cashSales - cashRefunds + cashInManual - cashOutManual,
    );
  }

  static CashClosingSummary buildClosingSummary({
    required double openingAmount,
    required double totalSales,
    required double totalExpenses,
    required double totalWithdrawals,
    required double countedCash,
  }) {
    final normalizedOpeningAmount = _normalizeCurrency(openingAmount);
    final normalizedSales = _normalizeCurrency(totalSales);
    final normalizedExpenses = _normalizePositive(totalExpenses);
    final normalizedWithdrawals = _normalizePositive(totalWithdrawals);
    final normalizedCountedCash = _normalizeCurrency(countedCash);
    final expectedCash = calculateExpectedCash(
      openingAmount: normalizedOpeningAmount,
      totalSales: normalizedSales,
      totalExpenses: normalizedExpenses,
      totalWithdrawals: normalizedWithdrawals,
    );
    return CashClosingSummary(
      openingAmount: normalizedOpeningAmount,
      totalSales: normalizedSales,
      totalExpenses: normalizedExpenses,
      totalWithdrawals: normalizedWithdrawals,
      expectedCash: expectedCash,
      countedCash: normalizedCountedCash,
      difference: _normalizeCurrency(normalizedCountedCash - expectedCash),
    );
  }

  static void validateAmount(double amount) {
    if (!amount.isFinite || amount <= 0) {
      throw Exception('El monto debe ser mayor a 0.');
    }
  }

  static double _normalizePositive(double value) {
    return _normalizeCurrency(value < 0 ? 0 : value);
  }

  static double _normalizeCurrency(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}
