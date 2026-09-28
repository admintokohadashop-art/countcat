import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';

class ReportTotals {
  const ReportTotals({required this.gmv, required this.netIncome, required this.hpp, required this.profit});
  final int gmv, netIncome, hpp, profit;

  factory ReportTotals.fromTransactions(List<Transaction> items) {
    var gmv = 0, net = 0, hpp = 0, profit = 0;
    for (final t in items) {
      gmv += t.gmvAmount;
      final inactive = t.paymentStatus == PaymentStatus.cancelled ||
          t.orderStatus == OrderStatus.returned ||
          t.orderStatus == OrderStatus.cancel;
      if (inactive) continue;
      final cost = t.hppUnitAmount * t.quantity;
      net += t.netIncomeAmount;
      hpp += cost;
      profit += t.netIncomeAmount - cost;
    }
    return ReportTotals(gmv: gmv, netIncome: net, hpp: hpp, profit: profit);
  }
}