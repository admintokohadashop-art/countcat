import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:tiktok_seller/core/backup/countcat_backup_service.dart';
import 'package:tiktok_seller/core/storage/countcat_data_paths.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/hpp_master.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/hpp_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/reports/report_totals.dart';
import 'package:tiktok_seller/features/returns/return_totals.dart';
import 'package:tiktok_seller/features/sales/transaction_validator.dart';

void main() {
  setUpAll(sqfliteFfiInit);

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

  group('returnShippingCompensation model', () {
    test('defaults to 0 for a new Transaction', () {
      final t = _tx(transactionDate: DateTime(2026, 8, 1));
      expect(t.returnShippingCompensation, 0);
    });

    test('round-trips through toMap/fromMap and persists to SQLite', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'O-RT',
        returnShippingCompensation: 30000,
      ));
      final stored = (await transactions.listTransactions()).single;
      expect(stored.returnShippingCompensation, 30000);
      expect(stored.toMap()['return_shipping_compensation'], 30000);
    });

    test('fromMap tolerates legacy rows without the column', () {
      final now = DateTime(2026).toUtc().toIso8601String();
      final row = <String, Object?>{
        'id': 1, 'account_id': 1, 'live_session_id': null, 'hpp_id': null,
        'hpp_unit_amount': 0, 'unit_price': 0,
        'transaction_date': '2026-08-01',
        'product_code': 'P', 'order_id': 'O', 'quantity': 1,
        'gmv_amount': 1000, 'payment_description': null,
        'payment_status': 'pending', 'paid_at': null,
        'net_income_amount': 900, 'order_status': 'new',
        'created_at': now, 'updated_at': now,
      };
      expect(Transaction.fromMap(row).returnShippingCompensation, 0);
    });

    test('copyWith overrides and preserves returnShippingCompensation', () {
      final t = _tx(
        transactionDate: DateTime(2026, 8, 1),
        returnShippingCompensation: 10000,
      );
      expect(t.copyWith(returnShippingCompensation: 30000).returnShippingCompensation, 30000);
      expect(t.copyWith(quantity: 5).returnShippingCompensation, 10000);
      expect(t.copyWith(returnShippingCompensation: 0).returnShippingCompensation, 0);
    });
  });

  group('ReturnTotals — aggregation rules', () {
    test('empty list yields zeroes', () {
      final r = ReturnTotals.fromTransactions(const []);
      expect(r.returnedCount, 0);
      expect(r.totalCompensation, 0);
      expect(r.activeIncome, 0);
      expect(r.activeHpp, 0);
      expect(r.incomeAfterReturn, 0);
      expect(r.profitAfterReturn, 0);
    });

    test('returnedCount and compensation count all RETURNED regardless of payment status', () {
      final items = [
        _tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A', orderStatus: OrderStatus.returned, returnShippingCompensation: 10000),
        _tx(transactionDate: DateTime(2026, 8, 2), orderId: 'B', orderStatus: OrderStatus.returned, paymentStatus: PaymentStatus.cancelled, returnShippingCompensation: 20000),
        _tx(transactionDate: DateTime(2026, 8, 3), orderId: 'C', orderStatus: OrderStatus.closed, returnShippingCompensation: 99999),
      ];
      final r = ReturnTotals.fromTransactions(items);
      expect(r.returnedCount, 2);
      expect(r.totalCompensation, 30000);
    });

    test('activeIncome and activeHpp follow 4C active rules', () {
      final items = [
        _tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A', netIncomeAmount: 50000, hppUnitAmount: 10000, quantity: 2),
        _tx(transactionDate: DateTime(2026, 8, 2), orderId: 'B', orderStatus: OrderStatus.returned, netIncomeAmount: 48000, hppUnitAmount: 20000, quantity: 1, returnShippingCompensation: 30000),
        _tx(transactionDate: DateTime(2026, 8, 3), orderId: 'C', orderStatus: OrderStatus.cancel, netIncomeAmount: 99999),
        _tx(transactionDate: DateTime(2026, 8, 4), orderId: 'D', paymentStatus: PaymentStatus.cancelled, netIncomeAmount: 99999),
      ];
      final r = ReturnTotals.fromTransactions(items);
      expect(r.activeIncome, 50000);
      expect(r.activeHpp, 20000);
      expect(r.totalCompensation, 30000);
      expect(r.incomeAfterReturn, 20000);
      expect(r.profitAfterReturn, 0);
    });

    test('compensation > activeIncome yields negative incomeAfterReturn (not clamped)', () {
      final items = [
        _tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A', netIncomeAmount: 50000, hppUnitAmount: 20000),
        _tx(transactionDate: DateTime(2026, 8, 2), orderId: 'B', orderStatus: OrderStatus.returned, returnShippingCompensation: 80000),
      ];
      final r = ReturnTotals.fromTransactions(items);
      expect(r.activeIncome, 50000);
      expect(r.incomeAfterReturn, -30000);
      expect(r.profitAfterReturn, -50000);
    });

    test('profitAfterReturn is negative when HPP exceeds incomeAfterReturn', () {
      final items = [
        _tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A', netIncomeAmount: 10000, hppUnitAmount: 40000, quantity: 1),
      ];
      final r = ReturnTotals.fromTransactions(items);
      expect(r.incomeAfterReturn, 10000);
      expect(r.profitAfterReturn, -30000);
    });

    test('does not double-subtract returned order income', () {
      final items = [
        _tx(transactionDate: DateTime(2026, 8, 1), orderId: 'ACTIVE', netIncomeAmount: 100000, hppUnitAmount: 0, quantity: 1),
        _tx(transactionDate: DateTime(2026, 8, 2), orderId: 'RET', orderStatus: OrderStatus.returned, netIncomeAmount: 48000, hppUnitAmount: 0, quantity: 1, returnShippingCompensation: 30000),
      ];
      final r = ReturnTotals.fromTransactions(items);
      expect(r.activeIncome, 100000);
      expect(r.incomeAfterReturn, 70000);
    });

    test('spec example: 500k active income, 80k compensation, 250k HPP -> 420k/170k', () {
      final items = [
        _tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A', netIncomeAmount: 500000, hppUnitAmount: 250000, quantity: 1),
        _tx(transactionDate: DateTime(2026, 8, 2), orderId: 'B', orderStatus: OrderStatus.returned, returnShippingCompensation: 80000),
      ];
      final r = ReturnTotals.fromTransactions(items);
      expect(r.incomeAfterReturn, 420000);
      expect(r.profitAfterReturn, 170000);
    });
  });

  group('HPP snapshot independence', () {
    test('activeHpp uses transaction snapshot, not the current HPP master', () async {
      final hppRepo = HppRepository(database);
      final account = (await accounts.activeAccount())!;
      final master = await hppRepo.create(
        accountId: account.id!,
        name: 'Kaos',
        unitAmount: 20000,
      );
      // Transaction snapshots 20 000 / unit at insert time.
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'SNAP',
        hppUnitAmount: 20000,
        quantity: 2,
        netIncomeAmount: 100000,
        orderStatus: OrderStatus.closed,
      ));
      // Now change the HPP master to 50 000 / unit.
      await hppRepo.update(HppMaster(
        id: master.id,
        accountId: master.accountId,
        name: master.name,
        unitAmount: 50000,
        isActive: master.isActive,
        createdAt: master.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ));
      // Confirming master really changed:
      final refreshed = await hppRepo.find(master.id);
      expect(refreshed!.unitAmount, 50000);
      // ReturnTotals must still use the snapshot (20 000 × 2 = 40 000).
      final r = ReturnTotals.fromTransactions(await transactions.listTransactions());
      expect(r.activeHpp, 40000);
    });
  });

  group('ReturnTotals — persistence via SQLite', () {
    test('edit compensation replaces previous value (no accumulation)', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'O-RT',
        orderStatus: OrderStatus.returned,
        returnShippingCompensation: 10000,
      ));
      final original = (await transactions.listTransactions()).single;
      await transactions.updateTransaction(original.copyWith(returnShippingCompensation: 25000));
      final updated = (await transactions.listTransactions()).single;
      expect(updated.returnShippingCompensation, 25000);
      expect(updated.returnShippingCompensation, isNot(35000));
    });

    test('RETURNED -> CLOSE keeps compensation, CLOSE -> RETURNED re-activates it', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'O-RT',
        orderStatus: OrderStatus.returned,
        returnShippingCompensation: 30000,
      ));
      var stored = (await transactions.listTransactions()).single;
      await transactions.updateTransaction(stored.copyWith(orderStatus: OrderStatus.closed));
      stored = (await transactions.listTransactions()).single;
      expect(stored.orderStatus, OrderStatus.closed);
      expect(stored.returnShippingCompensation, 30000);
      await transactions.updateTransaction(stored.copyWith(orderStatus: OrderStatus.returned));
      stored = (await transactions.listTransactions()).single;
      expect(stored.orderStatus, OrderStatus.returned);
      expect(stored.returnShippingCompensation, 30000);
    });

    test('RETURNED -> CANCEL keeps compensation, CANCEL -> RETURNED re-activates it', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'O-CAN',
        orderStatus: OrderStatus.returned,
        returnShippingCompensation: 15000,
      ));
      var stored = (await transactions.listTransactions()).single;
      await transactions.updateTransaction(stored.copyWith(orderStatus: OrderStatus.cancel));
      stored = (await transactions.listTransactions()).single;
      expect(stored.orderStatus, OrderStatus.cancel);
      expect(stored.returnShippingCompensation, 15000);
      await transactions.updateTransaction(stored.copyWith(orderStatus: OrderStatus.returned));
      stored = (await transactions.listTransactions()).single;
      expect(stored.orderStatus, OrderStatus.returned);
      expect(stored.returnShippingCompensation, 15000);
    });

    test('GMV is preserved when a CLOSED transaction becomes RETURNED', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'GMV-1',
        unitPrice: 50000,
        quantity: 2,
        gmvAmount: 100000,
        orderStatus: OrderStatus.closed,
      ));
      final before = (await transactions.listTransactions()).single;
      await transactions.updateTransaction(before.copyWith(orderStatus: OrderStatus.returned));
      final after = (await transactions.listTransactions()).single;
      expect(after.gmvAmount, 100000);
      expect(ReportTotals.fromTransactions([after]).gmv, 100000);
    });

    test('RETURNED + PaymentStatus.cancelled stays manageable for compensation', () async {
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'O-RT',
        orderStatus: OrderStatus.returned,
        paymentStatus: PaymentStatus.cancelled,
        returnShippingCompensation: 15000,
      ));
      final r = ReturnTotals.fromTransactions(await transactions.listTransactions());
      expect(r.returnedCount, 1);
      expect(r.totalCompensation, 15000);
      expect(r.activeIncome, 0);
      expect(r.activeHpp, 0);
    });

    test('period filtering by transactionDate year/month', () async {
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 8, 20), orderId: 'AUG', orderStatus: OrderStatus.returned, returnShippingCompensation: 5000));
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 9, 5), orderId: 'SEP', orderStatus: OrderStatus.returned, returnShippingCompensation: 7000));
      final aug = await transactions.listTransactions(periodStart: DateTime(2026, 8), periodEnd: DateTime(2026, 9));
      final sep = await transactions.listTransactions(periodStart: DateTime(2026, 9), periodEnd: DateTime(2026, 10));
      expect(ReturnTotals.fromTransactions(aug).totalCompensation, 5000);
      expect(ReturnTotals.fromTransactions(sep).totalCompensation, 7000);
    });

    test('edit transactionDate moves compensation to another month', () async {
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 8, 1), orderId: 'O-RT', orderStatus: OrderStatus.returned, returnShippingCompensation: 30000));
      final stored = (await transactions.listTransactions()).single;
      await transactions.updateTransaction(stored.copyWith(transactionDate: DateTime(2026, 9, 1)));
      final aug = await transactions.listTransactions(periodStart: DateTime(2026, 8), periodEnd: DateTime(2026, 9));
      final sep = await transactions.listTransactions(periodStart: DateTime(2026, 9), periodEnd: DateTime(2026, 10));
      expect(ReturnTotals.fromTransactions(aug).totalCompensation, 0);
      expect(ReturnTotals.fromTransactions(sep).totalCompensation, 30000);
    });

    test('different years are isolated', () async {
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2025, 9, 15), orderId: 'OLD', orderStatus: OrderStatus.returned, returnShippingCompensation: 5000));
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 9, 15), orderId: 'NEW', orderStatus: OrderStatus.returned, returnShippingCompensation: 7000));
      final s2025 = await transactions.listTransactions(periodStart: DateTime(2025, 9), periodEnd: DateTime(2025, 10));
      final s2026 = await transactions.listTransactions(periodStart: DateTime(2026, 9), periodEnd: DateTime(2026, 10));
      expect(ReturnTotals.fromTransactions(s2025).totalCompensation, 5000);
      expect(ReturnTotals.fromTransactions(s2026).totalCompensation, 7000);
    });
  });

  group('Report consistency', () {
    test('ReturnTotals.activeIncome and activeHpp equal ReportTotals netIncome/hpp', () async {
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A', netIncomeAmount: 100000, hppUnitAmount: 40000, quantity: 2, unitPrice: 60000, orderStatus: OrderStatus.closed));
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 8, 2), orderId: 'B', netIncomeAmount: 48000, hppUnitAmount: 20000, quantity: 1, unitPrice: 50000, orderStatus: OrderStatus.returned, returnShippingCompensation: 30000));
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 8, 3), orderId: 'C', netIncomeAmount: 70000, hppUnitAmount: 10000, quantity: 1, unitPrice: 80000, paymentStatus: PaymentStatus.cancelled));
      final all = await transactions.listTransactions(periodStart: DateTime(2026, 8), periodEnd: DateTime(2026, 9));
      final returns = ReturnTotals.fromTransactions(all);
      final reports = ReportTotals.fromTransactions(all);
      expect(returns.activeIncome, reports.netIncome);
      expect(returns.activeHpp, reports.hpp);
    });
  });

  group('account scoping', () {
    test('compensation on account A is not visible to account B', () async {
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A-1', orderStatus: OrderStatus.returned, returnShippingCompensation: 10000));
      await accounts.create(name: 'Other');
      expect((await transactions.listTransactions()), isEmpty);
    });

    test('searching account B does not return account A orders', () async {
      await transactions.insertTransaction(_tx(transactionDate: DateTime(2026, 8, 1), orderId: 'A-ONLY', orderStatus: OrderStatus.returned, returnShippingCompensation: 10000));
      await accounts.create(name: 'Other');
      expect((await transactions.listTransactions(search: 'A-ONLY')), isEmpty);
    });
  });

  group('validator', () {
    test('returnShippingCompensation accepts >= 0 and rejects null/negative', () {
      expect(TransactionValidator.returnShippingCompensation(null), isNotNull);
      expect(TransactionValidator.returnShippingCompensation(-1), isNotNull);
      expect(TransactionValidator.returnShippingCompensation(0), isNull);
      expect(TransactionValidator.returnShippingCompensation(30000), isNull);
    });
  });

  group('backup & restore regression', () {
    late Directory temp;
    late CountCatDataPaths paths;
    late AppDatabase db;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('countcat-m5-backup-');
      paths = CountCatDataPaths(root: temp);
      db = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final acc = AccountRepository(db);
      await acc.create(name: 'Main');
    });
    tearDown(() async {
      await db.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('.countcat round-trip preserves returnShippingCompensation', () async {
      final tx = TransactionRepository(db);
      await tx.insertTransaction(_tx(
        transactionDate: DateTime(2026, 8, 1),
        orderId: 'O-BK',
        orderStatus: OrderStatus.returned,
        returnShippingCompensation: 30000,
      ));
      final backup = File('${temp.path}${Platform.pathSeparator}roundtrip.countcat');
      await CountCatBackupService(db, paths: paths).createBackup(destination: backup);
      expect(await backup.exists(), isTrue);

      // Mutate to prove restore actually rolls back.
      final stored = (await tx.listTransactions()).single;
      await tx.updateTransaction(stored.copyWith(returnShippingCompensation: 0));
      expect((await tx.listTransactions()).single.returnShippingCompensation, 0);

      await CountCatBackupService(db, paths: paths).restore(backup);
      final restored = (await tx.listTransactions()).single;
      expect(restored.returnShippingCompensation, 30000);
    });
  });
}

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
}) {
  final now = DateTime(2026);
  return Transaction(
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