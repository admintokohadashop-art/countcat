import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';

class ReportTotals {
  const ReportTotals({required this.gmv, required this.netIncome, required this.hpp, required this.profit});
  final int gmv;
  final int netIncome;
  final int hpp;
  final int profit;

  factory ReportTotals.fromTransactions(List<Transaction> transactions, int globalHpp) {
    var gmv = 0;
    var netIncome = 0;
    var hpp = 0;
    var profit = 0;
    for (final transaction in transactions) {
      gmv += transaction.gmvAmount;
      if (transaction.paymentStatus == PaymentStatus.cancelled) continue;
      final transactionHpp = globalHpp * transaction.quantity;
      netIncome += transaction.netIncomeAmount;
      hpp += transactionHpp;
      profit += transaction.netIncomeAmount - transactionHpp;
    }
    return ReportTotals(gmv: gmv, netIncome: netIncome, hpp: hpp, profit: profit);
  }
}
