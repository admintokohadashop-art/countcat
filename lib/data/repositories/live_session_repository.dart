import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'account_repository.dart';
import '../models/live_session.dart';

class LiveSessionRepository {
  LiveSessionRepository(this._database);
  final AppDatabase _database;
  Future<int?> _activeId() async => (await AccountRepository(_database).activeAccount())?.id;

  Future<LiveSession> createSession({required String name, DateTime? startedAt}) async {
    final now = DateTime.now().toUtc();
    final database = await _database.database;
    final accountId = await _activeId();
    final id = await database.insert('live_sessions', {'account_id': accountId, 'name': name, 'started_at': startedAt?.toUtc().toIso8601String(), 'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String()});
    final session = LiveSession(id: id, name: name, startedAt: startedAt?.toUtc(), createdAt: now, updatedAt: now);
    await setSelectedSessionId(id);
    return session;
  }

  Future<List<LiveSession>> listSessions() async {
    final database = await _database.database;
    final accountId = await _activeId();
    final rows = await database.query('live_sessions', where: accountId == null ? null : 'account_id = ?', whereArgs: accountId == null ? null : [accountId], orderBy: 'created_at DESC, id DESC');
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
    await database.insert('settings', {'key': 'selected_live_session_id', 'value': '$sessionId', 'updated_at': DateTime.now().toUtc().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<LiveSession?> getSelectedSession() async {
    final id = await getSelectedSessionId();
    if (id == null) return null;
    final database = await _database.database;
    final rows = await database.query('live_sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LiveSession.fromMap(rows.single);
  }
}
