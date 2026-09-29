import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/monthly_report.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/monthly_report_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_page.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_totals.dart';
import 'package:tiktok_seller/features/reports/report_totals.dart';
import 'package:tiktok_seller/features/reports/reports_page.dart';
import 'package:tiktok_seller/features/returns/returns_page.dart';

Transaction _tx({
  required DateTime transactionDate,
  String orderId = 'O',
  String productCode = 'P',
  int quantity = 1,
  int unitPrice = 1000,
  int hppUnitAmount = 0,
  int gmvAmount = 0,
  int netIncomeAmount = 1000,
  int returnShippingCompensation = 0,
  OrderStatus orderStatus = OrderStatus.closed,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  int? id,
}) {
  final now = DateTime(2026);
  return Transaction(
    id: id,
    transactionDate: transactionDate,
    productCode: productCode,
    orderId: orderId,
    quantity: quantity,
    unitPrice: unitPrice,
    gmvAmount: gmvAmount == 0 ? unitPrice * quantity : gmvAmount,
    hppUnitAmount: hppUnitAmount,
    netIncomeAmount: netIncomeAmount,
    returnShippingCompensation: returnShippingCompensation,
    orderStatus: orderStatus,
    paymentStatus: paymentStatus,
    paidAt: paymentStatus == PaymentStatus.paid ? now : null,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this.accounts = const [], this.active});
  final List<Account> accounts;
  final Account? active;
  @override
  Future<List<Account>> listAccounts() async => accounts;
  @override
  Future<Account?> activeAccount() async => active;
  @override
  Future<void> setActiveAccountId(int? id) async {}
  @override
  Future<Account> create({required String name, String description = '', String? photoPath}) async => throw UnimplementedError();
  @override
  Future<void> update(Account account) async {}
  @override
  Future<void> delete(Account account) async {}
}

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository([this._items = const []]);
  final List<Transaction> _items;
  @override
  Future<int> insertTransaction(Transaction transaction) async => 1;
  @override
  Future<List<Transaction>> listTransactions({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    return _items.where((t) {
      if (search.isNotEmpty && !t.orderId.contains(search)) return false;
      if (orderStatus != null && t.orderStatus != orderStatus) return false;
      if (paymentStatus != null && t.paymentStatus != paymentStatus) return false;
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

class _FakeMonthlyReportRepository implements MonthlyReportRepository {
  @override
  Future<List<MonthlyReport>> listReports() async => const [];
  @override
  Future<void> save(MonthlyReport report) async {}
}

void main() {
  group('Year rollover', () {
    late AppDatabase database;
    late AccountRepository accounts;
    late TransactionRepository transactions;

    setUp(() async {
      database = AppDatabase.inMemoryForTesting();
      accounts = AccountRepository(database);
      transactions = TransactionRepository(database);
      await accounts.create(name: 'Main shop');
    });
    tearDown(() => database.close());

    test('December 2026 and January 2027 are separate periods', () async {
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 12, 31), orderId: 'DEC'));
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2027, 1, 1), orderId: 'JAN'));

      final dec = await transactions.listTransactions(
        periodStart: DateTime(2026, 12),
        periodEnd: DateTime(2027, 1),
      );
      final jan = await transactions.listTransactions(
        periodStart: DateTime(2027, 1),
        periodEnd: DateTime(2027, 2),
      );

      expect(dec.map((t) => t.orderId), ['DEC']);
      expect(jan.map((t) => t.orderId), ['JAN']);
    });

    test('ReportTotals per period do not mix across the year boundary', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 12, 31),
        orderId: 'DEC',
        netIncomeAmount: 10000,
        hppUnitAmount: 2000,
        quantity: 1,
      ));
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2027, 1, 1),
        orderId: 'JAN',
        netIncomeAmount: 20000,
        hppUnitAmount: 3000,
        quantity: 1,
      ));

      final dec = await transactions.listTransactions(
        periodStart: DateTime(2026, 12),
        periodEnd: DateTime(2027, 1),
      );
      final jan = await transactions.listTransactions(
        periodStart: DateTime(2027, 1),
        periodEnd: DateTime(2027, 2),
      );

      final decTotals = ReportTotals.fromTransactions(dec);
      final janTotals = ReportTotals.fromTransactions(jan);

      expect(decTotals.netIncome, 10000);
      expect(janTotals.netIncome, 20000);
    });

    test('edit transactionDate moves the row from Dec 2026 to Jan 2027', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 12, 31),
        orderId: 'MOVE',
      ));
      final stored = (await transactions.listTransactions()).single;
      await transactions.updateTransaction(stored.copyWith(transactionDate: DateTime(2027, 1, 15)));

      final dec = await transactions.listTransactions(
        periodStart: DateTime(2026, 12),
        periodEnd: DateTime(2027, 1),
      );
      final jan = await transactions.listTransactions(
        periodStart: DateTime(2027, 1),
        periodEnd: DateTime(2027, 2),
      );

      expect(dec, isEmpty);
      expect(jan.single.orderId, 'MOVE');
    });

    test('ReturnPeriod 2026-12 and 2027-01 are distinct', () {
      const dec = ReturnPeriod(2026, 12);
      const jan = ReturnPeriod(2027, 1);
      expect(dec == jan, isFalse);
      expect(dec.label, 'DESEMBER 2026');
      expect(jan.label, 'JANUARI 2027');
      expect(dec.compareTo(jan), lessThan(0));
    });

    test('DashboardTotals lifetime sums both years together', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 12, 31),
        orderId: 'DEC',
        netIncomeAmount: 10000,
        hppUnitAmount: 2000,
        quantity: 2,
      ));
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2027, 1, 1),
        orderId: 'JAN',
        netIncomeAmount: 20000,
        hppUnitAmount: 3000,
        quantity: 3,
      ));

      final all = await transactions.listTransactions();
      final totals = DashboardTotals.fromTransactions(all);
      expect(totals.itemsSold, 5);
      expect(totals.activeIncome, 30000);
      expect(totals.activeHpp, 2000 * 2 + 3000 * 3);
      expect(totals.profit, 30000 - (2000 * 2 + 3000 * 3));
    });
  });

  group('DashboardTotals', () {
    test('empty list yields zeroes', () {
      final t = DashboardTotals.fromTransactions(const []);
      expect(t.itemsSold, 0);
      expect(t.gmv, 0);
      expect(t.activeIncome, 0);
      expect(t.activeHpp, 0);
      expect(t.profit, 0);
      expect(t.returnedQty, 0);
      expect(t.totalCompensation, 0);
    });

    test('active rows contribute to qty/GMV/income/HPP/profit', () {
      final items = [
        _tx(
          transactionDate: DateTime(2026, 8, 1),
          quantity: 3,
          unitPrice: 50000,
          netIncomeAmount: 140000,
          hppUnitAmount: 20000,
          orderStatus: OrderStatus.closed,
        ),
      ];
      final t = DashboardTotals.fromTransactions(items);
      expect(t.itemsSold, 3);
      expect(t.gmv, 150000);
      expect(t.activeIncome, 140000);
      expect(t.activeHpp, 60000);
      expect(t.profit, 80000);
      expect(t.returnedQty, 0);
      expect(t.totalCompensation, 0);
    });

    test('RETURNED is excluded from active metrics but counted in GMV/returnedQty/compensation', () {
      final items = [
        _tx(
          transactionDate: DateTime(2026, 8, 1),
          quantity: 2,
          unitPrice: 50000,
          netIncomeAmount: 90000,
          hppUnitAmount: 20000,
          orderStatus: OrderStatus.returned,
          returnShippingCompensation: 30000,
        ),
      ];
      final t = DashboardTotals.fromTransactions(items);
      expect(t.itemsSold, 0);
      expect(t.activeIncome, 0);
      expect(t.activeHpp, 0);
      expect(t.profit, 0);
      expect(t.gmv, 100000);
      expect(t.returnedQty, 2);
      expect(t.totalCompensation, 30000);
    });

    test('CANCEL is excluded from active metrics but counted in GMV', () {
      final items = [
        _tx(
          transactionDate: DateTime(2026, 8, 1),
          quantity: 4,
          unitPrice: 25000,
          netIncomeAmount: 80000,
          hppUnitAmount: 10000,
          orderStatus: OrderStatus.cancel,
        ),
      ];
      final t = DashboardTotals.fromTransactions(items);
      expect(t.itemsSold, 0);
      expect(t.activeIncome, 0);
      expect(t.activeHpp, 0);
      expect(t.profit, 0);
      expect(t.gmv, 100000);
      expect(t.returnedQty, 0);
    });

    test('payment cancelled is excluded from active metrics but counted in GMV', () {
      final items = [
        _tx(
          transactionDate: DateTime(2026, 8, 1),
          quantity: 2,
          unitPrice: 30000,
          netIncomeAmount: 50000,
          hppUnitAmount: 15000,
          orderStatus: OrderStatus.closed,
          paymentStatus: PaymentStatus.cancelled,
        ),
      ];
      final t = DashboardTotals.fromTransactions(items);
      expect(t.itemsSold, 0);
      expect(t.activeIncome, 0);
      expect(t.activeHpp, 0);
      expect(t.profit, 0);
      expect(t.gmv, 60000);
    });

    test('RETURNED + payment cancelled is still returned with compensation', () {
      final items = [
        _tx(
          transactionDate: DateTime(2026, 8, 1),
          quantity: 3,
          unitPrice: 40000,
          netIncomeAmount: 100000,
          hppUnitAmount: 20000,
          orderStatus: OrderStatus.returned,
          paymentStatus: PaymentStatus.cancelled,
          returnShippingCompensation: 25000,
        ),
      ];
      final t = DashboardTotals.fromTransactions(items);
      expect(t.itemsSold, 0);
      expect(t.activeIncome, 0);
      expect(t.activeHpp, 0);
      expect(t.profit, 0);
      expect(t.gmv, 120000);
      expect(t.returnedQty, 3);
      expect(t.totalCompensation, 25000);
    });

    test('Dashboard profit does not subtract compensation', () {
      final items = [
        _tx(
          transactionDate: DateTime(2026, 8, 1),
          quantity: 2,
          unitPrice: 50000,
          netIncomeAmount: 90000,
          hppUnitAmount: 20000,
          orderStatus: OrderStatus.closed,
        ),
        _tx(
          transactionDate: DateTime(2026, 8, 2),
          quantity: 1,
          unitPrice: 10000,
          netIncomeAmount: 0,
          hppUnitAmount: 0,
          orderStatus: OrderStatus.returned,
          returnShippingCompensation: 40000,
        ),
      ];
      final t = DashboardTotals.fromTransactions(items);
      expect(t.activeIncome, 90000);
      expect(t.activeHpp, 40000);
      expect(t.profit, 50000);
      expect(t.totalCompensation, 40000);
    });
  });

  group('Reports copy ID Pesanan', () {
    testWidgets('copy icon copies exact orderId and shows snackbar', (tester) async {
      tester.view.physicalSize = const Size(2400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final log = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          log.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final fakeTx = _FakeTransactionRepository([
        _tx(
          id: 1,
          orderId: 'ORDER-COPY-XYZ',
          transactionDate: DateTime(2026, 8, 20),
          orderStatus: OrderStatus.closed,
        ),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: MonthDetailPage(
          month: const ReportMonth(2026, 8),
          transactionRepository: fakeTx,
          monthlyReportRepository: _FakeMonthlyReportRepository(),
          liveSessionRepository: _FakeLiveSessionRepository(),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.copy), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      await tester.pump();

      final clipboardCall = log.firstWhere(
        (c) => c.method == 'Clipboard.setData',
        orElse: () => throw StateError('Clipboard.setData not invoked'),
      );
      expect((clipboardCall.arguments as Map)['text'], 'ORDER-COPY-XYZ');
      expect(find.text('ID Pesanan disalin.'), findsOneWidget);
    });
  });

  group('Dashboard widget', () {
    Future<void> pumpDashboard(
      WidgetTester tester, {
      required _FakeAccountRepository accounts,
      required _FakeTransactionRepository transactions,
    }) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DashboardPage(repository: accounts, transactionRepository: transactions),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows all six summary rows with the active account', (tester) async {
      final active = Account(id: 1, name: 'Main', description: '', createdAt: DateTime(2026), updatedAt: DateTime(2026));
      await pumpDashboard(
        tester,
        accounts: _FakeAccountRepository(accounts: [active], active: active),
        transactions: _FakeTransactionRepository([
          _tx(
            transactionDate: DateTime(2026, 8, 1),
            quantity: 5,
            unitPrice: 100000,
            netIncomeAmount: 450000,
            hppUnitAmount: 30000,
            orderStatus: OrderStatus.closed,
          ),
          _tx(
            transactionDate: DateTime(2026, 8, 2),
            quantity: 2,
            unitPrice: 50000,
            netIncomeAmount: 80000,
            hppUnitAmount: 20000,
            orderStatus: OrderStatus.returned,
            returnShippingCompensation: 30000,
          ),
        ]),
      );

      expect(find.text('Ringkasan'), findsOneWidget);
      expect(find.text('Barang Terjual'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('GMV'), findsOneWidget);
      expect(find.text('Rp600.000'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Rp450.000'), findsOneWidget);
      expect(find.text('Profit'), findsOneWidget);
      expect(find.text('Rp300.000'), findsOneWidget);
      expect(find.text('Retur'), findsOneWidget);
      expect(find.text('2 barang'), findsOneWidget);
      expect(find.text('Kompensasi'), findsOneWidget);
      expect(find.text('Rp30.000'), findsOneWidget);
    });

    testWidgets('shows six zero rows when active account has no transactions', (tester) async {
      final active = Account(id: 1, name: 'Main', description: '', createdAt: DateTime(2026), updatedAt: DateTime(2026));
      await pumpDashboard(
        tester,
        accounts: _FakeAccountRepository(accounts: [active], active: active),
        transactions: _FakeTransactionRepository(const []),
      );

      expect(find.text('Ringkasan'), findsOneWidget);
      expect(find.text('Barang Terjual'), findsOneWidget);
      expect(find.text('GMV'), findsOneWidget);
      expect(find.text('Rp0'), findsNWidgets(4));
      expect(find.text('0'), findsOneWidget);
      expect(find.text('0 barang'), findsOneWidget);
    });

    testWidgets('hides Ringkasan when no active account', (tester) async {
      await pumpDashboard(
        tester,
        accounts: _FakeAccountRepository(),
        transactions: _FakeTransactionRepository(const []),
      );
      expect(find.text('Ringkasan'), findsNothing);
      expect(find.text('Create New Account'), findsOneWidget);
    });

    testWidgets('Create New Account opens the create dialog', (tester) async {
      final active = Account(id: 1, name: 'Main', description: '', createdAt: DateTime(2026), updatedAt: DateTime(2026));
      await pumpDashboard(
        tester,
        accounts: _FakeAccountRepository(accounts: [active], active: active),
        transactions: _FakeTransactionRepository(const []),
      );
      await tester.ensureVisible(find.text('Create New Account'));
      await tester.pump();
      await tester.tap(find.text('Create New Account'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('CREATE'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
    });
  });
}