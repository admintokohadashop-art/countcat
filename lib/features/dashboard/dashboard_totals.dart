import '../../data/models/order.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_with_order.dart';

/// Lifetime summary for the active account under M7 multi-item semantics.
///
/// Computed from the full transaction history (all months, all years), never
/// from `MonthlyReport` snapshots.
///
/// Active rule (identical to 4C):
/// `paymentStatus != cancelled && orderStatus != returned && orderStatus != cancel`.
///
/// - [gmv] counts every item (including items of RETURNED orders).
/// - [itemsSold], [activeIncome], [activeHpp], [profit] use items whose
///   parent order is active.
/// - [returnedQty] sums item quantities inside returned orders.
/// - [totalCompensation] sums `order.return_shipping_compensation` once per
///   returned order.
/// - [profit] = activeIncome - activeHpp. It does NOT subtract
///   totalCompensation.
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

  factory DashboardTotals.fromJoined(List<TransactionWithOrder> items) {
    var itemsSold = 0;
    var gmv = 0;
    var activeIncome = 0;
    var activeHpp = 0;
    var returnedQty = 0;
    var totalCompensation = 0;
    final seenReturned = <String>{};

    for (final v in items) {
      final o = v.order;
      gmv += v.item.gmvAmount;
      if (o.orderStatus == OrderStatus.returned) {
        returnedQty += v.item.quantity;
        if (seenReturned.add(_key(o))) {
          totalCompensation += o.returnShippingCompensation;
        }
      }
      final inactive = o.paymentStatus == PaymentStatus.cancelled ||
          o.orderStatus == OrderStatus.returned ||
          o.orderStatus == OrderStatus.cancel;
      if (inactive) continue;
      itemsSold += v.item.quantity;
      activeIncome += v.item.netIncomeAmount;
      activeHpp += v.item.hppUnitAmount * v.item.quantity;
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

  factory DashboardTotals.fromTransactions(List<Transaction> items) =>
      DashboardTotals.fromJoined(items.map(TransactionWithOrder.fromTransaction).toList(growable: false));

  static String _key(Order o) =>
      o.id != null ? 'id:${o.id}' : 'k:${o.accountId}::${o.orderId}';
}