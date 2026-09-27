import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class AppDatabase {
  AppDatabase._({sqflite.DatabaseFactory? databaseFactory, String? databasePath})
      : _databaseFactory = databaseFactory,
        _databasePath = databasePath;

  static final AppDatabase instance = AppDatabase._();
  static const _databaseName = 'tiktok_seller.db';
  static const _schemaVersion = 2;

  sqflite.Database? _database;
  final sqflite.DatabaseFactory? _databaseFactory;
  final String? _databasePath;

  factory AppDatabase.inMemoryForTesting() {
    ffi.sqfliteFfiInit();
    return AppDatabase._(
      databaseFactory: ffi.databaseFactoryFfi,
      databasePath: ffi.inMemoryDatabasePath,
    );
  }

  Future<sqflite.Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null) return existingDatabase;

    final factory = _databaseFactory ?? _databaseFactoryForCurrentPlatform();
    final databasePath = _databasePath ?? await _defaultDatabasePath(factory);
    final openedDatabase = await factory.openDatabase(
      databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = openedDatabase;
    return openedDatabase;
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<String> _defaultDatabasePath(sqflite.DatabaseFactory factory) async {
    final databasesPath = await factory.getDatabasesPath();
    return '$databasesPath${Platform.pathSeparator}$_databaseName';
  }

  sqflite.DatabaseFactory _databaseFactoryForCurrentPlatform() {
    if (Platform.isWindows) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  Future<void> _createSchema(sqflite.Database database, int version) async {
    await database.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE live_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        started_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        live_session_id INTEGER,
        product_code TEXT NOT NULL,
        order_id TEXT NOT NULL UNIQUE,
        quantity INTEGER NOT NULL,
        gmv_amount INTEGER NOT NULL,
        payment_description TEXT,
        payment_status TEXT NOT NULL CHECK(payment_status IN ('pending', 'paid', 'cancelled')),
        paid_at TEXT,
        net_income_amount INTEGER NOT NULL,
        order_status TEXT NOT NULL CHECK(order_status IN ('new', 'dropoff', 'shipping', 'closed', 'returned')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (live_session_id) REFERENCES live_sessions(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('CREATE INDEX transactions_live_session_index ON transactions(live_session_id)');
    await database.execute('CREATE INDEX transactions_product_code_index ON transactions(product_code)');
    await database.execute('CREATE INDEX transactions_payment_status_index ON transactions(payment_status)');
    await database.execute('CREATE INDEX transactions_order_status_index ON transactions(order_status)');
    await _createMonthlyReportsTable(database);
  }

  Future<void> _upgradeSchema(sqflite.Database database, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createMonthlyReportsTable(database);
  }

  Future<void> _createMonthlyReportsTable(sqflite.Database database) => database.execute('''
    CREATE TABLE IF NOT EXISTS monthly_reports (
      year INTEGER NOT NULL,
      month INTEGER NOT NULL,
      period_start TEXT NOT NULL,
      period_end TEXT NOT NULL,
      gmv_total INTEGER NOT NULL,
      net_income_total INTEGER NOT NULL,
      hpp_total INTEGER NOT NULL,
      profit_total INTEGER NOT NULL,
      submitted_at TEXT NOT NULL,
      PRIMARY KEY (year, month)
    )
  ''');
}
