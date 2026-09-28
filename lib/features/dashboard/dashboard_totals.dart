import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';

/// Lifetime summary for the active account.
///
/// Computed from the full transaction history (all months, all years).
/// Never derived from `MonthlyReport` snapshots.
///
/// Active rule (identical to Milestone 4C):
/// `paymentStatus != cancelled && orderStatus != returned && orderStatus != cancel`.
///
/// - [gmv] counts every transaction (including RETURNED).
/// - [itemsSold], [activeIncome], [activeHpp], [profit] use only active transactions.
/// - [returnedQty] is SUM(quantity) where orderStatus == returned, regardless of paymentStatus.
/// - [totalCompensation] is SUM(returnShippingCompensation) for the same filter.
/// - [profit] = activeIncome - activeHpp. It does NOT subtract totalCompensation.
class DashboardTotals {
  const DashboardTotals({
    required this.itemsSold,
    required this.gmv,
    required this.activeIncome,
    required this.activeHpp,
    required this.profit,
    required this.returnedQty,
    required this.totalCompensation,
  });

  final int itemsSold;
  final int gmv;
  final int activeIncome;
  final int activeHpp;
  final int profit;
  final int returnedQty;
  final int totalCompensation;

  factory DashboardTotals.fromTransactions(List<Transaction> items) {
    var itemsSold = 0;
    var gmv = 0;
    var activeIncome = 0;
    var activeHpp = 0;
    var returnedQty = 0;
    var totalCompensation = 0;
    for (final t in items) {
      gmv += t.gmvAmount;
      if (t.orderStatus == OrderStatus.returned) {
        returnedQty += t.quantity;
        totalCompensation += t.returnShippingCompensation;
      }
      final inactive = t.paymentStatus == PaymentStatus.cancelled ||
          t.orderStatus == OrderStatus.returned ||
          t.orderStatus == OrderStatus.cancel;
      if (inactive) continue;
      itemsSold += t.quantity;
      activeIncome += t.netIncomeAmount;
      activeHpp += t.hppUnitAmount * t.quantity;
    }
    return DashboardTotals(
      itemsSold: itemsSold,
      gmv: gmv,
      activeIncome: activeIncome,
      activeHpp: activeHpp,
      profit: activeIncome - activeHpp,
      returnedQty: returnedQty,
      totalCompensation: totalCompensation,
    );
  }
}