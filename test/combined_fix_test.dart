import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:tiktok_seller/core/profile/avatar_storage.dart';
import 'package:tiktok_seller/core/storage/countcat_data_paths.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/models/hpp_master.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/monthly_report.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/hpp_repository.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/monthly_report_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/sales/new_sale_page.dart';
import 'package:tiktok_seller/features/settings/settings_page.dart';

Transaction _tx({
  int? id,
  int? accountId,
  DateTime? transactionDate,
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
  DateTime? paidAt,
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime(2026, 8, 1, 10);
  return Transaction(
    id: id,
    accountId: accountId,
    transactionDate: transactionDate ?? DateTime(now.year, now.month, now.day),
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
    paidAt: paidAt ?? (paymentStatus == PaymentStatus.paid ? now : null),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('Paid date timezone round-trip', () {
    test('toMap writes UTC, fromMap reads back local', () {
      final original = DateTime(2026, 9, 15, 10, 30);
      final t = _tx(
        transactionDate: DateTime(2026, 9, 15),
        paymentStatus: PaymentStatus.paid,
        paidAt: original,
      );
      final m = t.toMap();
      final raw = m['paid_at'] as String;
      expect(raw.endsWith('Z'), isTrue, reason: 'paid_at must be stored as UTC ISO-8601');

      final restored = Transaction.fromMap(m);
      expect(restored.paidAt, isNotNull);
      expect(restored.paidAt!.isUtc, isFalse, reason: 'paid_at must be local after read');
      expect(restored.paidAt!.toUtc(), original.toUtc());
      expect(restored.paidAt!.year, original.year);
      expect(restored.paidAt!.month, original.month);
      expect(restored.paidAt!.day, original.day);
    });

    test('SQLite round-trip preserves the local calendar day', () async {
      final database = AppDatabase.inMemoryForTesting();
      addTearDown(database.close);
      final accounts = AccountRepository(database);
      final transactions = TransactionRepository(database);
      await accounts.create(name: 'Main');

      final original = DateTime(2026, 9, 15, 10, 30);
      await transactions.insertTransaction(_tx(
        transactionDate: DateTime(2026, 9, 15),
        orderId: 'PAID-1',
        paymentStatus: PaymentStatus.paid,
        paidAt: original,
      ));

      final stored = (await transactions.listTransactions()).single;
      expect(stored.paidAt, isNotNull);
      expect(stored.paidAt!.toUtc(), original.toUtc());
      expect(stored.paidAt!.year, 2026);
      expect(stored.paidAt!.month, 9);
      expect(stored.paidAt!.day, 15);

      final row = (await (await database.database).query('transactions')).single;
      expect((row['paid_at'] as String).endsWith('Z'), isTrue);
    });
  });

  group('New Sale vertical scrollbar', () {
    testWidgets('renders a Scrollbar with thumbVisibility and interactive set', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NewSalePage(
            accountRepository: _NoopAccountRepo(),
            liveSessionRepository: _NoopLiveSessionRepo(),
            hppRepository: _NoopHppRepo(),
            transactionRepository: _NoopTransactionRepo(),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.interactive, isTrue);
      expect(scrollbar.controller, isNotNull);
      final listView = tester.widget<ListView>(find.byType(ListView).first);
      expect(listView.controller, same(scrollbar.controller));
    });
  });

  group('Delete account', () {
    late Directory temp;
    late CountCatDataPaths paths;
    late AppDatabase database;
    late AccountRepository accounts;
    late TransactionRepository transactions;
    late LiveSessionRepository sessions;
    late HppRepository hpp;
    late MonthlyReportRepository reports;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('combined-fix-delete-');
      paths = CountCatDataPaths(root: temp);
      database = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      accounts = AccountRepository(database, avatars: AvatarStorage(paths: paths));
      transactions = TransactionRepository(database);
      sessions = LiveSessionRepository(database);
      hpp = HppRepository(database);
      reports = MonthlyReportRepository(database);
    });

    tearDown(() async {
      await database.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('removes the account and all data owned by it, leaves other account intact', () async {
      final a = await accounts.create(name: 'A');
      await transactions.insertTransaction(_tx(accountId: a.id, orderId: 'A-1'));
      await hpp.create(accountId: a.id!, name: 'H-A', unitAmount: 100);
      await sessions.createSession(name: 'S-A');
      await reports.save(MonthlyReport(
        year: 2026,
        month: 8,
        periodStart: DateTime(2026, 8),
        periodEnd: DateTime(2026, 9),
        gmvTotal: 1,
        netIncomeTotal: 1,
        hppTotal: 1,
        profitTotal: 1,
        submittedAt: DateTime.now(),
      ));

      final b = await accounts.create(name: 'B');
      await transactions.insertTransaction(_tx(accountId: b.id, orderId: 'B-1'));
      await hpp.create(accountId: b.id!, name: 'H-B', unitAmount: 200);
      await sessions.createSession(name: 'S-B');
      await reports.save(MonthlyReport(
        year: 2026,
        month: 9,
        periodStart: DateTime(2026, 9),
        periodEnd: DateTime(2026, 10),
        gmvTotal: 2,
        netIncomeTotal: 2,
        hppTotal: 2,
        profitTotal: 2,
        submittedAt: DateTime.now(),
      ));

      await accounts.delete(a);

      final db = await database.database;
      expect(await db.query('transactions', where: 'account_id = ?', whereArgs: [a.id]), isEmpty);
      expect(await db.query('monthly_reports', where: 'account_id = ?', whereArgs: [a.id]), isEmpty);
      expect(await db.query('live_sessions', where: 'account_id = ?', whereArgs: [a.id]), isEmpty);
      expect(await db.query('hpp_master', where: 'account_id = ?', whereArgs: [a.id]), isEmpty);
      expect(await db.query('account_settings', where: 'account_id = ?', whereArgs: [a.id]), isEmpty);
      expect(await db.query('accounts', where: 'id = ?', whereArgs: [a.id]), isEmpty);

      expect(await db.query('transactions', where: 'account_id = ?', whereArgs: [b.id]), hasLength(1));
      expect(await db.query('monthly_reports', where: 'account_id = ?', whereArgs: [b.id]), hasLength(1));
      expect(await db.query('live_sessions', where: 'account_id = ?', whereArgs: [b.id]), hasLength(1));
      expect(await db.query('hpp_master', where: 'account_id = ?', whereArgs: [b.id]), hasLength(1));

      final active = await accounts.activeAccount();
      expect(active?.id, b.id);
    });

    test('database file is not deleted after account deletion', () async {
      final a = await accounts.create(name: 'Solo');
      final dbFile = await paths.databaseFile;
      expect(await dbFile.exists(), isTrue);
      await accounts.delete(a);
      expect(await dbFile.exists(), isTrue);
    });

    test('deleting active account promotes another account to active', () async {
      final a = await accounts.create(name: 'A');
      final b = await accounts.create(name: 'B');
      await accounts.delete(b);
      final active = await accounts.activeAccount();
      expect(active?.id, a.id);
    });

    test('deleting last account clears active_account_id', () async {
      final a = await accounts.create(name: 'Only');
      await accounts.delete(a);
      final db = await database.database;
      final active = await accounts.activeAccount();
      expect(active, isNull);
      expect(await db.query('settings', where: 'key = ?', whereArgs: ['active_account_id']), isEmpty);
    });

    test('deletes avatar owned by CountCat', () async {
      final avatarDir = await paths.avatarsDirectory;
      final file = File('${avatarDir.path}${Platform.pathSeparator}avatar-test.jpg');
      await file.writeAsBytes(const [1, 2, 3]);

      final a = await accounts.create(name: 'A', photoPath: file.path);
      await accounts.delete(a);
      expect(await file.exists(), isFalse);
    });

    test('does not delete unrelated files', () async {
      final outside = File('${temp.path}${Platform.pathSeparator}unrelated.txt');
      await outside.writeAsString('keep me');
      final a = await accounts.create(name: 'A', photoPath: outside.path);
      await accounts.delete(a);
      expect(await outside.exists(), isTrue);
    });

    test('account without any transactions can be deleted', () async {
      final a = await accounts.create(name: 'Empty');
      await accounts.delete(a);
      final db = await database.database;
      expect(await db.query('accounts'), isEmpty);
    });

    test('clears selected_live_session_id when it points to a session owned by the deleted account', () async {
      final a = await accounts.create(name: 'A');
      final aSession = await sessions.createSession(name: 'A1');
      expect(aSession.id, isNotNull);

      final b = await accounts.create(name: 'B');
      await sessions.createSession(name: 'B1');

      // Point the global selection at A's session explicitly.
      await sessions.setSelectedSessionId(aSession.id);
      expect(await sessions.getSelectedSessionId(), aSession.id);

      await accounts.delete(a);

      final db = await database.database;
      expect(
        await db.query('settings', where: 'key = ?', whereArgs: ['selected_live_session_id']),
        isEmpty,
        reason: 'stale pointer to a deleted session must be cleared',
      );
      expect(
        await db.query('live_sessions', where: 'account_id = ?', whereArgs: [b.id]),
        hasLength(1),
        reason: "other account's live session must remain",
      );
    });

    test('keeps selected_live_session_id when it points to another account\'s session', () async {
      final a = await accounts.create(name: 'A');
      await sessions.createSession(name: 'A1');

      final b = await accounts.create(name: 'B');
      final bSession = await sessions.createSession(name: 'B1');
      expect(await sessions.getSelectedSessionId(), bSession.id);

      await accounts.delete(a);

      expect(await sessions.getSelectedSessionId(), bSession.id);
      final db = await database.database;
      expect(
        await db.query('live_sessions', where: 'account_id = ?', whereArgs: [b.id]),
        hasLength(1),
      );
    });
  });

  group('Delete account widget test', () {
    late Directory temp;
    late CountCatDataPaths paths;
    late AppDatabase database;
    late AccountRepository accounts;
    late HppRepository hpp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('combined-fix-widget-');
      paths = CountCatDataPaths(root: temp);
      database = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      accounts = AccountRepository(database, avatars: AvatarStorage(paths: paths));
      hpp = HppRepository(database);
      await accounts.create(name: 'Alpha');
    });

    tearDown(() async {
      await database.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<void> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsPage(repository: accounts, hppRepository: hpp)),
      ));
      final deleteFinder = find.text('DELETE ACCOUNT');
      for (var attempt = 0; attempt < 200 && deleteFinder.evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(
        deleteFinder,
        findsOneWidget,
        reason: 'SettingsPage did not finish its async initial load in time',
      );
    }

    testWidgets('BATAL does not delete the account', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('DELETE ACCOUNT'));
      await tester.pumpAndSettle();
      expect(find.text('HAPUS ACCOUNT'), findsOneWidget);
      await tester.tap(find.text('BATAL'));
      await tester.pumpAndSettle();

      final remaining =
          await tester.runAsync(() => accounts.listAccounts()) ?? const <Account>[];
      expect(remaining, hasLength(1));
      expect(remaining.single.name, 'Alpha');
    });

    testWidgets('HAPUS ACCOUNT deletes the account', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('DELETE ACCOUNT'));
      await tester.pumpAndSettle();
      expect(find.text('HAPUS ACCOUNT'), findsOneWidget);
      await tester.tap(find.text('HAPUS ACCOUNT'));
      await tester.pump();

      List<Account> remaining = const <Account>[];
      for (var attempt = 0; attempt < 200; attempt++) {
        remaining =
            await tester.runAsync(() => accounts.listAccounts()) ?? const <Account>[];
        if (remaining.isEmpty) break;
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(remaining, isEmpty);
    });
  });
}

class _NoopAccountRepo implements AccountRepository {
  @override
  Future<List<Account>> listAccounts() async => const [];
  @override
  Future<Account?> activeAccount() async {
    final now = DateTime(2026);
    return Account(id: 1, name: 'A', description: '', createdAt: now, updatedAt: now);
  }
  @override
  Future<void> setActiveAccountId(int? id) async {}
  @override
  Future<Account> create({required String name, String description = '', String? photoPath}) async => throw UnimplementedError();
  @override
  Future<void> update(Account account) async {}
  @override
  Future<void> delete(Account account) async {}
}

class _NoopLiveSessionRepo implements LiveSessionRepository {
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

class _NoopHppRepo implements HppRepository {
  @override
  Future<List<HppMaster>> list(int accountId, {bool activeOnly = true}) async => const [];
  @override
  Future<HppMaster?> find(int? id) async => null;
  @override
  Future<HppMaster> create({required int accountId, required String name, required int unitAmount}) async => throw UnimplementedError();
  @override
  Future<void> update(HppMaster h) async {}
  @override
  Future<void> deactivate(int id, int accountId) async {}
}

class _NoopTransactionRepo implements TransactionRepository {
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
  }) async => const [];
  @override
  Future<void> deleteTransaction(int id) async {}
  @override
  Future<void> updateTransaction(Transaction transaction) async {}
}