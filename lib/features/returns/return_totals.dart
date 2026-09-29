import '../../data/models/order.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_with_order.dart';

/// Aggregated figures for the RETUR report under M7 multi-item semantics.
///
/// - [returnedCount] counts unique returned orders, not item rows.
/// - [returnedQty] sums item quantities inside returned orders.
/// - [totalCompensation] sums `order.return_shipping_compensation` exactly
///   once per returned order (compensation is order-level, not per item).
/// - [activeIncome] / [activeHpp] follow the 4C active rule, applied at the
///   parent-order level.
/// - [incomeAfterReturn] and [profitAfterReturn] may be negative. Do not clamp.
class ReturnTotals {
  const ReturnTotals({
    required this.returnedCount,
    required this.returnedQty,
    required this.totalCompensation,
    required this.activeIncome,
    required this.activeHpp,
    required this.incomeAfterReturn,
    required this.profitAfterReturn,
  });

  final int returnedCount;
  final int returnedQty;
  final int totalCompensation;
  final int activeIncome;
  final int activeHpp;
  final int incomeAfterReturn;
  final int profitAfterReturn;

  factory ReturnTotals.fromJoined(List<TransactionWithOrder> items) {
    var returnedQty = 0;
    var totalCompensation = 0;
    var activeIncome = 0;
    var activeHpp = 0;
    final seenReturned = <String>{};

    for (final v in items) {
      final o = v.order;
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
      activeIncome += v.item.netIncomeAmount;
      activeHpp += v.item.hppUnitAmount * v.item.quantity;
    }

    final incomeAfterReturn = activeIncome - totalCompensation;
    final profitAfterReturn = incomeAfterReturn - activeHpp;
    return ReturnTotals(
      returnedCount: seenReturned.length,
      returnedQty: returnedQty,
      totalCompensation: totalCompensation,
      activeIncome: activeIncome,
      activeHpp: activeHpp,
      incomeAfterReturn: incomeAfterReturn,
      profitAfterReturn: profitAfterReturn,
    );
  }

  factory ReturnTotals.fromTransactions(List<Transaction> items) =>
      ReturnTotals.fromJoined(items.map(TransactionWithOrder.fromTransaction).toList(growable: false));

  static String _key(Order o) =>
      o.id != null ? 'id:${o.id}' : 'k:${o.accountId}::${o.orderId}';
}