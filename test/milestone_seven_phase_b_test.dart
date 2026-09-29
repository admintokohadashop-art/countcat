import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:tiktok_seller/core/profile/avatar_storage.dart';
import 'package:tiktok_seller/core/storage/countcat_data_paths.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';

Order _order({
  int accountId = 1,
  String orderId = 'ORD-1',
  int? liveSessionId,
  DateTime? transactionDate,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  OrderStatus orderStatus = OrderStatus.closed,
  int returnShippingCompensation = 0,
}) {
  final now = DateTime(2026, 9, 1, 10);
  return Order(
    accountId: accountId,
    orderId: orderId,
    liveSessionId: liveSessionId,
    transactionDate: transactionDate ?? DateTime(2026, 9, 15),
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    paidAt: paymentStatus == PaymentStatus.paid ? now : null,
    returnShippingCompensation: returnShippingCompensation,
    createdAt: now,
    updatedAt: now,
  );
}

Transaction _item({
  String productCode = 'P',
  int quantity = 1,
  int unitPrice = 1000,
  int hppUnitAmount = 0,
  int netIncomeAmount = 1000,
  DateTime? transactionDate,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  OrderStatus orderStatus = OrderStatus.closed,
  String orderId = 'ORD-1',
}) {
  final now = DateTime(2026, 9, 1, 10);
  final txDate = transactionDate ?? DateTime(2026, 9, 15);
  return Transaction(
    transactionDate: txDate,
    productCode: productCode,
    orderId: orderId,
    quantity: quantity,
    unitPrice: unitPrice,
    gmvAmount: unitPrice * quantity,
    hppUnitAmount: hppUnitAmount,
    netIncomeAmount: netIncomeAmount,
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  late CountCatDataPaths paths;
  late AppDatabase database;
  late AccountRepository accounts;
  late OrderRepository orders;
  late TransactionRepository transactions;
  late LiveSessionRepository sessions;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('m7b-');
    paths = CountCatDataPaths(root: temp);
    database = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
    accounts = AccountRepository(database, avatars: AvatarStorage(paths: paths));
    orders = OrderRepository(database);
    transactions = TransactionRepository(database);
    sessions = LiveSessionRepository(database);
    await accounts.create(name: 'Main');
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('OrderRepository', () {
    test('create + get + list', () async {
      final id = await orders.create(_order(orderId: 'ORD-1'));
      final fetched = await orders.get(id);
      expect(fetched?.orderId, 'ORD-1');
      final list = await orders.list();
      expect(list, hasLength(1));
    });

    test('update changes order-level fields', () async {
      final id = await orders.create(_order(orderId: 'ORD-1'));
      final fetched = (await orders.get(id))!;
      await orders.update(fetched.copyWith(orderStatus: OrderStatus.returned, returnShippingCompensation: 30000));
      final updated = (await orders.get(id))!;
      expect(updated.orderStatus, OrderStatus.returned);
      expect(updated.returnShippingCompensation, 30000);
    });

    test('delete removes the order', () async {
      final id = await orders.create(_order(orderId: 'ORD-1'));
      await orders.delete(id);
      expect(await orders.get(id), isNull);
    });

    test('duplicate order_id rejected in same account', () async {
      await orders.create(_order(orderId: 'DUP'));
      await expectLater(orders.create(_order(orderId: 'DUP')), throwsA(isA<DuplicateOrderIdException>()));
    });

    test('same order_id allowed in different accounts', () async {
      await orders.create(_order(orderId: 'SHARED'));
      await accounts.create(name: 'Other');
      final id = await orders.create(_order(orderId: 'SHARED'));
      final fetched = await orders.get(id);
      expect(fetched?.orderId, 'SHARED');
    });

    test('account isolation', () async {
      final id = await orders.create(_order(orderId: 'A-1'));
      await accounts.create(name: 'Other');
      expect(await orders.get(id), isNull);
      expect(await orders.list(), isEmpty);
    });

    test('createWithItems is atomic and links items to order', () async {
      final orderPk = await orders.createWithItems(
        _order(orderId: 'ORD-MULTI'),
        [_item(productCode: 'A'), _item(productCode: 'B'), _item(productCode: 'C')],
      );
      final rows = await (await database.database).query('transactions', where: 'order_fk = ?', whereArgs: [orderPk], orderBy: 'item_index ASC');
      expect(rows, hasLength(3));
      expect(rows.map((r) => r['product_code']), ['A', 'B', 'C']);
      expect(rows.map((r) => r['item_index']), [0, 1, 2]);
    });
  });

  group('TransactionRepository — legacy compatibility', () {
    test('insertTransaction creates order + item', () async {
      final id = await transactions.insertTransaction(_item(orderId: 'LEG'));
      expect(id, greaterThan(0));
      final db = await database.database;
      final orderRows = await db.query('orders', where: 'order_id = ?', whereArgs: ['LEG']);
      expect(orderRows, hasLength(1));
      final itemRows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(itemRows.single['order_fk'], orderRows.single['id']);
    });

    test('legacy listTransactions still works', () async {
      await transactions.insertTransaction(_item(orderId: 'LEG1'));
      await transactions.insertTransaction(_item(orderId: 'LEG2'));
      final all = await transactions.listTransactions();
      expect(all, hasLength(2));
    });

    test('deleteTransaction removes the order when last item is removed', () async {
      final id = await transactions.insertTransaction(_item(orderId: 'ONLY'));
      await transactions.deleteTransaction(id);
      final db = await database.database;
      expect(await db.query('orders', where: 'order_id = ?', whereArgs: ['ONLY']), isEmpty);
    });
  });

  group('TransactionRepository — M7 joined reads', () {
    test('multi-item order appears as one group', () async {
      await orders.createWithItems(
        _order(orderId: 'ORD-G'),
        [_item(productCode: 'A'), _item(productCode: 'B'), _item(productCode: 'C')],
      );
      final rows = await transactions.listItemsJoined();
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.order.orderId == 'ORD-G'), isTrue);
    });

    test('search by order id returns all items of that order', () async {
      await orders.createWithItems(
        _order(orderId: 'ORD-X'),
        [_item(productCode: 'A'), _item(productCode: 'B')],
      );
      await orders.createWithItems(
        _order(orderId: 'ORD-Y'),
        [_item(productCode: 'C')],
      );
      final matched = await transactions.listItemsJoined(search: 'ORD-X');
      expect(matched, hasLength(2));
      expect(matched.every((r) => r.order.orderId == 'ORD-X'), isTrue);
    });

    test('search by product code returns only matching items', () async {
      await orders.createWithItems(
        _order(orderId: 'ORD-1'),
        [_item(productCode: 'MATCH'), _item(productCode: 'OTHER')],
      );
      final matched = await transactions.listItemsJoined(search: 'MATCH');
      expect(matched, hasLength(1));
      expect(matched.single.item.productCode, 'MATCH');
      expect(matched.single.order.orderId, 'ORD-1');
    });

    test('period filter uses order.transaction_date', () async {
      await orders.createWithItems(
        _order(orderId: 'AUG', transactionDate: DateTime(2026, 8, 20)),
        [_item()],
      );
      await orders.createWithItems(
        _order(orderId: 'SEP', transactionDate: DateTime(2026, 9, 5)),
        [_item()],
      );
      final aug = await transactions.listItemsJoined(
        periodStart: DateTime(2026, 8),
        periodEnd: DateTime(2026, 9),
      );
      expect(aug, hasLength(1));
      expect(aug.single.order.orderId, 'AUG');
    });

    test('payment status filter uses order.payment_status', () async {
      await orders.createWithItems(
        _order(orderId: 'P', paymentStatus: PaymentStatus.pending),
        [_item(paymentStatus: PaymentStatus.pending)],
      );
      await orders.createWithItems(
        _order(orderId: 'C', paymentStatus: PaymentStatus.cancelled),
        [_item(paymentStatus: PaymentStatus.cancelled)],
      );
      final pending = await transactions.listItemsJoined(paymentStatus: PaymentStatus.pending);
      expect(pending, hasLength(1));
      expect(pending.single.order.orderId, 'P');
    });

    test('order status filter uses order.order_status', () async {
      await orders.createWithItems(
        _order(orderId: 'RET', orderStatus: OrderStatus.returned),
        [_item(orderStatus: OrderStatus.returned)],
      );
      await orders.createWithItems(
        _order(orderId: 'OK', orderStatus: OrderStatus.closed),
        [_item()],
      );
      final returned = await transactions.listItemsJoined(orderStatus: OrderStatus.returned);
      expect(returned, hasLength(1));
      expect(returned.single.order.orderId, 'RET');
    });

    test('combined filters', () async {
      final session = await sessions.createSession(name: 'S1');
      await orders.createWithItems(
        _order(orderId: 'A', liveSessionId: session.id, transactionDate: DateTime(2026, 9, 15)),
        [_item()],
      );
      await orders.createWithItems(
        _order(orderId: 'B', transactionDate: DateTime(2026, 9, 15)),
        [_item()],
      );
      final result = await transactions.listItemsJoined(
        liveSessionId: session.id,
        periodStart: DateTime(2026, 9),
        periodEnd: DateTime(2026, 10),
      );
      expect(result, hasLength(1));
      expect(result.single.order.orderId, 'A');
    });

    test('updateItem changes only that item', () async {
      final orderPk = await orders.createWithItems(
        _order(orderId: 'M'),
        [_item(productCode: 'A', quantity: 1), _item(productCode: 'B', quantity: 1)],
      );
      final itemRows = await (await database.database).query('transactions', where: 'order_fk = ?', whereArgs: [orderPk], orderBy: 'item_index ASC');
      final itemA = Transaction.fromMap(itemRows[0]);
      await transactions.updateItem(itemA.copyWith(quantity: 5));
      final refreshed = await (await database.database).query('transactions', where: 'order_fk = ?', whereArgs: [orderPk], orderBy: 'item_index ASC');
      expect(refreshed[0]['quantity'], 5);
      expect(refreshed[1]['quantity'], 1);
    });

    test('deleteItem leaves other items intact', () async {
      final orderPk = await orders.createWithItems(
        _order(orderId: 'M'),
        [_item(productCode: 'A'), _item(productCode: 'B')],
      );
      final rows = await (await database.database).query('transactions', where: 'order_fk = ?', whereArgs: [orderPk], orderBy: 'item_index ASC');
      await transactions.deleteItem(rows[0]['id'] as int);
      final remaining = await (await database.database).query('transactions', where: 'order_fk = ?', whereArgs: [orderPk]);
      expect(remaining, hasLength(1));
      expect(remaining.single['product_code'], 'B');
    });

    test('deleteItem of last item removes the order', () async {
      final orderPk = await orders.createWithItems(_order(orderId: 'LAST'), [_item()]);
      final itemId = (await (await database.database).query('transactions', where: 'order_fk = ?', whereArgs: [orderPk])).single['id'] as int;
      await transactions.deleteItem(itemId);
      expect(await (await database.database).query('orders', where: 'id = ?', whereArgs: [orderPk]), isEmpty);
    });

    test('cross-account mutation is rejected', () async {
      final orderPk = await orders.createWithItems(_order(orderId: 'A'), [_item()]);
      final itemId = (await (await database.database).query('transactions', where: 'order_fk = ?', whereArgs: [orderPk])).single['id'] as int;
      await accounts.create(name: 'Other');
      await expectLater(transactions.deleteItem(itemId), completes);
      // After switching accounts, the item still exists because the join
      // filtered by the new active account.
      await accounts.setActiveAccountId(1);
      final stillThere = await (await database.database).query('transactions', where: 'id = ?', whereArgs: [itemId]);
      expect(stillThere, hasLength(1));
    });
  });

  group('LiveSessionRepository — M7-C', () {
    test('updateSession changes name and startedAt; id preserved', () async {
      final s = await sessions.createSession(name: 'Old', startedAt: DateTime(2026, 9, 1, 19));
      await sessions.updateSession(id: s.id!, name: 'New', startedAt: DateTime(2026, 9, 2, 20));
      final refreshed = (await sessions.listSessions()).firstWhere((x) => x.id == s.id);
      expect(refreshed.name, 'New');
      expect(refreshed.startedAt!.toUtc(), DateTime(2026, 9, 2, 20).toUtc());
    });

    test('hasTransactions detects usage through orders', () async {
      final s = await sessions.createSession(name: 'S');
      expect(await sessions.hasTransactions(s.id!), isFalse);
      await orders.createWithItems(_order(orderId: 'O', liveSessionId: s.id), [_item()]);
      expect(await sessions.hasTransactions(s.id!), isTrue);
    });

    test('deleteSession removes an unused session', () async {
      final s = await sessions.createSession(name: 'S');
      await sessions.deleteSession(s.id!);
      expect((await sessions.listSessions()).where((x) => x.id == s.id), isEmpty);
    });

    test('deleteSession refuses a used session', () async {
      final s = await sessions.createSession(name: 'S');
      await orders.createWithItems(_order(orderId: 'O', liveSessionId: s.id), [_item()]);
      await expectLater(sessions.deleteSession(s.id!), throwsA(isA<SessionInUseException>()));
      expect((await sessions.listSessions()).where((x) => x.id == s.id), hasLength(1));
    });

    test('linked orders remain intact when delete is refused', () async {
      final s = await sessions.createSession(name: 'S');
      final orderPk = await orders.createWithItems(_order(orderId: 'O', liveSessionId: s.id), [_item()]);
      try { await sessions.deleteSession(s.id!); } catch (_) {}
      final order = await orders.get(orderPk);
      expect(order, isNotNull);
      expect(order!.liveSessionId, s.id);
    });

    test('selected session fallback when deleted', () async {
      final s1 = await sessions.createSession(name: 'S1', startedAt: DateTime(2026, 9, 1));
      final s2 = await sessions.createSession(name: 'S2', startedAt: DateTime(2026, 9, 2));
      await sessions.setSelectedSessionId(s1.id);
      await sessions.deleteSession(s1.id!);
      expect(await sessions.getSelectedSessionId(), s2.id);
    });

    test('selected session cleared when last session deleted', () async {
      final s = await sessions.createSession(name: 'S');
      await sessions.deleteSession(s.id!);
      expect(await sessions.getSelectedSessionId(), isNull);
    });

    test('account isolation for delete', () async {
      final s = await sessions.createSession(name: 'A');
      await accounts.create(name: 'Other');
      await expectLater(sessions.deleteSession(s.id!), throwsA(isA<StateError>()));
    });
  });

  group('AccountRepository — M7 cascade', () {
    test('delete removes orders and their items', () async {
      await orders.createWithItems(_order(orderId: 'O'), [_item(), _item()]);
      final a = (await accounts.activeAccount())!;
      await accounts.delete(a);
      final db = await database.database;
      expect(await db.query('orders'), isEmpty);
      expect(await db.query('transactions'), isEmpty);
    });

    test('other account data is untouched', () async {
      final a1 = (await accounts.activeAccount())!;
      await orders.createWithItems(_order(orderId: 'A-ORD'), [_item()]);
      await accounts.create(name: 'B');
      await orders.createWithItems(_order(orderId: 'B-ORD'), [_item()]);
      await accounts.delete(a1);
      final db = await database.database;
      final remaining = await db.query('orders');
      expect(remaining, hasLength(1));
      expect(remaining.single['order_id'], 'B-ORD');
    });
  });
}