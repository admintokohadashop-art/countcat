import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/core/currency/rupiah.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/hpp_master.dart';
import 'package:tiktok_seller/data/models/monthly_report.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/hpp_repository.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/monthly_report_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/reports/report_totals.dart';
import 'package:tiktok_seller/features/sales/transaction_validator.dart';

void main() {
  late AppDatabase database;
  late AccountRepository accounts;
  late HppRepository hpp;
  late LiveSessionRepository sessions;
  late TransactionRepository transactions;

  setUp(() async {
    database = AppDatabase.inMemoryForTesting();
    accounts = AccountRepository(database);
    hpp = HppRepository(database);
    sessions = LiveSessionRepository(database);
    transactions = TransactionRepository(database);
    await accounts.create(name: 'Main shop');
  });
  tearDown(() => database.close());

  test('parses and formats Rupiah input', () {
    expect(Rupiah.parse('Rp5.000'), 5000);
    expect(Rupiah.format(12500), 'Rp12.500');
  });

  test('creates account-scoped HPP and deactivates it without deleting it', () async {
    final account = (await accounts.activeAccount())!;
    final item = await hpp.create(
      accountId: account.id!,
      name: 'Cardigan',
      unitAmount: 20000,
    );
    expect((await hpp.list(account.id!)).single.name, 'Cardigan');
    await hpp.deactivate(item.id!, account.id!);
    expect(await hpp.list(account.id!), isEmpty);
    expect((await hpp.list(account.id!, activeOnly: false)).single.isActive, isFalse);
  });

  test('HPP master data is isolated per account', () async {
    final first = (await accounts.activeAccount())!;
    await hpp.create(accountId: first.id!, name: 'Kaos', unitAmount: 15000);
    final second = await accounts.create(name: 'Second shop');
    await hpp.create(accountId: second.id!, name: 'Blouse', unitAmount: 25000);
    expect((await hpp.list(first.id!)).map((item) => item.name), ['Kaos']);
    expect((await hpp.list(second.id!)).map((item) => item.name), ['Blouse']);
  });

  test('creates and selects account-scoped sessions', () async {
    final first = await sessions.createSession(name: 'Live #1');
    final second = await sessions.createSession(name: 'Live #2');
    expect((await sessions.listSessions()).map((item) => item.name), ['Live #2', 'Live #1']);
    await sessions.setSelectedSessionId(first.id);
    expect(await sessions.getSelectedSessionId(), first.id);
    expect(second.id, isNot(first.id));
  });

  test('creates a transaction with its HPP snapshot', () async {
    final item = await _createHpp(hpp, accounts, 5000);
    await transactions.insertTransaction(_transaction(hppId: item.id, hppUnitAmount: item.unitAmount));
    final stored = (await transactions.listTransactions()).single;
    expect(stored.hppId, item.id);
    expect(stored.hppUnitAmount, 5000);
  });

  test('rejects duplicate order ID within the same account', () async {
    await transactions.insertTransaction(_transaction(orderId: 'ORDER-1'));
    await expectLater(
      transactions.insertTransaction(_transaction(orderId: 'ORDER-1')),
      throwsA(isA<DuplicateOrderIdException>()),
    );
  });

  test('allows the same order ID in different accounts', () async {
    await transactions.insertTransaction(_transaction(orderId: 'SHARED'));
    await accounts.create(name: 'Other shop');
    await transactions.insertTransaction(_transaction(orderId: 'SHARED'));
    expect((await transactions.listTransactions()).single.orderId, 'SHARED');
  });

  test('validates required transaction values and payment date rules', () {
    expect(TransactionValidator.productCode(''), isNotNull);
    expect(TransactionValidator.orderId(''), isNotNull);
    expect(TransactionValidator.quantity('0'), isNotNull);
    expect(TransactionValidator.quantity('1'), isNull);
    expect(TransactionValidator.paidAt(PaymentStatus.paid, null), isNotNull);
    expect(TransactionValidator.paidAt(PaymentStatus.paid, DateTime(2026, 9, 26)), isNull);
    expect(TransactionValidator.normalizePaidAt(PaymentStatus.pending, DateTime.now()), isNull);
  });

  test('cancelled transaction preserves stored financial amounts', () async {
    await transactions.insertTransaction(_transaction(
      orderId: 'ORDER-C',
      paymentStatus: PaymentStatus.cancelled,
      gmvAmount: 22000,
      netIncomeAmount: 20000,
    ));
    final row = (await (await database.database).query(
      'transactions',
      where: 'order_id = ?',
      whereArgs: ['ORDER-C'],
    )).single;
    expect(row['gmv_amount'], 22000);
    expect(row['net_income_amount'], 20000);
    expect(row['paid_at'], isNull);
  });

  test('payment and order statuses remain independent', () async {
    final now = DateTime.now();
    for (final combination in [
      (PaymentStatus.paid, OrderStatus.shipping),
      (PaymentStatus.cancelled, OrderStatus.returned),
    ]) {
      await transactions.insertTransaction(_transaction(
        orderId: 'COMBO-${combination.$1.value}',
        paymentStatus: combination.$1,
        paidAt: combination.$1 == PaymentStatus.paid ? now : null,
        orderStatus: combination.$2,
      ));
    }
    expect((await transactions.listTransactions()).length, 2);
  });

  test('lists, searches, filters, and updates active-account transactions', () async {
    final session = await sessions.createSession(name: 'Live Filter');
    await transactions.insertTransaction(_transaction(
      orderId: 'ORDER-OLD',
      productCode: 'ALPHA',
      liveSessionId: session.id,
      paymentStatus: PaymentStatus.paid,
      paidAt: DateTime(2026, 1, 1),
      orderStatus: OrderStatus.shipping,
      createdAt: DateTime(2026, 1, 1),
    ));
    await transactions.insertTransaction(_transaction(
      orderId: 'ORDER-NEW',
      productCode: 'BETA',
      createdAt: DateTime(2026, 1, 2),
    ));
    expect((await transactions.listTransactions()).first.orderId, 'ORDER-NEW');
    expect((await transactions.listTransactions(search: 'ALPHA')).single.orderId, 'ORDER-OLD');
    expect((await transactions.listTransactions(liveSessionId: session.id)).single.orderId, 'ORDER-OLD');
    final original = (await transactions.listTransactions(search: 'BETA')).single;
    await transactions.updateTransaction(original.copyWith(productCode: 'UPDATED', quantity: 2));
    final updated = (await transactions.listTransactions(search: 'UPDATED')).single;
    expect(updated.createdAt, original.createdAt);
    expect(updated.quantity, 2);
  });

  test('rejects a conflicting order ID during update in the same account', () async {
    await transactions.insertTransaction(_transaction(orderId: 'KEEP'));
    await transactions.insertTransaction(_transaction(orderId: 'EDIT'));
    final editable = (await transactions.listTransactions(search: 'EDIT')).single;
    await expectLater(
      transactions.updateTransaction(editable.copyWith(orderId: 'KEEP')),
      throwsA(isA<DuplicateOrderIdException>()),
    );
  });

  test('uses transaction HPP snapshots and excludes cancelled financial totals', () async {
    await transactions.insertTransaction(_transaction(
      orderId: 'ACTIVE',
      quantity: 2,
      gmvAmount: 20000,
      netIncomeAmount: 16000,
      hppUnitAmount: 5000,
    ));
    await transactions.insertTransaction(_transaction(
      orderId: 'CANCELLED',
      quantity: 3,
      gmvAmount: 22000,
      netIncomeAmount: 20000,
      hppUnitAmount: 9000,
      paymentStatus: PaymentStatus.cancelled,
    ));
    final totals = ReportTotals.fromTransactions(await transactions.listTransactions());
    expect(totals.gmv, 42000);
    expect(totals.netIncome, 16000);
    expect(totals.hpp, 10000);
    expect(totals.profit, 6000);
  });

  test('excludes returned and cancel order status from active totals but keeps GMV', () async {
    await transactions.insertTransaction(_transaction(
      orderId: 'ACTIVE',
      quantity: 2,
      gmvAmount: 20000,
      netIncomeAmount: 16000,
      hppUnitAmount: 5000,
    ));
    await transactions.insertTransaction(_transaction(
      orderId: 'RET',
      quantity: 1,
      gmvAmount: 12000,
      netIncomeAmount: 10000,
      hppUnitAmount: 4000,
      orderStatus: OrderStatus.returned,
    ));
    await transactions.insertTransaction(_transaction(
      orderId: 'CAN',
      quantity: 1,
      gmvAmount: 8000,
      netIncomeAmount: 6000,
      hppUnitAmount: 3000,
      orderStatus: OrderStatus.cancel,
    ));
    final totals = ReportTotals.fromTransactions(await transactions.listTransactions());
    expect(totals.gmv, 40000);
    expect(totals.netIncome, 16000);
    expect(totals.hpp, 10000);
    expect(totals.profit, 6000);
  });

  test('account avatar path persists and can be removed', () async {
    final account = await accounts.activeAccount();
    if (account == null) {
      fail("Active account missing");
    }
    const avatarPath = "/tmp/countcat-avatar-test.jpg";
    await accounts.update(account.copyWith(photoPath: avatarPath));
    var stored = await accounts.activeAccount();
    expect(stored?.photoPath, avatarPath);
    if (stored == null) {
      fail("Account disappeared");
    }
    await accounts.update(stored.copyWith(photoPath: null));
    stored = await accounts.activeAccount();
    expect(stored?.photoPath, isNull);
  });

  test('monthly snapshots remain isolated by submitted local calendar month', () async {
    final reports = MonthlyReportRepository(database);
    await transactions.insertTransaction(_transaction(orderId: 'AUG', gmvAmount: 10000, netIncomeAmount: 8000, hppUnitAmount: 2000, createdAt: DateTime(2026, 8, 31, 23, 0)));
    await transactions.insertTransaction(_transaction(orderId: 'SEP', gmvAmount: 20000, netIncomeAmount: 15000, hppUnitAmount: 3000, createdAt: DateTime(2026, 9, 1)));
    Future<void> submit(int month) async { final start = DateTime(2026, month); final end = DateTime(2026, month + 1); final totals = ReportTotals.fromTransactions(await transactions.listTransactions(periodStart: start, periodEnd: end)); await reports.save(MonthlyReport(year: 2026, month: month, periodStart: start, periodEnd: end, gmvTotal: totals.gmv, netIncomeTotal: totals.netIncome, hppTotal: totals.hpp, profitTotal: totals.profit, submittedAt: DateTime.now())); }
    await submit(8);
    final august = (await reports.listReports()).single;
    expect(august.gmvTotal, 10000);
    await submit(9);
    var snapshots = await reports.listReports();
    expect(snapshots.where((item) => item.month == 8).single.gmvTotal, 10000);
    expect(snapshots.where((item) => item.month == 9).single.gmvTotal, 20000);
    await transactions.insertTransaction(_transaction(orderId: 'SEP-2', gmvAmount: 5000, netIncomeAmount: 4000, hppUnitAmount: 1000, createdAt: DateTime(2026, 9, 30, 23, 59)));
    await submit(9);
    snapshots = await reports.listReports();
    expect(snapshots.where((item) => item.month == 8), hasLength(1));
    expect(snapshots.where((item) => item.month == 9), hasLength(1));
    expect(snapshots.where((item) => item.month == 9).single.gmvTotal, 25000);
  });
}

Future<HppMaster> _createHpp(
  HppRepository repository,
  AccountRepository accounts,
  int amount,
) async {
  final account = (await accounts.activeAccount())!;
  return repository.create(accountId: account.id!, name: 'HPP $amount', unitAmount: amount);
}

Transaction _transaction({
  String orderId = 'ORDER-1',
  String productCode = 'SKU-1',
  int? liveSessionId,
  int? hppId,
  int hppUnitAmount = 5000,
  int quantity = 1,
  int gmvAmount = 12000,
  int netIncomeAmount = 10000,
  PaymentStatus paymentStatus = PaymentStatus.pending,
  DateTime? paidAt,
  OrderStatus orderStatus = OrderStatus.newOrder,
  DateTime? createdAt,
  DateTime? transactionDate,
}) {
  final now = createdAt ?? DateTime.now();
  final local = now.toLocal();
  final txDate = transactionDate ?? DateTime(local.year, local.month, local.day);
  return Transaction(
    liveSessionId: liveSessionId,
    hppId: hppId,
    hppUnitAmount: hppUnitAmount,
    productCode: productCode,
    orderId: orderId,
    quantity: quantity,
    gmvAmount: gmvAmount,
    transactionDate: txDate,
    paymentStatus: paymentStatus,
    paidAt: paidAt,
    netIncomeAmount: netIncomeAmount,
    orderStatus: orderStatus,
    createdAt: now,
    updatedAt: now,
  );
}