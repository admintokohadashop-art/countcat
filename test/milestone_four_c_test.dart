import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/monthly_report.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/monthly_report_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/reports/report_totals.dart';
import 'package:tiktok_seller/features/reports/reports_page.dart';

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository([this._items = const []]);
  final List<Transaction> _items;
  Transaction? lastInserted;
  @override
  Future<int> insertTransaction(Transaction transaction) async {
    lastInserted = transaction;
    return 1;
  }
  @override
  Future<List<Transaction>> listTransactions({String search = '', int? liveSessionId, PaymentStatus? paymentStatus, OrderStatus? orderStatus, DateTime? periodStart, DateTime? periodEnd}) async {
    return _items.where((t) {
      if (periodStart != null && t.transactionDate.isBefore(periodStart)) return false;
      if (periodEnd != null && !t.transactionDate.isBefore(periodEnd)) return false;
      return true;
    }).toList();
  }
  @override
  Future<void> deleteTransaction(int id) async {}
  @override
  Future<void> updateTransaction(Transaction transaction) async {}
}

class _FakeMonthlyReportRepository implements MonthlyReportRepository {
  final List<MonthlyReport> _reports = [];
  @override
  Future<List<MonthlyReport>> listReports() async => List.unmodifiable(_reports);
  @override
  Future<void> save(MonthlyReport report) async {
    _reports.removeWhere((r) => r.year == report.year && r.month == report.month);
    _reports.add(report);
  }
}

class _FakeLiveSessionRepository implements LiveSessionRepository {
  @override
  Future<LiveSession> createSession({required String name, DateTime? startedAt}) async => throw UnimplementedError();
  @override
  Future<List<LiveSession>> listSessions() async => const [];
  @override
  Future<int?> getSelectedSessionId() async => null;
  @override
  Future<void> setSelectedSessionId(int? sessionId) async {}
  @override
  Future<LiveSession?> getSelectedSession() async => null;
}

Transaction _tx({
  int id = 1,
  required DateTime transactionDate,
  String orderId = 'O',
  int qty = 1,
  int unitPrice = 1000,
  int hppUnitAmount = 200,
  int netIncomeAmount = 900,
  OrderStatus orderStatus = OrderStatus.closed,
  PaymentStatus paymentStatus = PaymentStatus.paid,
}) {
  final now = DateTime(2026);
  return Transaction(
    id: id,
    transactionDate: transactionDate,
    productCode: 'P',
    orderId: orderId,
    quantity: qty,
    unitPrice: unitPrice,
    gmvAmount: unitPrice * qty,
    hppUnitAmount: hppUnitAmount,
    netIncomeAmount: netIncomeAmount,
    orderStatus: orderStatus,
    paymentStatus: paymentStatus,
    paidAt: paymentStatus == PaymentStatus.paid ? now : null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ReportTotals — Milestone 4C rules', () {
    test('active transaction contributes to all totals', () {
      final t = _tx(transactionDate: DateTime(2026, 8, 1));
      final r = ReportTotals.fromTransactions([t]);
      expect(r.gmv, 1000);
      expect(r.netIncome, 900);
      expect(r.hpp, 200);
      expect(r.profit, 700);
    });

    test('returned (order) keeps GMV but excludes Income/HPP/Profit', () {
      final t = _tx(transactionDate: DateTime(2026, 8, 1), orderStatus: OrderStatus.returned);
      final r = ReportTotals.fromTransactions([t]);
      expect(r.gmv, 1000);
      expect(r.netIncome, 0);
      expect(r.hpp, 0);
      expect(r.profit, 0);
    });

    test('cancel (order) keeps GMV but excludes Income/HPP/Profit', () {
      final t = _tx(transactionDate: DateTime(2026, 8, 1), orderStatus: OrderStatus.cancel);
      final r = ReportTotals.fromTransactions([t]);
      expect(r.gmv, 1000);
      expect(r.netIncome, 0);
      expect(r.hpp, 0);
      expect(r.profit, 0);
    });

    test('cancelled (payment) keeps GMV but excludes Income/HPP/Profit', () {
      final t = _tx(transactionDate: DateTime(2026, 8, 1), paymentStatus: PaymentStatus.cancelled);
      final r = ReportTotals.fromTransactions([t]);
      expect(r.gmv, 1000);
      expect(r.netIncome, 0);
      expect(r.hpp, 0);
      expect(r.profit, 0);
    });

    test('mix: GMV from all rows, income/hpp/profit only from active rows', () {
      final active = _tx(id: 1, transactionDate: DateTime(2026, 8, 1));
      final ret = _tx(id: 2, transactionDate: DateTime(2026, 8, 2), orderStatus: OrderStatus.returned);
      final can = _tx(id: 3, transactionDate: DateTime(2026, 8, 3), orderStatus: OrderStatus.cancel);
      final cancelPay = _tx(id: 4, transactionDate: DateTime(2026, 8, 4), paymentStatus: PaymentStatus.cancelled);
      final r = ReportTotals.fromTransactions([active, ret, can, cancelPay]);
      expect(r.gmv, 4000);
      expect(r.netIncome, 900);
      expect(r.hpp, 200);
      expect(r.profit, 700);
    });

    test('profit = income - (hpp snapshot × qty)', () {
      final t = _tx(transactionDate: DateTime(2026, 8, 1), qty: 3, unitPrice: 5000, hppUnitAmount: 2000, netIncomeAmount: 12000);
      final r = ReportTotals.fromTransactions([t]);
      expect(r.profit, 12000 - (2000 * 3));
    });
  });

  group('ReportsPage grouping by transactionDate', () {
    Future<void> pumpPage(WidgetTester tester, _FakeTransactionRepository tx, _FakeMonthlyReportRepository monthly) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReportsPage(
            transactionRepository: tx,
            monthlyReportRepository: monthly,
            liveSessionRepository: _FakeLiveSessionRepository(),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('groups by transactionDate, not createdAt, in DESC order', (tester) async {
      final tx = _FakeTransactionRepository([
        _tx(id: 1, transactionDate: DateTime(2026, 8, 18), orderId: 'A'),
        _tx(id: 2, transactionDate: DateTime(2026, 9, 15), orderId: 'B'),
      ]);
      await pumpPage(tester, tx, _FakeMonthlyReportRepository());
      expect(find.text('AGUSTUS 2026'), findsOneWidget);
      expect(find.text('SEPTEMBER 2026'), findsOneWidget);
      final sepY = tester.getTopLeft(find.text('SEPTEMBER 2026')).dy;
      final augY = tester.getTopLeft(find.text('AGUSTUS 2026')).dy;
      expect(sepY, lessThan(augY));
    });

    testWidgets('does not add current month placeholder when there are no transactions', (tester) async {
      final tx = _FakeTransactionRepository(const []);
      await pumpPage(tester, tx, _FakeMonthlyReportRepository());
      expect(find.text('Belum ada transaksi.'), findsOneWidget);
      final now = DateTime.now();
      final monthLabel = '${_monthNames[now.month - 1]} ${now.year}'.toUpperCase();
      expect(find.text(monthLabel), findsNothing);
    });
  });

  group('Monthly snapshot immutability', () {
    test('snapshot does not change when transactions change until resubmit', () async {
      final tx = _FakeTransactionRepository([
        _tx(id: 1, transactionDate: DateTime(2026, 8, 1)),
      ]);
      final monthly = _FakeMonthlyReportRepository();

      // First submit
      final first = ReportTotals.fromTransactions(await tx.listTransactions(periodStart: DateTime(2026, 8), periodEnd: DateTime(2026, 9)));
      await monthly.save(MonthlyReport(year: 2026, month: 8, periodStart: DateTime(2026, 8), periodEnd: DateTime(2026, 9), gmvTotal: first.gmv, netIncomeTotal: first.netIncome, hppTotal: first.hpp, profitTotal: first.profit, submittedAt: DateTime.now()));

      // Mutate source
      final updated = _tx(id: 1, transactionDate: DateTime(2026, 8, 1), orderStatus: OrderStatus.returned);
      final updatedRepo = _FakeTransactionRepository([updated]);
      final after = ReportTotals.fromTransactions(await updatedRepo.listTransactions(periodStart: DateTime(2026, 8), periodEnd: DateTime(2026, 9)));
      expect(after.netIncome, 0);

      // Snapshot is unchanged
      var snapshot = (await monthly.listReports()).single;
      expect(snapshot.netIncomeTotal, 900);

      // Resubmit replaces the snapshot
      await monthly.save(MonthlyReport(year: 2026, month: 8, periodStart: DateTime(2026, 8), periodEnd: DateTime(2026, 9), gmvTotal: after.gmv, netIncomeTotal: after.netIncome, hppTotal: after.hpp, profitTotal: after.profit, submittedAt: DateTime.now()));
      snapshot = (await monthly.listReports()).single;
      expect(snapshot.netIncomeTotal, 0);
      expect(snapshot.gmvTotal, 1000);
    });
  });

  group('Account model used by test doubles', () {
    test('Account can be constructed without a database', () {
      final now = DateTime(2026);
      final a = Account(id: 1, name: 'N', description: '', createdAt: now, updatedAt: now);
      expect(a.id, 1);
    });
  });

  test('AppDatabase.inMemoryForTesting does not need real plugins', () {
    final db = AppDatabase.inMemoryForTesting();
    expect(db, isNotNull);
  });
}

const _monthNames = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];