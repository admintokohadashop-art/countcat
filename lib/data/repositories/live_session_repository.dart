import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'account_repository.dart';
import '../models/live_session.dart';

class SessionInUseException implements Exception {
  const SessionInUseException(this.sessionId, {this.linkedOrderCount = 0});
  final int sessionId;
  final int linkedOrderCount;

  @override
  String toString() =>
      'Session $sessionId is in use by $linkedOrderCount order(s).';
}

class LiveSessionRepository {
  LiveSessionRepository(this._database);
  final AppDatabase _database;

  Future<int?> _activeId() async => (await AccountRepository(_database).activeAccount())?.id;

  Future<LiveSession> createSession({required String name, DateTime? startedAt}) async {
    final now = DateTime.now().toUtc();
    final database = await _database.database;
    final accountId = await _activeId();
    final id = await database.insert('live_sessions', {
      'account_id': accountId,
      'name': name,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    final session = LiveSession(id: id, name: name, startedAt: startedAt?.toUtc(), createdAt: now, updatedAt: now);
    await setSelectedSessionId(id);
    return session;
  }

  Future<List<LiveSession>> listSessions() async {
    final database = await _database.database;
    final accountId = await _activeId();
    final rows = await database.query(
      'live_sessions',
      where: accountId == null ? null : 'account_id = ?',
      whereArgs: accountId == null ? null : [accountId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(LiveSession.fromMap).toList();
  }

  Future<int?> getSelectedSessionId() async {
    final database = await _database.database;
    final rows = await database.query('settings', columns: ['value'], where: 'key = ?', whereArgs: ['selected_live_session_id']);
    return rows.isEmpty ? null : int.tryParse(rows.single['value'] as String);
  }

  Future<void> setSelectedSessionId(int? sessionId) async {
    final database = await _database.database;
    if (sessionId == null) {
      await database.delete('settings', where: 'key = ?', whereArgs: ['selected_live_session_id']);
      return;
    }
    await database.insert('settings', {
      'key': 'selected_live_session_id',
      'value': '$sessionId',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<LiveSession?> getSelectedSession() async {
    final id = await getSelectedSessionId();
    if (id == null) return null;
    final database = await _database.database;
    final rows = await database.query('live_sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LiveSession.fromMap(rows.single);
  }

  /// Edit name and started_at only. Session id never changes, and linked
  /// orders keep pointing at the same live_sessions row.
  Future<void> updateSession({required int id, required String name, required DateTime startedAt}) async {
    final accountId = await _activeId();
    if (accountId == null) return;
    final database = await _database.database;
    await database.update(
      'live_sessions',
      {
        'name': name,
        'started_at': startedAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND account_id = ?',
      whereArgs: [id, accountId],
    );
  }

  /// Under M7-A, session usage is determined through orders.live_session_id.
  /// Returns true if any order of the active account references the session.
  Future<bool> hasTransactions(int sessionId) async {
    final accountId = await _activeId();
    if (accountId == null) return false;
    final database = await _database.database;
    final rows = await database.query(
      'orders',
      columns: ['id'],
      where: 'account_id = ? AND live_session_id = ?',
      whereArgs: [accountId, sessionId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Deletes the session in a single transaction.
  /// - Refuses when linked orders exist.
  /// - Clears / falls back `selected_live_session_id` when the deleted session
  ///   was the selected one.
  Future<void> deleteSession(int sessionId) async {
    final accountId = await _activeId();
    if (accountId == null) throw StateError('No active account.');
    final database = await _database.database;
    await database.transaction((tx) async {
      final sessionRows = await tx.query(
        'live_sessions',
        where: 'id = ? AND account_id = ?',
        whereArgs: [sessionId, accountId],
      );
      if (sessionRows.isEmpty) {
        throw StateError('Session not found for active account.');
      }
      final linkedOrders = await tx.query(
        'orders',
        columns: ['id'],
        where: 'account_id = ? AND live_session_id = ?',
        whereArgs: [accountId, sessionId],
      );
      if (linkedOrders.isNotEmpty) {
        throw SessionInUseException(sessionId, linkedOrderCount: linkedOrders.length);
      }
      await tx.delete('live_sessions', where: 'id = ? AND account_id = ?', whereArgs: [sessionId, accountId]);

      final selectedRows = await tx.query('settings', columns: ['value'], where: 'key = ?', whereArgs: ['selected_live_session_id']);
      final selectedId = selectedRows.isEmpty ? null : int.tryParse(selectedRows.single['value'] as String);
      if (selectedId == sessionId) {
        final remaining = await tx.query(
          'live_sessions',
          columns: ['id'],
          where: 'account_id = ?',
          whereArgs: [accountId],
          orderBy: 'started_at DESC, id DESC',
          limit: 1,
        );
        if (remaining.isEmpty) {
          await tx.delete('settings', where: 'key = ?', whereArgs: ['selected_live_session_id']);
        } else {
          await tx.insert('settings', {
            'key': 'selected_live_session_id',
            'value': '${remaining.single['id']}',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}