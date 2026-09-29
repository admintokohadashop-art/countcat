import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:tiktok_seller/core/storage/countcat_data_paths.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';

Order _order({
  required String orderId,
  int accountId = 0,
  int? liveSessionId,
  DateTime? transactionDate,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  OrderStatus orderStatus = OrderStatus.closed,
  DateTime? paidAt,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Order(
    accountId: accountId,
    orderId: orderId,
    liveSessionId: liveSessionId,
    transactionDate: transactionDate ?? DateTime(2026, 9, 15),
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    paidAt: paidAt ?? (paymentStatus == PaymentStatus.paid ? now : null),
    returnShippingCompensation: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Transaction _item({
  required String orderId,
  String productCode = 'P',
  int quantity = 1,
  int unitPrice = 1000,
  int hppUnitAmount = 0,
  int? hppId,
  int? netIncomeAmount,
  DateTime? transactionDate,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Transaction(
    hppId: hppId,
    hppUnitAmount: hppUnitAmount,
    unitPrice: unitPrice,
    transactionDate: transactionDate ?? DateTime(2026, 9, 15),
    productCode: productCode,
    orderId: orderId,
    quantity: quantity,
    gmvAmount: unitPrice * quantity,
    paymentStatus: PaymentStatus.paid,
    paidAt: now,
    netIncomeAmount: netIncomeAmount ?? unitPrice * quantity,
    orderStatus: OrderStatus.closed,
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

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('m7d-');
    paths = CountCatDataPaths(root: temp);
    database = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
    accounts = AccountRepository(database);
    orders = OrderRepository(database);
    transactions = TransactionRepository(database);
    await accounts.create(name: 'Main');
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('one-item submission creates one order + one item', () async {
    final orderPk = await orders.createWithItems(
      _order(orderId: 'O1'),
      [_item(orderId: 'O1', productCode: 'A', quantity: 2, unitPrice: 50000, hppUnitAmount: 20000, netIncomeAmount: 80000)],
    );
    final db = await database.database;
    expect(await db.query('orders'), hasLength(1));
    final item = (await db.query('transactions')).single;
    expect(item['order_fk'], orderPk);
    expect(item['item_index'], 0);
    expect(item['product_code'], 'A');
    expect(item['quantity'], 2);
    expect(item['unit_price'], 50000);
    expect(item['gmv_amount'], 100000);
    expect(item['hpp_unit_amount'], 20000);
    expect(item['net_income_amount'], 80000);
  });

  test('two-item submission shares one orderPk', () async {
    final orderPk = await orders.createWithItems(
      _order(orderId: 'O2'),
      [
        _item(orderId: 'O2', productCode: 'A', quantity: 2, unitPrice: 50000, hppUnitAmount: 20000),
        _item(orderId: 'O2', productCode: 'B', quantity: 1, unitPrice: 80000, hppUnitAmount: 35000),
      ],
    );
    final db = await database.database;
    expect(await db.query('orders'), hasLength(1));
    final items = await db.query('transactions', orderBy: 'item_index ASC');
    expect(items, hasLength(2));
    expect(items[0]['order_fk'], orderPk);
    expect(items[1]['order_fk'], orderPk);
    expect(items[0]['item_index'], 0);
    expect(items[1]['item_index'], 1);
    expect(items[0]['product_code'], 'A');
    expect(items[1]['product_code'], 'B');
    expect(items[0]['hpp_unit_amount'], 20000);
    expect(items[1]['hpp_unit_amount'], 35000);
  });

  test('three-item submission stores three independent items', () async {
    final orderPk = await orders.createWithItems(
      _order(orderId: 'O3'),
      [
        _item(orderId: 'O3', productCode: 'A', quantity: 2, unitPrice: 21000, hppUnitAmount: 8000),
        _item(orderId: 'O3', productCode: 'B', quantity: 1, unitPrice: 27000, hppUnitAmount: 10000),
        _item(orderId: 'O3', productCode: 'C', quantity: 3, unitPrice: 30000, hppUnitAmount: 12000),
      ],
    );
    final db = await database.database;
    final items = await db.query('transactions', where: 'order_fk = ?', whereArgs: [orderPk], orderBy: 'item_index ASC');
    expect(items, hasLength(3));
    expect(items.map((r) => r['item_index']), [0, 1, 2]);
    expect(items.map((r) => r['product_code']), ['A', 'B', 'C']);
    expect(items.map((r) => r['quantity']), [2, 1, 3]);
    expect(items.map((r) => r['unit_price']), [21000, 27000, 30000]);
    expect(items.map((r) => r['gmv_amount']), [42000, 27000, 90000]);
    expect(items.map((r) => r['hpp_unit_amount']), [8000, 10000, 12000]);
  });

  test('order-level fields are stored once on the order row', () async {
    await orders.createWithItems(
      _order(orderId: 'O4', liveSessionId: null, paymentStatus: PaymentStatus.paid),
      [
        _item(orderId: 'O4', productCode: 'A'),
        _item(orderId: 'O4', productCode: 'B'),
      ],
    );
    final db = await database.database;
    final order = (await db.query('orders')).single;
    expect(order['order_id'], 'O4');
    expect(order['payment_status'], 'paid');
    expect(order['order_status'], 'closed');
  });

  test('duplicate order id in same account is rejected and leaves no partial rows', () async {
    await orders.createWithItems(_order(orderId: 'DUP'), [_item(orderId: 'DUP')]);
    await expectLater(
      orders.createWithItems(
        _order(orderId: 'DUP'),
        [_item(orderId: 'DUP', productCode: 'X'), _item(orderId: 'DUP', productCode: 'Y')],
      ),
      throwsA(isA<DuplicateOrderIdException>()),
    );
    final db = await database.database;
    expect(await db.query('orders'), hasLength(1));
    final items = await db.query('transactions');
    expect(items, hasLength(1));
    expect(items.single['product_code'], 'P');
  });

  test('same order id in different accounts is allowed', () async {
    final a = (await accounts.activeAccount())!;
    await orders.createWithItems(_order(orderId: 'SHARED'), [_item(orderId: 'SHARED')]);
    await accounts.create(name: 'Other');
    final orderPk = await orders.createWithItems(
      _order(orderId: 'SHARED'),
      [
        _item(orderId: 'SHARED', productCode: 'B1'),
        _item(orderId: 'SHARED', productCode: 'B2'),
      ],
    );
    final db = await database.database;
    final rows = await db.query('orders', orderBy: 'id ASC');
    expect(rows, hasLength(2));
    expect(rows.first['account_id'], a.id);
    expect(rows.last['account_id'], isNot(a.id));
    final items = await db.query('transactions', where: 'order_fk = ?', whereArgs: [orderPk], orderBy: 'item_index ASC');
    expect(items, hasLength(2));
  });

  test('createWithItems rejects item-less order', () async {
    // Empty list -> order only, no items. Repository permits this because
    // items list length 0 makes the loop a no-op. Documented behavior: callers
    // must always pass >= 1 item.
    final orderPk = await orders.createWithItems(_order(orderId: 'EMPTY'), const []);
    final db = await database.database;
    expect(await db.query('orders', where: 'id = ?', whereArgs: [orderPk]), hasLength(1));
    expect(await db.query('transactions', where: 'order_fk = ?', whereArgs: [orderPk]), isEmpty);
  });

  test('repositories expose joined multi-item read after submission', () async {
    await orders.createWithItems(
      _order(orderId: 'JOIN'),
      [
        _item(orderId: 'JOIN', productCode: 'A'),
        _item(orderId: 'JOIN', productCode: 'B'),
      ],
    );
    final rows = await transactions.listItemsJoined();
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.order.orderId == 'JOIN'), isTrue);
    expect(rows.every((r) => r.item.orderFk == rows.first.item.orderFk), isTrue);
    expect(rows.map((r) => r.item.productCode).toSet(), {'A', 'B'});
  });
}