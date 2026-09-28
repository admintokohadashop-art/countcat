import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';

/// Aggregated figures for the RETUR report.
///
/// [returnedCount] and [totalCompensation] count every transaction whose
/// `orderStatus == returned`, regardless of `paymentStatus` (including
/// `cancelled`, since OrderStatus determines the operational return status).
///
/// [activeIncome] and [activeHpp] follow the 4C active rule: only
/// transactions that are not `paymentStatus.cancelled`, not
/// `orderStatus.returned`, and not `orderStatus.cancel`.
///
/// [incomeAfterReturn] and [profitAfterReturn] may be negative. Do not clamp.
class ReturnTotals {
  const ReturnTotals({
    required this.returnedCount,
    required this.totalCompensation,
    required this.activeIncome,
    required this.activeHpp,
    required this.incomeAfterReturn,
    required this.profitAfterReturn,
  });

  final int returnedCount;
  final int totalCompensation;
  final int activeIncome;
  final int activeHpp;
  final int incomeAfterReturn;
  final int profitAfterReturn;

  factory ReturnTotals.fromTransactions(List<Transaction> items) {
    var returnedCount = 0;
    var totalCompensation = 0;
    var activeIncome = 0;
    var activeHpp = 0;
    for (final t in items) {
      if (t.orderStatus == OrderStatus.returned) {
        returnedCount += 1;
        totalCompensation += t.returnShippingCompensation;
      }
      final inactive = t.paymentStatus == PaymentStatus.cancelled ||
          t.orderStatus == OrderStatus.returned ||
          t.orderStatus == OrderStatus.cancel;
      if (inactive) continue;
      activeIncome += t.netIncomeAmount;
      activeHpp += t.hppUnitAmount * t.quantity;
    }
    final incomeAfterReturn = activeIncome - totalCompensation;
    final profitAfterReturn = incomeAfterReturn - activeHpp;
    return ReturnTotals(
      returnedCount: returnedCount,
      totalCompensation: totalCompensation,
      activeIncome: activeIncome,
      activeHpp: activeHpp,
      incomeAfterReturn: incomeAfterReturn,
      profitAfterReturn: profitAfterReturn,
    );
  }
}