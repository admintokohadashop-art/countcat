import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/profile/avatar_storage.dart';
import '../database/app_database.dart';
import '../models/account.dart';

class AccountRepository {
  /// Notification only; the database setting remains the active-account source of truth.
  static final activeAccountChanged = ValueNotifier<int>(0);
  AccountRepository(this._database, {AvatarStorage? avatars})
      : _avatars = avatars ?? AvatarStorage();
  final AppDatabase _database;
  final AvatarStorage _avatars;

  Future<List<Account>> listAccounts() async {
    final db = await _database.database;
    return (await db.query('accounts', orderBy: 'created_at ASC, id ASC')).map(Account.fromMap).toList();
  }

  Future<Account?> activeAccount() async {
    final db = await _database.database;
    final rows = await db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: ['active_account_id']);
    if (rows.isEmpty) return null;
    final id = int.tryParse(rows.single['value'] as String);
    if (id == null) return null;
    final accounts = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    return accounts.isEmpty ? null : Account.fromMap(accounts.single);
  }

  Future<void> setActiveAccountId(int? id) async {
    final db = await _database.database;
    if (id == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: ['active_account_id']);
      activeAccountChanged.value++;
      return;
    }
    await db.insert('settings', {'key': 'active_account_id', 'value': '$id', 'updated_at': DateTime.now().toUtc().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
    activeAccountChanged.value++;
  }

  Future<Account> create({required String name, String description = '', String? photoPath}) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc();
    final id = await db.insert('accounts', {'name': name, 'description': description, 'photo_path': photoPath, 'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String()});
    await setActiveAccountId(id);
    return Account(id: id, name: name, description: description, photoPath: photoPath, createdAt: now, updatedAt: now);
  }

  Future<void> update(Account account) async {
    final db = await _database.database;
    await db.update('accounts', {'name': account.name, 'description': account.description, 'photo_path': account.photoPath, 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'id = ?', whereArgs: [account.id]);
    activeAccountChanged.value++;
  }

  /// Deletes the given account and all data owned by it (M6 + M7 cascade).
  ///
  /// Cascades, inside one DB transaction:
  ///   - orders (M7-A) then transactions (items) — items first because FK is
  ///     not enforced at the DB level during FASE B.
  ///   - live_sessions, hpp_master, account_settings, monthly_reports.
  ///   - accounts row.
  /// Also clears `selected_live_session_id` when it pointed at one of this
  /// account's sessions, and promotes another account to active if needed.
  /// The database file itself is never deleted; avatar deletion is limited to
  /// files CountCat owns.
  Future<void> delete(Account account) async {
    final id = account.id;
    if (id == null) return;
    final db = await _database.database;
    await db.transaction((tx) async {
      // Clear selected session if it belongs to the deleted account.
      final selectedRows = await tx.query('settings', columns: ['value'], where: 'key = ?', whereArgs: ['selected_live_session_id']);
      final selectedSessionId = selectedRows.isEmpty ? null : int.tryParse(selectedRows.single['value'] as String);
      if (selectedSessionId != null) {
        final owned = await tx.query(
          'live_sessions',
          columns: ['id'],
          where: 'id = ? AND account_id = ?',
          whereArgs: [selectedSessionId, id],
        );
        if (owned.isNotEmpty) {
          await tx.delete('settings', where: 'key = ?', whereArgs: ['selected_live_session_id']);
        }
      }

      // M7: items first, then orders (no FK enforced yet).
      await tx.delete('transactions', where: 'account_id = ?', whereArgs: [id]);
      await tx.delete('orders', where: 'account_id = ?', whereArgs: [id]);
      await tx.delete('monthly_reports', where: 'account_id = ?', whereArgs: [id]);
      await tx.delete('live_sessions', where: 'account_id = ?', whereArgs: [id]);
      await tx.delete('hpp_master', where: 'account_id = ?', whereArgs: [id]);
      await tx.delete('account_settings', where: 'account_id = ?', whereArgs: [id]);
      await tx.delete('accounts', where: 'id = ?', whereArgs: [id]);

      final activeRows = await tx.query('settings', columns: ['value'], where: 'key = ?', whereArgs: ['active_account_id']);
      final activeId = activeRows.isEmpty ? null : int.tryParse(activeRows.single['value'] as String);
      if (activeId == id) {
        final remaining = await tx.query('accounts', orderBy: 'created_at ASC, id ASC', limit: 1);
        if (remaining.isEmpty) {
          await tx.delete('settings', where: 'key = ?', whereArgs: ['active_account_id']);
        } else {
          await tx.insert('settings', {
            'key': 'active_account_id',
            'value': '${remaining.single['id']}',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });

    await _avatars.deleteOwned(account.photoPath);
    activeAccountChanged.value++;
  }
}