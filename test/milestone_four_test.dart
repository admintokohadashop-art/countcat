import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:tiktok_seller/core/storage/countcat_data_paths.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('OrderStatus.cancel', () {
    test('exists with value cancel and label CANCEL', () {
      expect(OrderStatus.cancel.value, 'cancel');
      expect(OrderStatus.cancel.label, 'CANCEL');
    });

    test('is positioned after returned', () {
      expect(
        OrderStatus.values.indexOf(OrderStatus.cancel),
        greaterThan(OrderStatus.values.indexOf(OrderStatus.returned)),
      );
    });

    test('fromValue resolves cancel', () {
      expect(OrderStatus.fromValue('cancel'), OrderStatus.cancel);
    });
  });

  group('Transaction.unitPrice', () {
    test('defaults to 0 when omitted', () {
      final t = Transaction(
        productCode: 'SKU',
        orderId: 'ORDER',
        quantity: 1,
        gmvAmount: 1000,
        paymentStatus: PaymentStatus.pending,
        netIncomeAmount: 900,
        orderStatus: OrderStatus.newOrder,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(t.unitPrice, 0);
    });

    test('round-trips through toMap and fromMap', () {
      final now = DateTime(2026, 1, 1);
      final t = Transaction(
        id: 1,
        accountId: 1,
        unitPrice: 50000,
        productCode: 'SKU',
        orderId: 'ORDER',
        quantity: 2,
        gmvAmount: 100000,
        paymentStatus: PaymentStatus.pending,
        netIncomeAmount: 90000,
        orderStatus: OrderStatus.newOrder,
        createdAt: now,
        updatedAt: now,
      );
      final m = t.toMap();
      expect(m['unit_price'], 50000);
      final restored = Transaction.fromMap(m);
      expect(restored.unitPrice, 50000);
      expect(restored.gmvAmount, 100000);
      expect(restored.netIncomeAmount, 90000);
    });

    test('fromMap tolerates missing unit_price (legacy rows)', () {
      final now = DateTime(2026).toUtc().toIso8601String();
      final m = <String, Object?>{
        'id': 1,
        'account_id': 1,
        'live_session_id': null,
        'hpp_id': null,
        'hpp_unit_amount': 0,
        'product_code': 'P',
        'order_id': 'O',
        'quantity': 1,
        'gmv_amount': 5000,
        'payment_description': null,
        'payment_status': 'pending',
        'paid_at': null,
        'net_income_amount': 4500,
        'order_status': 'new',
        'created_at': now,
        'updated_at': now,
      };
      expect(Transaction.fromMap(m).unitPrice, 0);
    });

    test('copyWith preserves unitPrice when not provided', () {
      final now = DateTime(2026);
      final t = Transaction(
        unitPrice: 1000,
        productCode: 'P',
        orderId: 'O',
        quantity: 1,
        gmvAmount: 1000,
        paymentStatus: PaymentStatus.pending,
        netIncomeAmount: 900,
        orderStatus: OrderStatus.newOrder,
        createdAt: now,
        updatedAt: now,
      );
      expect(t.copyWith(quantity: 5).unitPrice, 1000);
      expect(t.copyWith(unitPrice: 2000).unitPrice, 2000);
    });
  });

  group('Schema v3 -> v4 migration', () {
    late Directory temp;
    late CountCatDataPaths paths;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('countcat-v3-v4-');
      paths = CountCatDataPaths(root: temp);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<void> createV3Database() async {
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
      await db.execute('CREATE INDEX sessions_account_index ON live_sessions(account_id)');
      await db.execute('CREATE INDEX hpp_account_index ON hpp_master(account_id,is_active)');
      await db.execute('CREATE INDEX reports_account_index ON monthly_reports(account_id)');
      await db.execute('PRAGMA user_version = 3');
      await db.close();
    }

    test('preserves v3 data and backfills unit_price from gmv/quantity', () async {
      await createV3Database();
      final file = await paths.databaseFile;
      final seed = await databaseFactoryFfi.openDatabase(file.path);
      final now = DateTime(2026, 9, 1).toUtc().toIso8601String();
      await seed.insert('transactions', {
        'account_id': 1,
        'live_session_id': null,
        'hpp_id': null,
        'hpp_unit_amount': 5000,
        'product_code': 'P1',
        'order_id': 'O1',
        'quantity': 2,
        'gmv_amount': 100000,
        'payment_description': 'desc',
        'payment_status': 'paid',
        'paid_at': now,
        'net_income_amount': 90000,
        'order_status': 'closed',
        'created_at': now,
        'updated_at': now,
      });
      await seed.close();

      final app = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final db = await app.database;
      final rows = await db.query('transactions');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['unit_price'], 50000);
      expect(row['gmv_amount'], 100000);
      expect(row['net_income_amount'], 90000);
      expect(row['hpp_unit_amount'], 5000);
      expect(row['quantity'], 2);
      expect(row['order_status'], 'closed');
      expect(row['product_code'], 'P1');
      expect(row['payment_status'], 'paid');
      await app.close();
    });

    test('backfills unit_price = 0 when quantity is 0', () async {
      await createV3Database();
      final file = await paths.databaseFile;
      final seed = await databaseFactoryFfi.openDatabase(file.path);
      final now = DateTime(2026).toUtc().toIso8601String();
      await seed.insert('transactions', {
        'account_id': 1,
        'hpp_unit_amount': 0,
        'product_code': 'P',
        'order_id': 'Z',
        'quantity': 0,
        'gmv_amount': 0,
        'payment_status': 'pending',
        'net_income_amount': 0,
        'order_status': 'new',
        'created_at': now,
        'updated_at': now,
      });
      await seed.close();

      final app = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final db = await app.database;
      expect((await db.query('transactions')).single['unit_price'], 0);
      await app.close();
    });

    test('v4 transactions table accepts order_status = cancel', () async {
      final app = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final db = await app.database;
      final now = DateTime(2026).toUtc().toIso8601String();
      await db.insert('transactions', {
        'account_id': 1,
        'hpp_unit_amount': 0,
        'unit_price': 1000,
        'product_code': 'P',
        'order_id': 'CANCELED',
        'quantity': 1,
        'gmv_amount': 1000,
        'payment_status': 'pending',
        'net_income_amount': 900,
        'order_status': 'cancel',
        'created_at': now,
        'updated_at': now,
      });
      final rows = await db.query('transactions', where: 'order_status = ?', whereArgs: ['cancel']);
      expect(rows, hasLength(1));
      await app.close();
    });
  });
}