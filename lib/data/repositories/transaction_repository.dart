import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseException;

import '../database/app_database.dart';
import '../models/order.dart';
import '../models/statuses.dart';
import '../models/transaction.dart';
import '../models/transaction_with_order.dart';
import 'account_repository.dart';

class DuplicateOrderIdException implements Exception {
  const DuplicateOrderIdException(this.orderId);
  final String orderId;
}

class TransactionRepository {
  TransactionRepository(this._database);
  final AppDatabase _database;

  Future<int?> _activeId() async => (await AccountRepository(_database).activeAccount())?.id;

  // ───────────────────────── legacy (M1–M6) CRUD ─────────────────────────

  /// Legacy insert. Kept for M1–M6 call-sites. Internally creates a matching
  /// `orders` row + one item row inside a single transaction so that the new
  /// M7 relational model stays consistent with legacy callers.
  Future<int> insertTransaction(Transaction transaction) async {
    final accountId = transaction.accountId ?? await _activeId();
    final db = await _database.database;
    try {
      return await db.transaction<int>((tx) async {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final orderPk = await tx.insert('orders', {
          'account_id': accountId,
          'order_id': transaction.orderId,
          'live_session_id': transaction.liveSessionId,
          'transaction_date': Transaction.formatLocalDate(transaction.transactionDate),
          'payment_status': transaction.paymentStatus.value,
          'order_status': transaction.orderStatus.value,
          'paid_at': transaction.paidAt?.toUtc().toIso8601String(),
          'return_shipping_compensation': transaction.returnShippingCompensation,
          'payment_description': transaction.paymentDescription,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        final values = Map<String, Object?>.from(transaction.toMap())
          ..remove('id')
          ..['order_fk'] = orderPk
          ..['item_index'] = transaction.itemIndex
          ..['account_id'] = accountId;
        return tx.insert('transactions', values);
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateOrderIdException(transaction.orderId);
      rethrow;
    }
  }

  /// Legacy read. Returns item-level rows from the `transactions` table,
  /// with the transitional mirror columns populated for M1–M6 compatibility.
  Future<List<Transaction>> listTransactions({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final clauses = <String>[];
    final arguments = <Object?>[];
    final accountId = await _activeId();
    if (accountId != null) {
      clauses.add('account_id = ?');
      arguments.add(accountId);
    }
    final trimmedSearch = search.trim();
    if (trimmedSearch.isNotEmpty) {
      clauses.add('(order_id LIKE ? OR product_code LIKE ?)');
      arguments..add('%$trimmedSearch%')..add('%$trimmedSearch%');
    }
    if (liveSessionId != null) {
      clauses.add('live_session_id = ?');
      arguments.add(liveSessionId);
    }
    if (paymentStatus != null) {
      clauses.add('payment_status = ?');
      arguments.add(paymentStatus.value);
    }
    if (orderStatus != null) {
      clauses.add('order_status = ?');
      arguments.add(orderStatus.value);
    }
    if (periodStart != null) {
      clauses.add('transaction_date >= ?');
      arguments.add(Transaction.formatLocalDate(periodStart));
    }
    if (periodEnd != null) {
      clauses.add('transaction_date < ?');
      arguments.add(Transaction.formatLocalDate(periodEnd));
    }
    final database = await _database.database;
    final rows = await database.query(
      'transactions',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Transaction.fromMap).toList();
  }

  /// Legacy update. Updates the item row AND its parent order row so that the
  /// order-level mirror fields cannot drift.
  Future<void> updateTransaction(Transaction transaction) async {
    final id = transaction.id;
    if (id == null) throw ArgumentError.value(id, 'transaction.id');
    final database = await _database.database;
    final accountId = await _activeId();
    try {
      await database.transaction((tx) async {
        final itemRows = await tx.query(
          'transactions',
          columns: ['order_fk'],
          where: accountId == null ? 'id = ?' : 'id = ? AND account_id = ?',
          whereArgs: accountId == null ? [id] : [id, accountId],
        );
        if (itemRows.isEmpty) return;
        final orderFk = itemRows.single['order_fk'] as int?;
        final nowIso = DateTime.now().toUtc().toIso8601String();
        if (orderFk != null) {
          await tx.update('orders', {
            'order_id': transaction.orderId,
            'live_session_id': transaction.liveSessionId,
            'transaction_date': Transaction.formatLocalDate(transaction.transactionDate),
            'payment_status': transaction.paymentStatus.value,
            'order_status': transaction.orderStatus.value,
            'paid_at': transaction.paidAt?.toUtc().toIso8601String(),
            'return_shipping_compensation': transaction.returnShippingCompensation,
            'payment_description': transaction.paymentDescription,
            'updated_at': nowIso,
          }, where: 'id = ?', whereArgs: [orderFk], conflictAlgorithm: ConflictAlgorithm.abort);
        }
        final values = Map<String, Object?>.from(transaction.toMap())
          ..remove('id')
          ..remove('created_at')
          ..remove('order_fk')
          ..remove('item_index')
          ..['updated_at'] = nowIso;
        await tx.update('transactions', values, where: 'id = ?', whereArgs: [id], conflictAlgorithm: ConflictAlgorithm.abort);
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateOrderIdException(transaction.orderId);
      rethrow;
    }
  }

  /// Legacy delete. Removes the item and, when it was the last item of its
  /// order, removes the parent order row as well.
  Future<void> deleteTransaction(int id) async {
    final database = await _database.database;
    final accountId = await _activeId();
    await database.transaction((tx) async {
      final rows = await tx.query(
        'transactions',
        columns: ['order_fk'],
        where: accountId == null ? 'id = ?' : 'id = ? AND account_id = ?',
        whereArgs: accountId == null ? [id] : [id, accountId],
      );
      if (rows.isEmpty) return;
      final orderFk = rows.single['order_fk'] as int?;
      await tx.delete('transactions', where: 'id = ?', whereArgs: [id]);
      if (orderFk != null) {
        final remaining = await tx.query('transactions', columns: ['id'], where: 'order_fk = ?', whereArgs: [orderFk], limit: 1);
        if (remaining.isEmpty) {
          await tx.delete('orders', where: 'id = ?', whereArgs: [orderFk]);
        }
      }
    });
  }

  // ─────────────────────────── M7 joined reads ───────────────────────────

  /// Joined read: item rows joined with their parent order.
  ///
  /// Search semantics (locked):
  /// - Order ID match → all items of that order.
  /// - Product code match → only matching items.
  Future<List<TransactionWithOrder>> listItemsJoined({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final accountId = await _activeId();
    if (accountId == null) return const [];

    final db = await _database.database;
    final clauses = <String>['account_id = ?'];
    final args = <Object?>[accountId];
    if (liveSessionId != null) {
      clauses.add('live_session_id = ?');
      args.add(liveSessionId);
    }
    if (paymentStatus != null) {
      clauses.add('payment_status = ?');
      args.add(paymentStatus.value);
    }
    if (orderStatus != null) {
      clauses.add('order_status = ?');
      args.add(orderStatus.value);
    }
    if (periodStart != null) {
      clauses.add('transaction_date >= ?');
      args.add(Transaction.formatLocalDate(periodStart));
    }
    if (periodEnd != null) {
      clauses.add('transaction_date < ?');
      args.add(Transaction.formatLocalDate(periodEnd));
    }

    final orderRows = await db.query('orders', where: clauses.join(' AND '), whereArgs: args, orderBy: 'transaction_date DESC, id DESC');
    if (orderRows.isEmpty) return const [];

    final orderIds = orderRows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(orderIds.length, '?').join(',');
    final itemRows = await db.query(
      'transactions',
      where: 'order_fk IN ($placeholders)',
      whereArgs: orderIds,
      orderBy: 'order_fk ASC, item_index ASC',
    );

    final itemsByOrder = <int, List<Map<String, Object?>>>{};
    for (final row in itemRows) {
      final fk = row['order_fk'] as int?;
      if (fk == null) continue;
      itemsByOrder.putIfAbsent(fk, () => []).add(row);
    }

    final trimmed = search.trim();
    final result = <TransactionWithOrder>[];
    for (final orderRow in orderRows) {
      final order = Order.fromMap(orderRow);
      final items = itemsByOrder[order.id] ?? const <Map<String, Object?>>[];
      for (final itemRow in items) {
        final item = Transaction.fromMap(itemRow);
        if (trimmed.isEmpty) {
          result.add(TransactionWithOrder(item: item, order: order));
        } else {
          final orderMatch = order.orderId.contains(trimmed);
          final itemMatch = item.productCode.contains(trimmed);
          if (orderMatch || itemMatch) {
            result.add(TransactionWithOrder(item: item, order: order));
          }
        }
      }
    }
    return result;
  }

  /// Item-level update. Never touches sibling items, never touches order-level
  /// fields (those belong to [OrderRepository.update]).
  Future<void> updateItem(Transaction item) async {
    final id = item.id;
    if (id == null) throw ArgumentError.value(id, 'item.id');
    final database = await _database.database;
    final accountId = await _activeId();
    final values = <String, Object?>{
      'product_code': item.productCode,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'gmv_amount': item.gmvAmount,
      'net_income_amount': item.netIncomeAmount,
      'hpp_id': item.hppId,
      'hpp_unit_amount': item.hppUnitAmount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await database.transaction((tx) async {
      final owned = await tx.rawQuery(
        'SELECT t.id FROM transactions t JOIN orders o ON o.id = t.order_fk '
        'WHERE t.id = ? AND o.account_id = ?',
        [id, accountId ?? -1],
      );
      if (owned.isEmpty) throw StateError('Item not found for active account.');
      await tx.update('transactions', values, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Item-level delete. When the last item is removed, the parent order is
  /// deleted as well (locked M7 behavior). Other items remain untouched.
  Future<void> deleteItem(int id) async {
    final database = await _database.database;
    final accountId = await _activeId();
    await database.transaction((tx) async {
      final owned = await tx.rawQuery(
        'SELECT t.order_fk AS order_fk FROM transactions t JOIN orders o ON o.id = t.order_fk '
        'WHERE t.id = ? AND o.account_id = ?',
        [id, accountId ?? -1],
      );
      if (owned.isEmpty) return;
      final orderFk = owned.single['order_fk'] as int?;
      await tx.delete('transactions', where: 'id = ?', whereArgs: [id]);
      if (orderFk != null) {
        final remaining = await tx.query('transactions', columns: ['id'], where: 'order_fk = ?', whereArgs: [orderFk], limit: 1);
        if (remaining.isEmpty) {
          await tx.delete('orders', where: 'id = ?', whereArgs: [orderFk]);
        }
      }
    });
  }
}