class MonthlyReport {
  const MonthlyReport({required this.year, required this.month, required this.periodStart, required this.periodEnd, required this.gmvTotal, required this.netIncomeTotal, required this.hppTotal, required this.profitTotal, required this.submittedAt});
  final int year;
  final int month;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int gmvTotal;
  final int netIncomeTotal;
  final int hppTotal;
  final int profitTotal;
  final DateTime submittedAt;
  factory MonthlyReport.fromMap(Map<String, Object?> map) => MonthlyReport(year: map['year'] as int, month: map['month'] as int, periodStart: DateTime.parse(map['period_start'] as String), periodEnd: DateTime.parse(map['period_end'] as String), gmvTotal: map['gmv_total'] as int, netIncomeTotal: map['net_income_total'] as int, hppTotal: map['hpp_total'] as int, profitTotal: map['profit_total'] as int, submittedAt: DateTime.parse(map['submitted_at'] as String));
  Map<String, Object?> toMap() => {'year': year, 'month': month, 'period_start': periodStart.toUtc().toIso8601String(), 'period_end': periodEnd.toUtc().toIso8601String(), 'gmv_total': gmvTotal, 'net_income_total': netIncomeTotal, 'hpp_total': hppTotal, 'profit_total': profitTotal, 'submitted_at': submittedAt.toUtc().toIso8601String()};
}
