import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:tiktok_seller/core/storage/countcat_data_paths.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('Order model', () {
    test('round-trips through toMap/fromMap', () {
      final now = DateTime(2026, 9, 15, 10);
      final order = Order(
        id: 1,
        accountId: 1,
        orderId: 'ORD-1',
        liveSessionId: 5,
        transactionDate: DateTime(2026, 9, 15),
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.closed,
        paidAt: now,
        returnShippingCompensation: 30000,
        paymentDescription: 'desc',
        createdAt: now,
        updatedAt: now,
      );
      final m = order.toMap();
      expect(m['transaction_date'], '2026-09-15');
      expect((m['paid_at'] as String).endsWith('Z'), isTrue);
      final restored = Order.fromMap(m);
      expect(restored.orderId, 'ORD-1');
      expect(restored.transactionDate.year, 2026);
      expect(restored.transactionDate.month, 9);
      expect(restored.transactionDate.day, 15);
      expect(restored.paidAt, isNotNull);
      expect(restored.returnShippingCompensation, 30000);
      expect(restored.paymentStatus, PaymentStatus.paid);
      expect(restored.orderStatus, OrderStatus.closed);
    });

    test('copyWith preserves fields when not provided', () {
      final now = DateTime(2026);
      final order = Order(
        id: 1,
        accountId: 1,
        orderId: 'ORD-1',
        transactionDate: DateTime(2026, 9, 15),
        paymentStatus: PaymentStatus.pending,
        orderStatus: OrderStatus.newOrder,
        createdAt: now,
        updatedAt: now,
      );
      final updated = order.copyWith(orderId: 'ORD-2');
      expect(updated.orderId, 'ORD-2');
      expect(updated.transactionDate.day, 15);
      expect(updated.paymentStatus, PaymentStatus.pending);
    });
  });

  group('Transaction (transitional v7)', () {
    test('orderFk and itemIndex default sensibly', () {
      final t = Transaction(
        transactionDate: DateTime(2026, 9, 15),
        productCode: 'P',
        orderId: 'O',
        quantity: 1,
        gmvAmount: 1000,
        paymentStatus: PaymentStatus.pending,
        netIncomeAmount: 900,
        orderStatus: OrderStatus.newOrder,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(t.orderFk, isNull);
      expect(t.itemIndex, 0);
    });

    test('round-trips orderFk and itemIndex through toMap/fromMap', () {
      final now = DateTime(2026, 9, 15, 10);
      final t = Transaction(
        id: 10,
        orderFk: 42,
        itemIndex: 2,
        accountId: 1,
        transactionDate: DateTime(2026, 9, 15),
        productCode: 'P',
        orderId: 'O',
        quantity: 2,
        unitPrice: 5000,
        gmvAmount: 10000,
        paymentStatus: PaymentStatus.paid,
        netIncomeAmount: 9000,
        orderStatus: OrderStatus.closed,
        createdAt: now,
        updatedAt: now,
      );
      final m = t.toMap();
      expect(m['order_fk'], 42);
      expect(m['item_index'], 2);
      final restored = Transaction.fromMap(m);
      expect(restored.orderFk, 42);
      expect(restored.itemIndex, 2);
    });

    test('fromMap tolerates missing order_fk and item_index (legacy rows)', () {
      final now = DateTime(2026).toUtc().toIso8601String();
      final m = <String, Object?>{
        'id': 1, 'account_id': 1, 'live_session_id': null, 'hpp_id': null,
        'hpp_unit_amount': 0, 'unit_price': 0,
        'transaction_date': '2026-09-15',
        'product_code': 'P', 'order_id': 'O', 'quantity': 1,
        'gmv_amount': 1000, 'payment_description': null,
        'payment_status': 'pending', 'paid_at': null,
        'net_income_amount': 900, 'order_status': 'new',
        'created_at': now, 'updated_at': now,
      };
      final restored = Transaction.fromMap(m);
      expect(restored.orderFk, isNull);
      expect(restored.itemIndex, 0);
    });
  });

  group('TransactionWithOrder', () {
    test('builds from a merged map', () {
      final now = DateTime(2026, 9, 15, 10).toUtc().toIso8601String();
      final m = <String, Object?>{
        'id': 5,
        'order_fk': 5,
        'item_index': 0,
        'account_id': 1,
        'live_session_id': null,
        'hpp_id': null,
        'hpp_unit_amount': 0,
        'unit_price': 5000,
        'transaction_date': '2026-09-15',
        'product_code': 'P',
        'order_id': 'ORD-1',
        'quantity': 2,
        'gmv_amount': 10000,
        'payment_description': null,
        'payment_status': 'paid',
        'paid_at': now,
        'net_income_amount': 9000,
        'return_shipping_compensation': 30000,
        'order_status': 'closed',
        'created_at': now,
        'updated_at': now,
      };
      final view = TransactionWithOrder.fromMap(m);
      expect(view.item.orderFk, 5);
      expect(view.order.orderId, 'ORD-1');
      expect(view.order.returnShippingCompensation, 30000);
      expect(view.item.quantity, 2);
    });
  });

  group('Schema v6 -> v8 migration', () {
    late Directory temp;
    late CountCatDataPaths paths;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('countcat-v6-v8-');
      paths = CountCatDataPaths(root: temp);
    });
    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<void> createV6Database() async {
      final file = await paths.databaseFile;
      await file.parent.create(recursive: true);
      final db = await databaseFactoryFfi.openDatabase(file.path);
      await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await db.execute("CREATE TABLE accounts (id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT '',photo_path TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)");
      await db.execute('CREATE TABLE account_settings (account_id INTEGER NOT NULL,key TEXT NOT NULL,value TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(account_id,key))');
      await db.execute('CREATE TABLE hpp_master (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER NOT NULL,name TEXT NOT NULL,unit_amount INTEGER NOT NULL,is_active INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE live_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,name TEXT NOT NULL,started_at TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await db.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,live_session_id INTEGER,hpp_id INTEGER,hpp_unit_amount INTEGER NOT NULL DEFAULT 0,unit_price INTEGER NOT NULL DEFAULT 0,transaction_date TEXT NOT NULL,product_code TEXT NOT NULL,order_id TEXT NOT NULL,quantity INTEGER NOT NULL,gmv_amount INTEGER NOT NULL,payment_description TEXT,payment_status TEXT NOT NULL CHECK(payment_status IN ('pending','paid','cancelled')),paid_at TEXT,net_income_amount INTEGER NOT NULL,return_shipping_compensation INTEGER NOT NULL DEFAULT 0,order_status TEXT NOT NULL CHECK(order_status IN ('new','dropoff','shipping','closed','returned','cancel')),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,UNIQUE(account_id,order_id))");
      await db.execute('CREATE TABLE monthly_reports (account_id INTEGER,year INTEGER NOT NULL,month INTEGER NOT NULL,period_start TEXT NOT NULL,period_end TEXT NOT NULL,gmv_total INTEGER NOT NULL,net_income_total INTEGER NOT NULL,hpp_total INTEGER NOT NULL,profit_total INTEGER NOT NULL,submitted_at TEXT NOT NULL,UNIQUE(account_id,year,month))');
      await db.execute('CREATE INDEX tx_account_index ON transactions(account_id)');
      await db.execute('CREATE INDEX sessions_account_index ON live_sessions(account_id)');
      await db.execute('CREATE INDEX hpp_account_index ON hpp_master(account_id,is_active)');
      await db.execute('CREATE INDEX reports_account_index ON monthly_reports(account_id)');
      await db.execute('PRAGMA user_version = 6');
      final now = DateTime(2026, 9, 15, 10).toUtc().toIso8601String();
      await db.insert('transactions', {
        'account_id': 1,
        'live_session_id': 7,
        'hpp_unit_amount': 20000,
        'unit_price': 50000,
        'transaction_date': '2026-09-15',
        'product_code': 'P1',
        'order_id': 'ORD-V6',
        'quantity': 2,
        'gmv_amount': 100000,
        'payment_description': 'desc',
        'payment_status': 'paid',
        'paid_at': now,
        'net_income_amount': 90000,
        'return_shipping_compensation': 30000,
        'order_status': 'closed',
        'created_at': now,
        'updated_at': now,
      });
      await db.close();
    }

    test('backfills orders and order_fk/item_index from v6 rows', () async {
      await createV6Database();
      final app = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final db = await app.database;

      final orderRows = await db.query('orders');
      expect(orderRows, hasLength(1));
      final order = orderRows.single;
      expect(order['order_id'], 'ORD-V6');
      expect(order['account_id'], 1);
      expect(order['live_session_id'], 7);
      expect(order['transaction_date'], '2026-09-15');
      expect(order['payment_status'], 'paid');
      expect(order['order_status'], 'closed');
      expect(order['return_shipping_compensation'], 30000);
      expect(order['payment_description'], 'desc');

      final txnRows = await db.query('transactions');
      expect(txnRows, hasLength(1));
      final txn = txnRows.single;
      expect(txn['order_id'], 'ORD-V6');
      expect(txn['order_fk'], txn['id']);
      expect(txn['item_index'], 0);
      expect(txn['unit_price'], 50000);
      expect(txn['gmv_amount'], 100000);
      expect(txn['net_income_amount'], 90000);
      expect(txn['hpp_unit_amount'], 20000);
      expect(txn['quantity'], 2);
      expect(txn['product_code'], 'P1');

      final version = (await db.rawQuery('PRAGMA user_version')).single.values.first as int;
      expect(version, 8);
      await app.close();
    });

    test('v8 transactions accepts a row with order_fk pointing to orders', () async {
      await createV6Database();
      final app = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final db = await app.database;
      final now = DateTime(2026, 9, 15, 10).toUtc().toIso8601String();
      final orderId = await db.insert('orders', {
        'account_id': 1,
        'order_id': 'ORD-NEW',
        'transaction_date': '2026-09-16',
        'payment_status': 'pending',
        'order_status': 'new',
        'return_shipping_compensation': 0,
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('transactions', {
        'order_fk': orderId,
        'item_index': 0,
        'account_id': 1,
        'transaction_date': '2026-09-16',
        'product_code': 'X',
        'order_id': 'ORD-NEW',
        'quantity': 1,
        'gmv_amount': 1000,
        'payment_status': 'pending',
        'net_income_amount': 900,
        'order_status': 'new',
        'created_at': now,
        'updated_at': now,
      });
      final joined = await db.rawQuery(
        'SELECT t.id AS txn_id, o.id AS order_id_pk FROM transactions t JOIN orders o ON o.id = t.order_fk WHERE t.order_id = ?',
        ['ORD-NEW'],
      );
      expect(joined, hasLength(1));
      expect(joined.single['order_id_pk'], orderId);
      await app.close();
    });
  });

  group('Chained migration to v8', () {
    late Directory temp;
    late CountCatDataPaths paths;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('countcat-chain-v8-');
      paths = CountCatDataPaths(root: temp);
    });
    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('v3 -> v4 -> v5 -> v6 -> v7 -> v8 preserves data and fills order_fk', () async {
      final file = await paths.databaseFile;
      await file.parent.create(recursive: true);
      final db = await databaseFactoryFfi.openDatabase(file.path);
      await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await db.execute("CREATE TABLE accounts (id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT '',photo_path TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)");
      await db.execute('CREATE TABLE account_settings (account_id INTEGER NOT NULL,key TEXT NOT NULL,value TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(account_id,key))');
      await db.execute('CREATE TABLE hpp_master (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER NOT NULL,name TEXT NOT NULL,unit_amount INTEGER NOT NULL,is_active INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE live_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,name TEXT NOT NULL,started_at TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await db.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,live_session_id INTEGER,hpp_id INTEGER,hpp_unit_amount INTEGER NOT NULL DEFAULT 0,product_code TEXT NOT NULL,order_id TEXT NOT NULL,quantity INTEGER NOT NULL,gmv_amount INTEGER NOT NULL,payment_description TEXT,payment_status TEXT NOT NULL CHECK(payment_status IN ('pending','paid','cancelled')),paid_at TEXT,net_income_amount INTEGER NOT NULL,order_status TEXT NOT NULL CHECK(order_status IN ('new','dropoff','shipping','closed','returned')),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,UNIQUE(account_id,order_id))");
      await db.execute('CREATE TABLE monthly_reports (account_id INTEGER,year INTEGER NOT NULL,month INTEGER NOT NULL,period_start TEXT NOT NULL,period_end TEXT NOT NULL,gmv_total INTEGER NOT NULL,net_income_total INTEGER NOT NULL,hpp_total INTEGER NOT NULL,profit_total INTEGER NOT NULL,submitted_at TEXT NOT NULL,UNIQUE(account_id,year,month))');
      await db.execute('CREATE INDEX tx_account_index ON transactions(account_id)');
      await db.execute('PRAGMA user_version = 3');
      final createdAtUtc = '2026-08-17T23:00:00.000Z';
      await db.insert('transactions', {
        'account_id': 1,
        'hpp_unit_amount': 5000,
        'product_code': 'P-LEGACY',
        'order_id': 'ORD-LEGACY',
        'quantity': 2,
        'gmv_amount': 100000,
        'payment_status': 'paid',
        'paid_at': createdAtUtc,
        'net_income_amount': 90000,
        'order_status': 'closed',
        'created_at': createdAtUtc,
        'updated_at': createdAtUtc,
      });
      await db.close();

      final app = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final opened = await app.database;
      final txn = (await opened.query('transactions')).single;
      expect(txn['order_id'], 'ORD-LEGACY');
      expect(txn['unit_price'], 50000);
      expect(txn['order_fk'], txn['id']);
      expect(txn['item_index'], 0);

      final order = (await opened.query('orders')).single;
      expect(order['order_id'], 'ORD-LEGACY');

      final expectedLocal = DateTime.parse(createdAtUtc).toLocal();
      final expectedDate =
          '${expectedLocal.year.toString().padLeft(4, '0')}-${expectedLocal.month.toString().padLeft(2, '0')}-${expectedLocal.day.toString().padLeft(2, '0')}';
      expect(order['transaction_date'], expectedDate);

      final version = (await opened.rawQuery('PRAGMA user_version')).single.values.first as int;
      expect(version, 8);
      await app.close();
    });
  });
}