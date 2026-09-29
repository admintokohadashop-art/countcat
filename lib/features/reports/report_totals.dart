import '../../data/models/order.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_with_order.dart';

/// Report totals for the 4C active rule under M7 multi-item semantics.
///
/// - GMV counts every item's `gmv_amount`, including items whose parent
///   order is returned / cancelled-payment / cancel.
/// - Active income / HPP / profit count only items whose parent order is
///   active per 4C: `payment_status != cancelled && order_status != returned
///   && order_status != cancel`.
/// - Order-level status decisions always come from the parent order, never
///   from transitional mirror fields on the item.
class ReportTotals {
  const ReportTotals({required this.gmv, required this.netIncome, required this.hpp, required this.profit});
  final int gmv, netIncome, hpp, profit;

  factory ReportTotals.fromJoined(List<TransactionWithOrder> items) {
    var gmv = 0, net = 0, hpp = 0, profit = 0;
    for (final v in items) {
      gmv += v.item.gmvAmount;
      if (_inactive(v.order)) continue;
      final cost = v.item.hppUnitAmount * v.item.quantity;
      net += v.item.netIncomeAmount;
      hpp += cost;
      profit += v.item.netIncomeAmount - cost;
    }
    return ReportTotals(gmv: gmv, netIncome: net, hpp: hpp, profit: profit);
  }

  /// Transitional single-item entry point for M1–M6 call-sites. Results are
  /// identical to `fromJoined` when each `Transaction` represents a 1-item
  /// order (its mirror order-level fields equal the real parent order).
  factory ReportTotals.fromTransactions(List<Transaction> items) =>
      ReportTotals.fromJoined(items.map(TransactionWithOrder.fromTransaction).toList(growable: false));

  static bool _inactive(Order o) =>
      o.paymentStatus == PaymentStatus.cancelled ||
      o.orderStatus == OrderStatus.returned ||
      o.orderStatus == OrderStatus.cancel;
}