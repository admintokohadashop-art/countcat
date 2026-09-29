import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseException;

import '../database/app_database.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import 'account_repository.dart';
import 'transaction_repository.dart' show DuplicateOrderIdException;

class OrderRepository {
  OrderRepository(this._database);
  final AppDatabase _database;

  Future<int> _requireActiveId() async {
    final id = (await AccountRepository(_database).activeAccount())?.id;
    if (id == null) throw StateError('No active account.');
    return id;
  }

  Future<Order?> get(int id) async {
    final accountId = (await AccountRepository(_database).activeAccount())?.id;
    if (accountId == null) return null;
    final db = await _database.database;
    final rows = await db.query('orders', where: 'id = ? AND account_id = ?', whereArgs: [id, accountId]);
    return rows.isEmpty ? null : Order.fromMap(rows.single);
  }

  Future<List<Order>> list({
    int? liveSessionId,
    DateTime? periodStart,
    DateTime? periodEnd,
    String search = '',
  }) async {
    final accountId = (await AccountRepository(_database).activeAccount())?.id;
    if (accountId == null) return const [];
    final clauses = <String>['account_id = ?'];
    final args = <Object?>[accountId];
    if (liveSessionId != null) {
      clauses.add('live_session_id = ?');
      args.add(liveSessionId);
    }
    if (periodStart != null) {
      clauses.add('transaction_date >= ?');
      args.add(Order.formatLocalDate(periodStart));
    }
    if (periodEnd != null) {
      clauses.add('transaction_date < ?');
      args.add(Order.formatLocalDate(periodEnd));
    }
    final trimmed = search.trim();
    if (trimmed.isNotEmpty) {
      clauses.add('order_id LIKE ?');
      args.add('%$trimmed%');
    }
    final db = await _database.database;
    final rows = await db.query(
      'orders',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'transaction_date DESC, id DESC',
    );
    return rows.map(Order.fromMap).toList();
  }

  /// Account-scoped write. The Order model's [Order.accountId] is a read-side
  /// value; creation always targets the active account so cross-account
  /// collisions are impossible by construction.
  Future<int> create(Order order) async {
    final accountId = await _requireActiveId();
    final db = await _database.database;
    try {
      return await db.transaction<int>((tx) async {
        final existing = await tx.query(
          'orders',
          columns: ['id'],
          where: 'account_id = ? AND order_id = ?',
          whereArgs: [accountId, order.orderId],
          limit: 1,
        );
        if (existing.isNotEmpty) throw DuplicateOrderIdException(order.orderId);
        final values = Map<String, Object?>.from(order.toMap())
          ..remove('id')
          ..['account_id'] = accountId;
        return tx.insert('orders', values, conflictAlgorithm: ConflictAlgorithm.abort);
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateOrderIdException(order.orderId);
      rethrow;
    }
  }

  /// Atomic order + items creation in one SQLite transaction.
  /// Account-scoped duplicate pre-check + UNIQUE(account_id, order_id) as
  /// final guard.
  Future<int> createWithItems(Order order, List<Transaction> items) async {
    final accountId = await _requireActiveId();
    final db = await _database.database;
    try {
      return await db.transaction<int>((tx) async {
        final existing = await tx.query(
          'orders',
          columns: ['id'],
          where: 'account_id = ? AND order_id = ?',
          whereArgs: [accountId, order.orderId],
          limit: 1,
        );
        if (existing.isNotEmpty) throw DuplicateOrderIdException(order.orderId);
        final orderValues = Map<String, Object?>.from(order.toMap())
          ..remove('id')
          ..['account_id'] = accountId;
        final orderPk = await tx.insert('orders', orderValues, conflictAlgorithm: ConflictAlgorithm.abort);
        for (var i = 0; i < items.length; i++) {
          final values = Map<String, Object?>.from(items[i].toMap())
            ..remove('id')
            ..['order_fk'] = orderPk
            ..['item_index'] = i
            ..['account_id'] = accountId;
          await tx.insert('transactions', values);
        }
        return orderPk;
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateOrderIdException(order.orderId);
      rethrow;
    }
  }

  Future<void> update(Order order) async {
    final id = order.id;
    if (id == null) throw ArgumentError.value(id, 'order.id');
    final accountId = (await AccountRepository(_database).activeAccount())?.id;
    final db = await _database.database;
    try {
      final values = Map<String, Object?>.from(order.toMap())
        ..remove('id')
        ..remove('created_at')
        ..remove('account_id') // never re-scope an order via update
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await db.update(
        'orders',
        values,
        where: accountId == null ? 'id = ?' : 'id = ? AND account_id = ?',
        whereArgs: accountId == null ? [id] : [id, accountId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateOrderIdException(order.orderId);
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    final accountId = (await AccountRepository(_database).activeAccount())?.id;
    final db = await _database.database;
    await db.transaction((tx) async {
      if (accountId == null) {
        await tx.delete('transactions', where: 'order_fk = ?', whereArgs: [id]);
        await tx.delete('orders', where: 'id = ?', whereArgs: [id]);
        return;
      }
      final owned = await tx.query('orders', columns: ['id'], where: 'id = ? AND account_id = ?', whereArgs: [id, accountId]);
      if (owned.isEmpty) return;
      await tx.delete('transactions', where: 'order_fk = ?', whereArgs: [id]);
      await tx.delete('orders', where: 'id = ?', whereArgs: [id]);
    });
  }
}