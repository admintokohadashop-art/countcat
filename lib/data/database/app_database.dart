import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../../core/profile/avatar_storage.dart';
import '../../core/storage/countcat_data_paths.dart';

class AppDatabase {
  AppDatabase._({sqflite.DatabaseFactory? databaseFactory, String? databasePath, CountCatDataPaths? paths})
      : _databaseFactory = databaseFactory,
        _databasePath = databasePath,
        _paths = paths ?? CountCatDataPaths();

  static final instance = AppDatabase._();
  static const databaseName = CountCatDataPaths.databaseFilename;
  static const _schemaVersion = 6;
  sqflite.Database? _database;
  final sqflite.DatabaseFactory? _databaseFactory;
  final String? _databasePath;
  final CountCatDataPaths _paths;

  factory AppDatabase.inMemoryForTesting() {
    ffi.sqfliteFfiInit();
    return AppDatabase._(databaseFactory: ffi.databaseFactoryFfi, databasePath: ffi.inMemoryDatabasePath);
  }

  factory AppDatabase.forTesting({required CountCatDataPaths paths, required sqflite.DatabaseFactory databaseFactory}) =>
      AppDatabase._(databaseFactory: databaseFactory, paths: paths);

  Future<sqflite.Database> get database async {
    if (_database != null) return _database!;
    final factory = _databaseFactory ?? _factory();
    final path = _databasePath ?? await _persistentPath();
    _database = await factory.openDatabase(path, options: sqflite.OpenDatabaseOptions(version: _schemaVersion, onCreate: _create, onUpgrade: _upgrade));
    if (_databasePath == null) await _migrateLegacyAvatars();
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  sqflite.DatabaseFactory _factory() {
    if (Platform.isWindows) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  Future<String> _persistentPath() async {
    final persistent = await _paths.databaseFile;
    if (await persistent.exists()) return persistent.path;
    final legacy = _paths.legacyDatabaseFile();
    if (await legacy.exists()) {
      await persistent.parent.create(recursive: true);
      await legacy.copy(persistent.path);
    }
    return persistent.path;
  }

  Future<void> _migrateLegacyAvatars() async {
    final db = _database!;
    final storage = AvatarStorage(paths: _paths);
    final avatars = await _paths.avatarsDirectory;
    final rows = await db.query('accounts', columns: ['id', 'photo_path']);
    for (final row in rows) {
      final path = row['photo_path'] as String?;
      if (path == null || await storage.isOwnedPath(path)) continue;
      final source = File(path);
      if (!await source.exists()) {
        final restored = File('${avatars.path}${Platform.pathSeparator}${source.uri.pathSegments.last}');
        if (await restored.exists()) {
          await db.update('accounts', {'photo_path': restored.path}, where: 'id = ?', whereArgs: [row['id']]);
        }
        continue;
      }
      final extension = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '.jpg';
      final target = File('${avatars.path}${Platform.pathSeparator}${row['id']}_${DateTime.now().microsecondsSinceEpoch}$extension');
      await source.copy(target.path);
      await db.update('accounts', {'photo_path': target.path}, where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  Future<void> _create(sqflite.Database d, int _) async => _tables(d);

  Future<void> _tables(sqflite.DatabaseExecutor d) async {
    await d.execute('CREATE TABLE settings (key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at TEXT NOT NULL)');
    await d.execute("CREATE TABLE accounts (id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT '',photo_path TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)");
    await d.execute('CREATE TABLE account_settings (account_id INTEGER NOT NULL,key TEXT NOT NULL,value TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(account_id,key))');
    await d.execute('CREATE TABLE hpp_master (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER NOT NULL,name TEXT NOT NULL,unit_amount INTEGER NOT NULL,is_active INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)');
    await d.execute('CREATE TABLE live_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,name TEXT NOT NULL,started_at TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)');
    await d.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,live_session_id INTEGER,hpp_id INTEGER,hpp_unit_amount INTEGER NOT NULL DEFAULT 0,unit_price INTEGER NOT NULL DEFAULT 0,transaction_date TEXT NOT NULL,product_code TEXT NOT NULL,order_id TEXT NOT NULL,quantity INTEGER NOT NULL,gmv_amount INTEGER NOT NULL,payment_description TEXT,payment_status TEXT NOT NULL CHECK(payment_status IN ('pending','paid','cancelled')),paid_at TEXT,net_income_amount INTEGER NOT NULL,return_shipping_compensation INTEGER NOT NULL DEFAULT 0,order_status TEXT NOT NULL CHECK(order_status IN ('new','dropoff','shipping','closed','returned','cancel')),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,UNIQUE(account_id,order_id))");
    await d.execute('CREATE TABLE monthly_reports (account_id INTEGER,year INTEGER NOT NULL,month INTEGER NOT NULL,period_start TEXT NOT NULL,period_end TEXT NOT NULL,gmv_total INTEGER NOT NULL,net_income_total INTEGER NOT NULL,hpp_total INTEGER NOT NULL,profit_total INTEGER NOT NULL,submitted_at TEXT NOT NULL,UNIQUE(account_id,year,month))');
    for (final sql in ['CREATE INDEX tx_account_index ON transactions(account_id)', 'CREATE INDEX sessions_account_index ON live_sessions(account_id)', 'CREATE INDEX hpp_account_index ON hpp_master(account_id,is_active)', 'CREATE INDEX reports_account_index ON monthly_reports(account_id)']) {
      await d.execute(sql);
    }
  }

  Future<void> _upgrade(sqflite.Database d, int old, int _) async {
    if (old < 3) {
      await _migrateFromLegacyToLatest(d);
      return;
    }
    if (old == 3) {
      await _migrateTransactionsV3ToV4(d);
    }
    if (old == 3 || old == 4) {
      await _migrateTransactionsV4ToV5(d);
    }
    if (old == 3 || old == 4 || old == 5) {
      await _migrateTransactionsV5ToV6(d);
    }
  }

  static String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _localDateFromUtcIso(String utcIso) {
    final parsed = DateTime.tryParse(utcIso);
    if (parsed == null) {
      final now = DateTime.now();
      return _dateString(DateTime(now.year, now.month, now.day));
    }
    final local = parsed.toLocal();
    return _dateString(DateTime(local.year, local.month, local.day));
  }

  Future<void> _migrateFromLegacyToLatest(sqflite.Database d) async {
    await d.transaction((tx) async {
      for (final t in ['settings', 'live_sessions', 'transactions', 'monthly_reports']) {
        try { await tx.execute('ALTER TABLE $t RENAME TO legacy_$t'); } catch (_) {}
      }
      await _tables(tx);
      final now = DateTime.now().toUtc().toIso8601String();
      final aid = await tx.insert('accounts', {'name': 'Default Account', 'description': 'Migrated existing data', 'created_at': now, 'updated_at': now});
      await tx.insert('settings', {'key': 'active_account_id', 'value': '$aid', 'updated_at': now});
      try {
        final s = await tx.query('legacy_settings');
        for (final r in s) {
          if (r['key'] == 'global_hpp') {
            await tx.insert('hpp_master', {'account_id': aid, 'name': 'Default HPP', 'unit_amount': int.tryParse(r['value'] as String) ?? 0, 'is_active': 1, 'created_at': now, 'updated_at': now});
          } else {
            await tx.insert('settings', r);
          }
        }
      } catch (_) {}
      try {
        await tx.execute('INSERT INTO live_sessions(id,account_id,name,started_at,created_at,updated_at) SELECT id,$aid,name,started_at,created_at,updated_at FROM legacy_live_sessions');
      } catch (_) {}
      try {
        final h = await tx.query('hpp_master', where: 'account_id=?', whereArgs: [aid], limit: 1);
        final amount = h.isEmpty ? 0 : h.single['unit_amount'] as int;
        final legacyRows = await tx.query('legacy_transactions');
        for (final row in legacyRows) {
          final createdAtRaw = (row['created_at'] as String?) ?? now;
          final txDate = _localDateFromUtcIso(createdAtRaw);
          final gmv = (row['gmv_amount'] as int?) ?? 0;
          final qty = (row['quantity'] as int?) ?? 1;
          final unitPrice = qty > 0 ? gmv ~/ qty : 0;
          await tx.insert('transactions', {
            'id': row['id'],
            'account_id': aid,
            'live_session_id': row['live_session_id'],
            'hpp_unit_amount': amount,
            'unit_price': unitPrice,
            'transaction_date': txDate,
            'product_code': row['product_code'],
            'order_id': row['order_id'],
            'quantity': qty,
            'gmv_amount': gmv,
            'payment_description': row['payment_description'],
            'payment_status': row['payment_status'],
            'paid_at': row['paid_at'],
            'net_income_amount': row['net_income_amount'],
            'return_shipping_compensation': 0,
            'order_status': row['order_status'],
            'created_at': createdAtRaw,
            'updated_at': row['updated_at'],
          });
        }
      } catch (_) {}
      try {
        await tx.execute('INSERT INTO monthly_reports(account_id,year,month,period_start,period_end,gmv_total,net_income_total,hpp_total,profit_total,submitted_at) SELECT $aid,year,month,period_start,period_end,gmv_total,net_income_total,hpp_total,profit_total,submitted_at FROM legacy_monthly_reports');
      } catch (_) {}
    });
  }

  Future<void> _migrateTransactionsV3ToV4(sqflite.Database d) async {
    await d.transaction((tx) async {
      await tx.execute('ALTER TABLE transactions RENAME TO legacy_transactions_v3');
      await tx.execute('DROP INDEX IF EXISTS tx_account_index');
      await tx.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,live_session_id INTEGER,hpp_id INTEGER,hpp_unit_amount INTEGER NOT NULL DEFAULT 0,unit_price INTEGER NOT NULL DEFAULT 0,product_code TEXT NOT NULL,order_id TEXT NOT NULL,quantity INTEGER NOT NULL,gmv_amount INTEGER NOT NULL,payment_description TEXT,payment_status TEXT NOT NULL CHECK(payment_status IN ('pending','paid','cancelled')),paid_at TEXT,net_income_amount INTEGER NOT NULL,order_status TEXT NOT NULL CHECK(order_status IN ('new','dropoff','shipping','closed','returned','cancel')),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,UNIQUE(account_id,order_id))");
      await tx.execute('CREATE INDEX tx_account_index ON transactions(account_id)');
      await tx.execute("INSERT INTO transactions(id,account_id,live_session_id,hpp_id,hpp_unit_amount,unit_price,product_code,order_id,quantity,gmv_amount,payment_description,payment_status,paid_at,net_income_amount,order_status,created_at,updated_at) SELECT id,account_id,live_session_id,hpp_id,hpp_unit_amount,CASE WHEN quantity > 0 THEN CAST(gmv_amount / quantity AS INTEGER) ELSE 0 END,product_code,order_id,quantity,gmv_amount,payment_description,payment_status,paid_at,net_income_amount,order_status,created_at,updated_at FROM legacy_transactions_v3");
      await tx.execute('DROP TABLE legacy_transactions_v3');
    });
  }

  Future<void> _migrateTransactionsV4ToV5(sqflite.Database d) async {
    await d.transaction((tx) async {
      await tx.execute('ALTER TABLE transactions RENAME TO legacy_transactions_v4');
      await tx.execute('DROP INDEX IF EXISTS tx_account_index');
      await tx.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT,account_id INTEGER,live_session_id INTEGER,hpp_id INTEGER,hpp_unit_amount INTEGER NOT NULL DEFAULT 0,unit_price INTEGER NOT NULL DEFAULT 0,transaction_date TEXT NOT NULL,product_code TEXT NOT NULL,order_id TEXT NOT NULL,quantity INTEGER NOT NULL,gmv_amount INTEGER NOT NULL,payment_description TEXT,payment_status TEXT NOT NULL CHECK(payment_status IN ('pending','paid','cancelled')),paid_at TEXT,net_income_amount INTEGER NOT NULL,order_status TEXT NOT NULL CHECK(order_status IN ('new','dropoff','shipping','closed','returned','cancel')),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,UNIQUE(account_id,order_id))");
      await tx.execute('CREATE INDEX tx_account_index ON transactions(account_id)');
      final legacyRows = await tx.query('legacy_transactions_v4');
      for (final row in legacyRows) {
        final createdAtRaw = (row['created_at'] as String?) ?? DateTime.now().toUtc().toIso8601String();
        final txDate = _localDateFromUtcIso(createdAtRaw);
        await tx.insert('transactions', {
          'id': row['id'],
          'account_id': row['account_id'],
          'live_session_id': row['live_session_id'],
          'hpp_id': row['hpp_id'],
          'hpp_unit_amount': row['hpp_unit_amount'],
          'unit_price': row['unit_price'],
          'transaction_date': txDate,
          'product_code': row['product_code'],
          'order_id': row['order_id'],
          'quantity': row['quantity'],
          'gmv_amount': row['gmv_amount'],
          'payment_description': row['payment_description'],
          'payment_status': row['payment_status'],
          'paid_at': row['paid_at'],
          'net_income_amount': row['net_income_amount'],
          'order_status': row['order_status'],
          'created_at': createdAtRaw,
          'updated_at': row['updated_at'],
        });
      }
      await tx.execute('DROP TABLE legacy_transactions_v4');
    });
  }

  Future<void> _migrateTransactionsV5ToV6(sqflite.Database d) async {
    await d.transaction((tx) async {
      await tx.execute('ALTER TABLE transactions ADD COLUMN return_shipping_compensation INTEGER NOT NULL DEFAULT 0');
    });
  }
}