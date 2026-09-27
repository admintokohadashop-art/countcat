import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseException;

import '../database/app_database.dart';
import '../models/statuses.dart';
import '../models/transaction.dart';

class DuplicateOrderIdException implements Exception {
  const DuplicateOrderIdException(this.orderId);
  final String orderId;
}

class TransactionRepository {
  TransactionRepository(this._database);
  final AppDatabase _database;

  Future<int> insertTransaction(Transaction transaction) async {
    try {
      final database = await _database.database;
      final values = Map<String, Object?>.from(transaction.toMap())..remove('id');
      return await database.insert('transactions', values);
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateOrderIdException(transaction.orderId);
      rethrow;
    }
  }

  Future<List<Transaction>> listTransactions({String search = '', int? liveSessionId, PaymentStatus? paymentStatus, OrderStatus? orderStatus, DateTime? periodStart, DateTime? periodEnd}) async {
    final clauses = <String>[];
    final arguments = <Object?>[];
    final trimmedSearch = search.trim();
    if (trimmedSearch.isNotEmpty) {
      clauses.add('(order_id LIKE ? OR product_code LIKE ?)');
      arguments..add('%$trimmedSearch%')..add('%$trimmedSearch%');
    }
    if (liveSessionId != null) { clauses.add('live_session_id = ?'); arguments.add(liveSessionId); }
    if (paymentStatus != null) { clauses.add('payment_status = ?'); arguments.add(paymentStatus.value); }
    if (orderStatus != null) { clauses.add('order_status = ?'); arguments.add(orderStatus.value); }
    if (periodStart != null) { clauses.add('created_at >= ?'); arguments.add(periodStart.toUtc().toIso8601String()); }
    if (periodEnd != null) { clauses.add('created_at < ?'); arguments.add(periodEnd.toUtc().toIso8601String()); }
    final database = await _database.database;
    final rows = await database.query('transactions', where: clauses.isEmpty ? null : clauses.join(' AND '), whereArgs: arguments, orderBy: 'created_at DESC, id DESC');
    return rows.map(Transaction.fromMap).toList();
  }

  Future<void> deleteTransaction(int id) async {
    final database = await _database.database;
    await database.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateTransaction(Transaction transaction) async {
    final id = transaction.id;
    if (id == null) throw ArgumentError.value(id, 'transaction.id');
    try {
      final values = Map<String, Object?>.from(transaction.toMap())
        ..remove('id')
        ..remove('created_at')
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
      final database = await _database.database;
      await database.update('transactions', values, where: 'id = ?', whereArgs: [id], conflictAlgorithm: ConflictAlgorithm.abort);
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateOrderIdException(transaction.orderId);
      rethrow;
    }
  }
}
